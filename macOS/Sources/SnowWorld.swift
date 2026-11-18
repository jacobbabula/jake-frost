import Foundation

/// Each display has its own stream so spawning particles doesn't request system
/// entropy for every size, velocity and position.
struct SnowRandom {
    var state: UInt64
    mutating func between(_ low:CGFloat,_ high:CGFloat) -> CGFloat {
        state &+= 0x9E3779B97F4A7C15
        var n=state
        n=(n ^ (n>>30)) &* 0xBF58476D1CE4E5B9
        n=(n ^ (n>>27)) &* 0x94D049BB133111EB
        n ^= n>>31
        return low + (high-low)*CGFloat(n>>11)/9_007_199_254_740_992
    }
}

final class MacPlowLoad {
    weak var bank: Drift?
    var samples = [(bin:Int, bed:CGFloat, added:CGFloat)]()
    var carry:CGFloat=0
}

final class Drift {
    var edge: SnowEdge
    private(set) var depth: [CGFloat]
    private(set) var revision: UInt = 0
    private(set) var maximumDepth: CGFloat
    var spacing: CGFloat { edge.width / CGFloat(depth.count - 1) }

    init(_ edge: SnowEdge) {
        self.edge = edge
        maximumDepth = edge.id == 0 ? 55 : 27
        let count = max(3, Int(ceil(edge.width / 10)) + 1)
        depth = (0..<count).map { i in
            edge.id == 0 ? 3.5 + 1.5 * sin(CGFloat(i) * 0.18) : 0
        }
    }

    func height(_ x: CGFloat) -> CGFloat {
        let t = min(CGFloat(depth.count - 1), max(0, (x-edge.x)/spacing))
        let i = Int(t), f = t - CGFloat(i)
        return depth[i] + (depth[min(i+1,depth.count-1)] - depth[i]) * f
    }
    func surface(_ x: CGFloat) -> CGFloat { edge.y - height(x) }
    func setDepthLimit(_ floorLimit: CGFloat) {
        let limit = edge.id == 0 ? floorLimit : (floorLimit * 27 / 55).rounded()
        guard limit != maximumDepth else { return }
        maximumDepth = limit
        for i in depth.indices { depth[i] = min(limit,depth[i]) }
        revision &+= 1
    }
    @discardableResult func add(at x: CGFloat, amount: CGFloat, spread: Int = 2) -> CGFloat {
        let mid = min(depth.count-1,max(0,Int(((x-edge.x)/spacing).rounded())))
        var changed: CGFloat = 0
        for i in max(0,mid-spread)...min(depth.count-1,mid+spread) {
            let weight = CGFloat(spread+1-abs(i-mid))/CGFloat(spread+1)
            let cap = edge.id == 0 ? maximumDepth : min(maximumDepth, 1.5+CGFloat(min(i,depth.count-1-i))*spacing*0.55)
            let next = min(cap,max(0,depth[i] + amount*weight))
            changed += next - depth[i]; depth[i] = next
        }
        if changed != 0 { revision &+= 1 }
        return changed
    }
    func move(to next: SnowEdge) {
        guard edge != next else { return }
        if abs(next.width-edge.width) > 0.5 {
            let count = max(3, Int(ceil(next.width/10))+1)
            depth = (0..<count).map { height(edge.x + edge.width*CGFloat($0)/CGFloat(count-1)) }
        }
        edge = next; revision &+= 1
    }
    func clear() { depth = Array(repeating:0,count:depth.count); revision &+= 1 }
    func settle(area:CGFloat,at x:CGFloat) {
        let dx=spacing, radius=max(1.8*dx,1.55*sqrt(area))
        let first=max(0,Int(ceil((x-radius-edge.x)/dx)))
        let last=min(depth.count-1,Int(floor((x+radius-edge.x)/dx)))
        guard area>0,first<=last else{return}
        func weight(_ i:Int)->CGFloat {
            let u=(edge.x+CGFloat(i)*dx-x)/radius, a=max(0,1-u*u)
            return a*a
        }
        var total:CGFloat=0
        for i in first...last {total+=weight(i)}
        guard total>0 else{return}
        for i in first...last {
            let cap=edge.id==0 ? maximumDepth:min(maximumDepth,1.5+CGFloat(min(i,depth.count-1-i))*dx*0.55)
            depth[i]=min(cap,depth[i]+area*weight(i)/(total*dx))
        }
        revision &+= 1
    }
    /// Cut each covered column down to a shallow road and move the reclaimed
    /// powder forward into a long, angle-limited bank. Never refill the wheel lane.
    func plowLane(rear: CGFloat, lip: CGFloat, scale: CGFloat, load:MacPlowLoad) -> CGFloat {
        guard edge.id == 0,max(rear,lip)>=edge.x,min(rear,lip)<=edge.x+edge.width else{return 0}
        let sign=lip>=rear ? 1 : -1,dx=spacing
        let left=max(0,Int(ceil((min(rear,lip)-edge.x)/dx)))
        let right=min(depth.count-1,Int(floor((max(rear,lip)-edge.x)/dx)))
        guard left<=right else {return 0}
        let carriedBefore = !load.samples.isEmpty
        if load.bank===self {
            for entry in load.samples where depth.indices.contains(entry.bin) {
                let lift=min(entry.added,max(0,depth[entry.bin]-entry.bed))
                depth[entry.bin]-=lift;load.carry+=lift
            }
        } else {load.bank=self;load.carry=0}
        load.samples.removeAll(keepingCapacity:true)
        let road:CGFloat=1.1
        var removed:CGFloat=0
        for i in left...right where depth[i]>road {removed+=depth[i]-road;depth[i]=road}
        let first=sign>0 ? right+1:left-1
        func distance(_ i:Int)->CGFloat {(edge.x+CGFloat(i)*dx-lip)*CGFloat(sign)}
        var i=first,incoming:CGFloat=0
        while depth.indices.contains(i),distance(i)<=max(16*dx,95*scale) {
            if distance(i)>2*dx && depth[i]<0.25 {break}
            incoming=max(incoming,depth[i]);i+=sign
        }
        let bite=max(dx*7,3.15*incoming+18*scale)
        i=first
        while depth.indices.contains(i),distance(i)<bite {
            let t=max(0,distance(i)/bite),cap=road+incoming*t*t*(3-2*t)
            let cut=max(0,depth[i]-cap)
            if cut<0.001 && distance(i)>2*dx {break}
            removed+=cut;depth[i]-=cut;i+=sign
        }
        load.carry+=removed
        let height=min(10.4*scale,sqrt(load.carry*dx*0.36)),reach=max(4.5*dx,19*scale+3.7*height)
        let crest=max(0.78*dx,5.2*scale)
        func profile(_ d:CGFloat)->CGFloat {
            if d<=crest {let t=max(0,d/crest);return 0.82+0.18*t*t*(3-2*t)}
            let u=min(1,(d-crest)/(reach-crest));return (1-u)*(1-u)*(1+2*u)
        }
        load.carry=min(load.carry,10.4*scale*reach*0.82/dx)
        var weight:CGFloat=0
        i=first
        while depth.indices.contains(i),distance(i)<reach {weight+=profile(distance(i));i+=sign}
        let amplitude=min(height,load.carry/max(1,weight))
        i=first
        while depth.indices.contains(i),distance(i)<reach {
            let bed=depth[i],added=min(maximumDepth-bed,amplitude*profile(distance(i)))
            if added>0.0001 {load.samples.append((i,bed,added));depth[i]+=added;load.carry-=added}
            i+=sign
        }
        load.carry=max(0,load.carry)
        if removed>0 || carriedBefore || !load.samples.isEmpty {revision &+= 1}
        return removed
    }
}

struct SnowParticle {
    var x, y, vx, vy, radius, phase: CGFloat
    var powder = false
    var life: CGFloat = 1
    var wisp = false
}

final class PackedBall {
    var x, y, radius: CGFloat
    var vx: CGFloat = 0, vy: CGFloat = 0
    var thrown = false
    weak var below: PackedBall?
    weak var above: PackedBall?
    var support: UInt32?
    var supportFraction: CGFloat = 0
    init(_ x: CGFloat,_ y: CGFloat,_ radius: CGFloat) { self.x=x; self.y=y; self.radius=radius }
}

final class BuiltSnowman {
    var x, foot: CGFloat
    let base, middle, head: CGFloat
    let style: Int, facing: CGFloat
    var giftID: String?
    var support: UInt32?, supportFraction: CGFloat
    var vx: CGFloat = 0, vy: CGFloat = 0
    var thrown = false
    var guest = false

    init(saved: SavedSnowman, desktop: CGSize) {
        x = saved.x*desktop.width; foot = saved.foot*desktop.height
        base = saved.base; middle = saved.middle; head = saved.head
        style = saved.style; facing = saved.facing; supportFraction = saved.fraction
        giftID = saved.giftID
    }
    init(gift: FrostGift, foot point: CGPoint) {
        x = point.x; foot = point.y; supportFraction = 0
        base = CGFloat(gift.size); middle = CGFloat(gift.mid); head = CGFloat(gift.head)
        style = gift.style; facing = CGFloat(gift.facing); giftID = gift.id
    }

    init(bottom: PackedBall, middleBall: PackedBall, headBall: PackedBall) {
        x = bottom.x; foot = bottom.y + bottom.radius
        support = bottom.support; supportFraction = bottom.supportFraction
        base = bottom.radius; middle = middleBall.radius; head = headBall.radius
        style = Int.random(in:0..<3); facing = Bool.random() ? 1 : -1
    }

    var reach: CGFloat { max(max(base, middle), head*1.08) }
    var hitBounds: CGRect {
        let torso = foot-base-0.78*(base+middle), face = torso-0.78*(middle+head)
        let top = min(foot-2*base, min(torso-middle, face-1.88*head))
        let bottom = max(foot, max(torso+middle, face+head))
        return CGRect(x:x-reach,y:top,width:2*reach,height:bottom-top)
    }
    func contains(_ point: CGPoint, padding: CGFloat = 1) -> Bool {
        let dx = abs(point.x-x), dy = point.y-foot
        guard dx <= reach+padding else {return false}
        let torso = -base - 0.78*(base+middle), face = torso - 0.78*(middle+head)
        return hypot(dx,dy+base) <= base+padding || hypot(dx,dy-torso) <= middle+padding ||
            hypot(dx,dy-face) <= head+padding || (dx <= head*0.72+padding && dy >= face-head*1.88-padding && dy <= face-head*0.77+padding) ||
            (dx <= head*1.08+padding && dy >= face-head-padding && dy <= face-head*0.77+padding)
    }
}

final class SnowWorld {
    private(set) var size = CGSize.zero
    private(set) var banks = [Drift]()
    private var byID = [UInt32:Drift]()
    private var collisionRows = [[Drift]]()
    private static let rowHeight: CGFloat = 64
    private var powderCount = 0
    private(set) var fragments = [MacSnowFragment]()
    let battle = MacSnowBattle()
    var battlePace:CGFloat = 1
    var hasMotion: Bool {
        (!paused && snowEnabled && (amount > 0 || !particles.isEmpty)) || powderCount > 0 ||
            battle.active || !fragments.isEmpty || balls.contains { ($0.support == nil || $0.vx != 0) && $0.below == nil } || snowmen.contains { $0.support == nil }
    }
    private(set) var particles = [SnowParticle]()
    private(set) var balls = [PackedBall]()
    private(set) var snowmen = [BuiltSnowman]()
    private var snowmanStore: SnowmanStore?
    private weak var heldSnowman: BuiltSnowman?
    private var spawnBudget: CGFloat = 0
    private var random = SnowRandom(state:UInt64.random(in:1...UInt64.max))
    var amount: CGFloat = 1
    var wind: CGFloat = 0
    var snowEnabled = true {
        didSet {
            if oldValue && !snowEnabled {
                particles.removeAll { !$0.powder }
                spawnBudget = 0
            }
        }
    }
    private(set) var depthLimit: CGFloat = 55
    func setAccumulation(_ value: CGFloat) {
        let limit = min(320,max(24,value))
        guard limit != depthLimit else { return }
        depthLimit = limit
        for bank in banks { bank.setDepthLimit(limit) }
        rebuildRows()
    }
    var paused = false
    private var start: CGPoint?, last = CGPoint.zero
    private var initialBank: Drift?, held: PackedBall?, ballOffset = CGPoint.zero
    private var samples = [(CGPoint,TimeInterval)]()
    private var explicitThrow = false

    func configureSnowmanStorage(settings: UserDefaults, displayID: UInt32) {
        if let store=snowmanStore, store.settings === settings, store.key == "snowmen.v1.\(displayID)" { return }
        let store = SnowmanStore(settings:settings,displayID:displayID)
        snowmanStore = store
        if size.width > 1 { snowmen = store.restore(in:size,banks:banks) }
    }
    func rememberSnowmenNow() { snowmanStore?.save(snowmen.filter{!$0.guest},size:size) }
    @discardableResult func plowObjects(_ blade: PlowSweep) -> Bool {
        guard let floor=byID[0] else {return false}
        func circle(_ b: PackedBall) -> Bool {
            let r=b.radius
            return blade.touches(CGRect(x:b.x-r,y:b.y-r,width:2*r,height:2*r),includingSnow:b.support==0) { hypot($0.x-b.x,$0.y-b.y)<=r }
        }
        for b in balls where b !== held && b.below == nil && (b.support == nil || b.support == 0) {
            guard circle(b) || b.above.map(circle)==true else {continue}
            b.x=max(b.radius,min(max(b.radius,size.width-b.radius),b.x+blade.advance+0.6*blade.direction))
            b.thrown=false;rest(b,on:floor);positionUpperBall(on:b)
        }
        var moved=false
        for figure in snowmen where figure !== heldSnowman && (figure.support == nil || figure.support == 0) {
            guard blade.touches(figure.hitBounds,includingSnow:figure.support==0,ink:{ figure.contains($0,padding:0) }) else {continue}
            let x=max(figure.reach,min(max(figure.reach,size.width-figure.reach),figure.x+blade.advance+0.6*blade.direction))
            if x != figure.x {figure.x=x;settle(figure,on:floor);moved=true}
        }
        return moved
    }
    func containsReceivedGift(_ id: String) -> Bool { snowmen.contains { $0.giftID == id } }
    func receiveSnowman(_ gift: FrostGift, at foot: CGPoint) -> Bool {
        guard gift.kind == .snowman else { return false }
        if containsReceivedGift(gift.id) { return true }
        guard let floor = byID[0], balls.count+snowmen.count < 55 else { return false }
        let figure = BuiltSnowman(gift:gift,foot:foot)
        settle(figure,on:floor);snowmen.append(figure);rememberSnowmenNow()
        return true
    }

    func setDesktop(size newSize: CGSize, edges: [SnowEdge]) {
        guard newSize.width > 1 && newSize.height > 1 else { return }
        let first = size == .zero
        size = newSize
        let floor = SnowEdge(id: 0, x: 0, y: size.height, width: size.width, visible: [0...size.width])
        // Keep the snow on each exposed window as its position and size change.
        var next = [UInt32:Drift]()
        for edge in [floor] + edges {
            if let bank = byID[edge.id] { bank.move(to: edge); next[edge.id]=bank }
            else {
                let bank = Drift(edge)
                bank.setDepthLimit(depthLimit)
                next[edge.id] = bank
            }
        }
        byID=next; banks=([floor]+edges).compactMap { next[$0.id] }
        if let store = snowmanStore, !store.loaded { snowmen = store.restore(in:size,banks:banks) }
        rebuildRows()
        if first && snowEnabled && amount>0 {
            for _ in 0..<min(280,Int(size.width*0.08)) { spawn(randomHeight:true) }
        }
    }
    private func rebuildRows() {
        collisionRows = Array(repeating: [], count: max(1,Int(size.height / Self.rowHeight)+1))
        for bank in banks {
            let firstRow = row(bank.edge.y - bank.maximumDepth)
            let lastRow = row(bank.edge.y + 1.2)
            for r in firstRow...lastRow { collisionRows[r].append(bank) }
        }
    }

    private func spawn(randomHeight: Bool) {
        let r=random.between(0.8,2.5)
        particles.append(SnowParticle(x:random.between(0,size.width),y:randomHeight ? random.between(0,size.height) : -3,
                         vx:random.between(-6,8),vy:18+12*r,radius:r,phase:random.between(0,6.28)))
    }

    func burst(_ point: CGPoint, count: Int, strength: CGFloat = 1) {
        guard particles.count < 1800 else { return }
        let added = max(0,min(count,1800-particles.count))
        powderCount += added
        for i in 0..<added {
            let wisp=i%8 == 0
            particles.append(SnowParticle(x:point.x,y:point.y,vx:random.between(-70,70)*strength,
                vy:random.between(-112,-23)*strength*(wisp ? 0.58 : 1),radius:wisp ? random.between(5,8)*strength : random.between(1,2.7),
                phase:0,powder:true,life:random.between(0.45,0.85),wisp:wisp))
        }
    }

    // Falling flakes are visual-only. A normal click can disturb them without making
    // the overlay handle that event; a selected brush also disturbs nearby banks.
    @discardableResult func puff(at point:CGPoint,brush:Bool)->Bool {
        let reach:CGFloat=brush ? 26 : 7
        var hits=0
        for i in particles.indices where !particles[i].powder {
            let flake=particles[i],dx=flake.x-point.x,dy=flake.y-point.y,r=reach+flake.radius
            if dx*dx+dy*dy>r*r {continue}
            particles[i].powder=true;particles[i].life = .random(in:0.45...0.85)
            particles[i].vx=dx*4 + .random(in:-52...52);particles[i].vy = .random(in:-155 ... -65)
            hits+=1
        }
        powderCount+=hits
        var origin=point, removed:CGFloat=0
        if brush,let bank=banks.filter({$0.edge.contains(point.x) && $0.height(point.x)>0.45 &&
            point.y >= $0.surface(point.x)-26 && point.y <= $0.edge.y+6})
            .min(by:{abs($0.surface(point.x)-point.y)<abs($1.surface(point.x)-point.y)}) {
            origin.y=bank.surface(point.x)
            removed = -bank.add(at:point.x,amount:-6,spread:3)
        }
        guard brush || hits>0 else {return false}
        let hit = hits>0 || removed>0
        burst(origin,count:hit ? min(31,11+Int(removed)) : 7,strength:hit ? 1 : 0.53)
        return true
    }

    private func row(_ y: CGFloat) -> Int {
        max(0, min(collisionRows.count - 1, Int(y / Self.rowHeight)))
    }
    func intercept(x:CGFloat, previous:CGFloat, next:CGFloat, embedded:Bool=false) -> Drift? {
        guard next>=previous,!collisionRows.isEmpty else{return nil}
        var bank: Drift?, earliest = CGFloat.greatestFiniteMagnitude
        let first = row(previous), last = row(next)
        // A normal flake crosses at most one row boundary. Keep the original bank
        // order for long sweeps, including a fast snowball passing several ledges.
        for d in (first == last ? collisionRows[first] : banks) {
            guard previous <= d.edge.y + 1.2, next >= d.edge.y - d.maximumDepth,
                  x >= d.edge.x, x <= d.edge.x + d.edge.width, d.edge.contains(x) else { continue }
            let y=d.surface(x)
            if (embedded || previous <= y+1.2) && next >= y && y < earliest { earliest=y;bank=d }
        }
        return bank
    }

    func step(_ seconds: TimeInterval) {
        guard size.width>1 else { return }
        let dt=CGFloat(min(0.08,max(0,seconds)))
        if !paused && snowEnabled {
            spawnBudget += dt*amount*size.width*0.023
            while spawnBudget>=1 { if particles.count<1600 {spawn(randomHeight:false)};spawnBudget-=1 }
        }
        if !paused || powderCount > 0 { stepParticles(dt) }
        stepFragments(dt)
        if !paused {battle.step(dt,world:self)}
        for b in balls where b !== held && b.below == nil {
            if b.thrown { advanceThrow(b,dt:dt);continue }
            if let id=b.support,let d=byID[id] {
                let anchor=d.edge.x+b.supportFraction*d.edge.width
                let slope=(d.surface(anchor+b.radius*0.5)-d.surface(anchor-b.radius*0.5))/max(1,b.radius)
                if abs(slope)>0.16 || abs(b.vx)>2 {b.vx+=max(-1,min(1,slope))*260*dt}
                b.vx *= max(0,1-0.65*dt)
                b.vx = (b.vx<0 ? -1:1)*max(0,abs(b.vx)-14*dt)
                let x=max(b.radius,min(max(b.radius,size.width-b.radius),anchor+b.vx*dt))
                b.x=x
                if d.edge.contains(x) {
                    if x==b.radius || x==size.width-b.radius {b.vx=0}
                    b.supportFraction=(x-d.edge.x)/d.edge.width;b.y=d.surface(x)-b.radius
                    positionUpperBall(on:b);continue
                }
            }
            b.support=nil
            let old=b.y+b.radius;b.vy+=340*dt;b.x+=b.vx*dt;b.y+=b.vy*dt
            let bank=intercept(x:b.x,previous:old,next:b.y+b.radius)
            let nextFoot=min(b.y+b.radius,bank?.surface(b.x) ?? size.height)
            if (abs(b.vx)>100 || b.vy>=175), hitFigure(b) {splat(b,nil);continue}
            if b.vy>=0 && b.vy<230 && tryStack(b,previous:old,next:nextFoot,byHand:false) {continue}
            if let d=bank {
                if b.vy>=175 {b.y=d.surface(b.x)-b.radius;splat(b,d);continue}
                rest(b,on:d)
            } else if b.y+b.radius>=size.height || b.x < -b.radius || b.x > size.width+b.radius {
                if let floor=byID[0] {
                    b.x=min(max(b.radius,b.x),size.width-b.radius)
                    if b.vy>=175 {b.y=floor.surface(b.x)-b.radius;splat(b,floor);continue}
                    rest(b,on:floor)
                }
            }
            positionUpperBall(on:b)
        }
        var landed = false
        for figure in snowmen where figure !== heldSnowman {
            if let id=figure.support,let bank=byID[id] {
                let x=bank.edge.x+figure.supportFraction*bank.edge.width
                if bank.edge.contains(x) {figure.x=x;figure.foot=bank.surface(x);continue}
            }
            figure.support=nil
            if advanceFigure(figure,dt) {landed=true}
        }
        if landed { rememberSnowmenNow() }
    }
    private func stepParticles(_ dt:CGFloat) {
        let wind=self.wind, paused=self.paused, bottom=size.height+6, right=size.width+15
        var kept=0, expiredPowder=0
        // Compact survivors in a single pass and truncate the array once per frame.
        particles.withUnsafeMutableBufferPointer { buffer in
            for i in buffer.indices {
                var p=buffer[i]
                if !paused || p.powder {
                    let previous=p.y
                    if p.powder {p.vy+=(p.wisp ? 38:170)*dt;p.life-=dt}
                    else {p.phase+=dt;p.x+=(sin(p.phase)*11+wind)*dt}
                    p.x+=p.vx*dt;p.y+=p.vy*dt
                    if !p.powder, let d=intercept(x:p.x,previous:previous,next:p.y) {
                        d.add(at:p.x,amount:0.28+p.radius*0.25);continue
                    }
                    if p.y>bottom || p.life<=0 || p.x < -15 || p.x>right {
                        if p.powder {expiredPowder+=1}
                        continue
                    }
                }
                buffer[kept]=p;kept+=1
            }
        }
        powderCount-=expiredPowder
        particles.removeLast(particles.count-kept)
    }

    private func rest(_ b: PackedBall,on bank:Drift) {
        b.y=bank.surface(b.x)-b.radius;b.vx=0;b.vy=0;b.support=bank.edge.id
        b.supportFraction=(b.x-bank.edge.x)/bank.edge.width
    }
    private func settle(_ figure: BuiltSnowman,on bank:Drift) {
        figure.support=bank.edge.id;figure.supportFraction=(figure.x-bank.edge.x)/bank.edge.width
        figure.foot=bank.surface(figure.x);figure.vy=0;figure.vx=0;figure.thrown=false
    }
    private func positionUpperBall(on bottom:PackedBall) {
        if let upper=bottom.above {
            upper.x=bottom.x;upper.y=bottom.y-0.78*(upper.radius+bottom.radius)
        }
    }
    private func tryStack(_ b:PackedBall,previous:CGFloat,next:CGFloat,byHand:Bool)->Bool {
        guard b.above == nil else {return false}
        var target:PackedBall?, best=CGFloat.greatestFiniteMagnitude
        for candidate in balls where candidate !== b && candidate !== held && candidate.above == nil {
            let bottom=candidate.below ?? candidate
            guard bottom.support != nil else {continue}
            let dx=abs(b.x-candidate.x), crown=candidate.y-candidate.radius
            if byHand {
                guard dx <= max(24,(bottom.radius+b.radius)*0.93),
                      b.y >= crown-b.radius-22, b.y <= bottom.y+bottom.radius+6 else {continue}
            } else {
                guard dx <= max(8,(b.radius+candidate.radius)*0.6),previous <= crown+2,next >= crown else {continue}
            }
            let score=dx+abs(previous-crown)*0.28
            if score<best {best=score;target=candidate}
        }
        guard let middle=target else {return false}
        if let bottom=middle.below {
            snowmen.append(BuiltSnowman(bottom:bottom,middleBall:middle,headBall:b))
            balls.removeAll { $0 === bottom || $0 === middle || $0 === b }
            rememberSnowmenNow()
        } else {
            middle.above=b;b.below=middle;b.vx=0;b.vy=0;b.support=nil
            positionUpperBall(on:middle)
        }
        return true
    }
    private func splat(_ b: PackedBall,_ bank:Drift?) {
        scatter(x:b.x,y:b.y,r:b.radius,vx:b.vx,speed:hypot(b.vx,b.vy),contact:bank)
        b.above?.below=nil;b.below?.above=nil;balls.removeAll { $0 === b }
    }
    private func advanceThrow(_ b:PackedBall,dt:CGFloat) {
        b.vy += 340*dt
        let steps=max(1,Int(ceil(max(abs(b.vx),abs(b.vy))*dt/7)))
        let slice=dt/CGFloat(steps)
        for _ in 0..<steps {
            let previous=b.y+b.radius
            b.x += b.vx*slice;b.y += b.vy*slice
            let bank=intercept(x:b.x,previous:previous,next:b.y+b.radius)
            if hitFigure(b) {splat(b,nil);return}
            if bank != nil || b.x <= b.radius || b.x+b.radius >= size.width || b.y <= b.radius || b.y+b.radius >= size.height {
                b.x=max(1,min(size.width-1,b.x));b.y=max(1,min(size.height-1,b.y))
                if let d=bank {b.y=d.surface(b.x)-b.radius}
                splat(b,bank);return
            }
        }
    }
    private func snowyBank(_ p:CGPoint)->Drift? {
        banks.first { d in
            d.edge.contains(p.x) && d.height(p.x)>0.7 && p.y>=d.surface(p.x)-2 && p.y<=d.edge.y+1
        }
    }
    private func ball(_ p:CGPoint)->PackedBall? {
        balls.reversed().first { hypot(p.x-$0.x,p.y-$0.y)<=$0.radius+1 }
    }
    func hit(_ p:CGPoint)->Bool {snowmen.contains { $0.contains(p) } || ball(p) != nil || snowyBank(p) != nil}
    @discardableResult func down(_ p:CGPoint,at t:TimeInterval)->Bool {
        cancel()
        if let figure=snowmen.reversed().first(where:{$0.contains(p)}) {
            heldSnowman=figure;start=p;ballOffset=CGPoint(x:figure.x-p.x,y:figure.foot-p.y)
            figure.support=nil;figure.vy=0;figure.vx=0;figure.thrown=false;last=p;samples=[(p,t)];return true
        }
        let b=ball(p), d=snowyBank(p)
        guard b != nil || d != nil else {return false}
        start=p;last=p;initialBank=d;held=b;samples=[(p,t)]
        if let b=b {
            b.above?.below=nil;b.below?.above=nil;b.above=nil;b.below=nil
            ballOffset=CGPoint(x:b.x-p.x,y:b.y-p.y);b.support=nil;b.vx=0;b.vy=0;b.thrown=false
        }
        return true
    }
    func drag(_ p:CGPoint,at t:TimeInterval) {
        guard let origin=start else{return}
        if let figure=heldSnowman {
            figure.x=max(0,min(size.width,p.x+ballOffset.x))
            figure.foot=max(0,min(byID[0]?.surface(figure.x) ?? size.height,p.y+ballOffset.y))
            last=p;samples.append((p,t));samples.removeAll{t-$0.1>0.14};return
        }
        if held==nil {
            guard hypot(p.x-origin.x,p.y-origin.y)>=4,balls.count+snowmen.count<55 else{return}
            let b=PackedBall(origin.x,origin.y-7,7);balls.append(b);held=b;ballOffset=CGPoint(x:0,y:-6)
        }
        guard let b=held else{return}
        let dx=p.x-last.x
        if abs(dx)>0.5 {
            let n=min(32,max(1,Int(abs(dx)/4)))
            for j in 1...n {
                let f=CGFloat(j)/CGFloat(n),x=last.x+dx*f,y=last.y+(p.y-last.y)*f
                if b.radius < 76, let d=banks.first(where:{ $0.edge.contains(x) && abs($0.surface(x)-y)<b.radius+11 }) {
                    let taken = -d.add(at:x,amount:-min(2,abs(dx)/CGFloat(n)*0.12),spread:1)
                    b.radius=min(76,sqrt(b.radius*b.radius+taken*6))
                }
            }
        }
        b.x=p.x+ballOffset.x;b.y=min(size.height-b.radius,p.y+ballOffset.y)
        if let floor=byID[0] {b.y=min(b.y,floor.surface(b.x)-b.radius)}
        last=p;samples.append((p,t));samples.removeAll{t-$0.1>0.14}
    }
    func up(_ p:CGPoint,at t:TimeInterval) {
        guard start != nil else{return}
        drag(p,at:t)
        var vx:CGFloat=0,vy:CGFloat=0
        if let first=samples.first {
            let elapsed=CGFloat(max(0.04,t-first.1))
            vx=(p.x-first.0.x)/elapsed;vy=(p.y-first.0.y)/elapsed
        }
        let speed=hypot(vx,vy), releaseSpeed:CGFloat=explicitThrow ? 55:175
        if let figure=heldSnowman {
            if speed>releaseSpeed {
                let k=min(1,920/speed);figure.thrown=true;figure.vx=vx*k;figure.vy=vy*k
            } else if let bank=banks.filter({$0.edge.contains(figure.x) && abs($0.surface(figure.x)-figure.foot)<9})
                .min(by:{abs($0.surface(figure.x)-figure.foot)<abs($1.surface(figure.x)-figure.foot)}) {
                settle(figure,on:bank)
            }
        } else if let b=held {
            let support=banks.first{$0.edge.contains(b.x) && abs($0.surface(b.x)-(b.y+b.radius))<7}
            let rolling = !explicitThrow && support != nil && abs(vy)<abs(vx)*0.45
            if !rolling && speed>releaseSpeed {let k=min(1,1100/speed);b.vx=vx*k;b.vy=vy*k;b.thrown=true}
            if !b.thrown,!tryStack(b,previous:b.y+b.radius,next:b.y+b.radius,byHand:true),
               let d=support {rest(b,on:d);if rolling && abs(vx)>34 {b.vx=max(-410,min(410,vx*0.63))}}
        } else if let d=initialBank {
            d.add(at:p.x,amount:-3,spread:2);burst(CGPoint(x:p.x,y:d.surface(p.x)),count:23)
        }
        cancel()
    }
    func cancel(){
        if heldSnowman != nil { rememberSnowmenNow() }
        start=nil;held=nil;heldSnowman=nil;initialBank=nil;explicitThrow=false;samples.removeAll()
    }
    @discardableResult func rollDown(_ p:CGPoint,at time:TimeInterval)->Bool {
        if down(p,at:time) {return true}
        guard balls.count+snowmen.count<55,size.width>1 else{return false}
        let b=PackedBall(p.x,p.y,9);balls.append(b);held=b;start=p;last=p;ballOffset = .zero;samples=[(p,time)]
        return true
    }
    @discardableResult func throwDown(_ p:CGPoint,at time:TimeInterval)->Bool {
        guard rollDown(p,at:time) else{return false}
        explicitThrow=true
        if held == nil && heldSnowman == nil {
            guard balls.count+snowmen.count<55 else{cancel();return false}
            let b=PackedBall(p.x,p.y,12);balls.append(b);held=b;ballOffset = .zero
        }
        return true
    }
    @discardableResult func wakeSnowmen()->Bool {battle.start(in:self)}
    func availableForPlay(_ man:BuiltSnowman)->Bool {
        man !== heldSnowman && !man.thrown && snowmen.contains(where:{$0===man})
    }
    func addGuest(at point:CGPoint,radius:CGFloat,style:Int)->BuiltSnowman? {
        guard balls.count+snowmen.count<55,let floor=byID[0] else{return nil}
        var gift=FrostGift();gift.kind = .snowman;gift.size=Double(radius);gift.mid=Double(radius*0.77)
        gift.head=Double(radius*0.56);gift.style=style
        let m=BuiltSnowman(gift:gift,foot:point)
        m.guest=true;m.giftID=nil
        let bank=intercept(x:point.x,previous:point.y-65,next:size.height+1) ?? floor
        settle(m,on:bank);snowmen.append(m);burst(CGPoint(x:m.x,y:m.foot-3),count:11,strength:0.6)
        return m
    }
    func removeGuests() {snowmen.removeAll{$0.guest && $0 !== heldSnowman}}
    func dropVisitorSnowman(at x:CGFloat,scale:CGFloat) {
        guard let m=addGuest(at:CGPoint(x:x,y:size.height),radius:19*scale,style:Int.random(in:0...4)) else{return}
        m.guest=false;rememberSnowmenNow()
    }
    private func advanceFigure(_ m:BuiltSnowman,_ dt:CGFloat)->Bool {
        m.vy=min(850,m.vy+(m.thrown ? 565:400)*dt)
        let n=max(1,Int(ceil(max(abs(m.vx),abs(m.vy))*dt/7))),slice=dt/CGFloat(n)
        for _ in 0..<n {
            let old=m.foot
            m.x+=m.vx*slice;m.foot+=m.vy*slice
            if let d=intercept(x:m.x,previous:old,next:m.foot,embedded:true) ?? (m.foot>=size.height ? byID[0]:nil) {
                m.foot=d.surface(m.x)
                if m.thrown || m.vy>=155 {crumble(m,vx:m.vx,vy:m.vy,contact:d)}
                else {settle(m,on:d)}
                return true
            }
            if m.thrown && ((m.vx<0 && m.x<=m.reach) || (m.vx>0 && m.x>=size.width-m.reach) ||
                             (m.vy<0 && m.hitBounds.minY<=0)) {crumble(m,vx:m.vx,vy:m.vy);return true}
        }
        return false
    }
    private func hitFigure(_ b:PackedBall)->Bool {
        guard let m=snowmen.first(where:{$0 !== heldSnowman && $0.contains(CGPoint(x:b.x,y:b.y),padding:b.radius)}) else{return false}
        crumble(m,vx:b.vx,vy:b.vy);return true
    }
    func crumble(_ m:BuiltSnowman,vx:CGFloat,vy:CGFloat,contact:Drift?=nil) {
        guard let i=snowmen.firstIndex(where:{$0===m}) else{return}
        snowmen.remove(at:i)
        let floor=contact ?? intercept(x:m.x,previous:m.foot-2,next:m.foot+2)
        let base=m.foot-m.base,middle=base-0.78*(m.base+m.middle),head=middle-0.78*(m.middle+m.head)
        let speed=hypot(vx,vy)
        scatter(x:m.x,y:base,r:m.base,vx:vx*0.45,speed:speed,contact:floor)
        scatter(x:m.x,y:middle,r:m.middle,vx:vx*0.70,speed:speed,contact:nil)
        scatter(x:m.x,y:head,r:m.head,vx:vx,speed:speed,contact:nil)
        if !m.guest {rememberSnowmenNow()}
    }
    func scatter(x:CGFloat,y:CGFloat,r:CGFloat,vx:CGFloat,speed:CGFloat,contact:Drift?) {
        let power=min(1.85,max(0.75,0.65+speed/820+r/85)),mass=1.65*r*r
        let count=min(9,max(3,Int(r/3))),carried=contact==nil ? mass:0.35*mass
        contact?.settle(area:mass*0.65,at:x)
        for _ in 0..<count {
            let fx=max(0,min(size.width,x+random.between(-0.55,0.55)*r))
            var fy=y+random.between(-0.55,0.24)*r
            if let bank=contact,bank.edge.contains(fx) {fy=min(fy,bank.surface(fx)-1)}
            let f=MacSnowFragment(x:fx,y:fy,vx:max(-220,min(220,vx*0.30))+random.between(-76,76)*power,
                                  vy:random.between(-140,-48)*power,r:min(7,max(1.8,r*random.between(0.12,0.28))),area:carried/CGFloat(count))
            if fragments.count<320 {fragments.append(f)}
            else if let near=fragments.indices.min(by:{hypot(fragments[$0].x-fx,fragments[$0].y-fy)<hypot(fragments[$1].x-fx,fragments[$1].y-fy)}) {
                fragments[near].area+=f.area
            }
        }
        burst(CGPoint(x:x,y:y),count:Int(min(46,max(12,r+speed/40))),strength:power)
    }
    private func stepFragments(_ dt:CGFloat) {
        guard !fragments.isEmpty else{return}
        var kept=0
        for i in fragments.indices {
            var f=fragments[i];let old=f.y
            f.vy=min(360,f.vy+290*dt);f.vx*=1-0.6*dt;f.x+=(f.vx+wind*0.1)*dt;f.y+=f.vy*dt
            if f.x<0 || f.x>size.width {f.x=max(0,min(size.width,f.x));f.vx *= -0.24}
            if f.vy>=0,let d=intercept(x:f.x,previous:old,next:f.y,embedded:true) ?? (f.y>=size.height ? byID[0]:nil) {
                d.settle(area:f.area,at:f.x);continue
            }
            fragments[kept]=f;kept+=1
        }
        fragments.removeLast(fragments.count-kept)
    }
    func clear() {
        cancel();battle.end(in:self);fragments.removeAll();particles.removeAll();balls.removeAll();snowmen.removeAll();spawnBudget=0;powderCount=0
        snowmanStore?.clear()
        for d in banks {d.clear()}
    }
}
