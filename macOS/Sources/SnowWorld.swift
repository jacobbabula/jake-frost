import Foundation

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
}

struct SnowParticle {
    var x, y, vx, vy, radius, phase: CGFloat
    var powder = false
    var life: CGFloat = 1
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
    var support: UInt32?, supportFraction: CGFloat
    var vy: CGFloat = 0

    init(bottom: PackedBall, middleBall: PackedBall, headBall: PackedBall) {
        x = bottom.x; foot = bottom.y + bottom.radius
        support = bottom.support; supportFraction = bottom.supportFraction
        base = min(42, max(14, max(bottom.radius, max(middleBall.radius, headBall.radius))))
        middle = min(base * 0.8, max(base * 0.66, middleBall.radius))
        head = min(base * 0.59, max(base * 0.46, headBall.radius))
        style = Int.random(in:0..<3); facing = Bool.random() ? 1 : -1
    }

    func contains(_ point: CGPoint) -> Bool {
        let dx = abs(point.x-x), dy = point.y-foot
        guard dx <= max(base, head*1.08)+1 else {return false}
        let torso = -base - 0.78*(base+middle), face = torso - 0.78*(middle+head)
        return hypot(dx,dy+base) <= base+1 || hypot(dx,dy-torso) <= middle+1 ||
            hypot(dx,dy-face) <= head+1 || (dx <= head*0.72 && dy >= face-head*1.88 && dy <= face-head*0.77) ||
            (dx <= head*1.08 && dy >= face-head && dy <= face-head*0.77)
    }
}

final class SnowWorld {
    private(set) var size = CGSize.zero
    private(set) var banks = [Drift]()
    private var byID = [UInt32:Drift]()
    private var collisionRows = [[Drift]]()
    private static let rowHeight: CGFloat = 64
    private var powderCount = 0
    var hasMotion: Bool {
        (!paused && snowEnabled && (amount > 0 || !particles.isEmpty)) || powderCount > 0 ||
            balls.contains { $0.support == nil && $0.below == nil } || snowmen.contains { $0.support == nil }
    }
    private(set) var particles = [SnowParticle]()
    private(set) var balls = [PackedBall]()
    private(set) var snowmen = [BuiltSnowman]()
    private weak var heldSnowman: BuiltSnowman?
    private var spawnBudget: CGFloat = 0
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
        let limit = min(140,max(24,value))
        guard limit != depthLimit else { return }
        depthLimit = limit
        for bank in banks { bank.setDepthLimit(limit) }
        rebuildRows()
    }
    var paused = false
    private var start: CGPoint?, last = CGPoint.zero
    private var initialBank: Drift?, held: PackedBall?, ballOffset = CGPoint.zero
    private var samples = [(CGPoint,TimeInterval)]()

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
        let r=CGFloat.random(in:0.8...2.5)
        particles.append(SnowParticle(x:.random(in:0...size.width),y:randomHeight ? .random(in:0...size.height) : -3,
                         vx:.random(in:-6...8),vy:18+12*r,radius:r,phase:.random(in:0...6.28)))
    }

    func burst(_ point: CGPoint, count: Int, strength: CGFloat = 1) {
        guard particles.count < 1800 else { return }
        let added = max(0,min(count,1800-particles.count))
        powderCount += added
        for _ in 0..<added {
            particles.append(SnowParticle(x:point.x,y:point.y,vx:.random(in:-70...70)*strength,
                vy:.random(in:-112 ... -23)*strength,radius:.random(in:1...2.7),
                phase:0,powder:true,life:.random(in:0.45...0.85)))
        }
    }

    private func row(_ y: CGFloat) -> Int {
        max(0, min(collisionRows.count - 1, Int(y / Self.rowHeight)))
    }
    func intercept(x:CGFloat, previous:CGFloat, next:CGFloat) -> Drift? {
        var bank: Drift?, earliest = CGFloat.greatestFiniteMagnitude
        let first = row(previous), last = row(next)
        // A normal flake crosses at most one row boundary. Keep the original bank
        // order for long sweeps, including a fast snowball passing several ledges.
        for d in (first == last ? collisionRows[first] : banks) {
            guard previous <= d.edge.y + 1.2, next >= d.edge.y - d.maximumDepth,
                  x >= d.edge.x, x <= d.edge.x + d.edge.width, d.edge.contains(x) else { continue }
            let y=d.surface(x)
            if previous <= y+1.2 && next >= y && y < earliest { earliest=y;bank=d }
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
        for b in balls where b !== held && b.below == nil {
            if let id=b.support,let d=byID[id] {
                let x=d.edge.x+b.supportFraction*d.edge.width
                if d.edge.contains(x) {
                    b.x=x;b.y=d.surface(x)-b.radius;positionUpperBall(on:b);continue
                }
            }
            b.support=nil
            let old=b.y+b.radius;b.vy+=340*dt;b.x+=b.vx*dt;b.y+=b.vy*dt
            let bank=intercept(x:b.x,previous:old,next:b.y+b.radius)
            let nextFoot=min(b.y+b.radius,bank?.surface(b.x) ?? size.height)
            if !b.thrown && b.vy>=0 && tryStack(b,previous:old,next:nextFoot,byHand:false) {continue}
            if let d=bank {
                if b.thrown { splat(b,d) } else { rest(b,on:d) }
            } else if b.y+b.radius>=size.height || b.x < -b.radius || b.x > size.width+b.radius {
                if b.thrown {splat(b,nil)} else if let floor=byID[0] {
                    b.x=min(max(b.radius,b.x),size.width-b.radius);rest(b,on:floor)
                }
            }
            positionUpperBall(on:b)
        }
        for figure in snowmen where figure !== heldSnowman {
            if let id=figure.support,let bank=byID[id] {
                let x=bank.edge.x+figure.supportFraction*bank.edge.width
                if bank.edge.contains(x) {figure.x=x;figure.foot=bank.surface(x);continue}
            }
            figure.support=nil
            let old=figure.foot
            figure.vy += 340*dt;figure.foot += figure.vy*dt
            if let bank = intercept(x:figure.x,previous:old,next:figure.foot) ?? (figure.foot >= size.height ? byID[0] : nil) {
                settle(figure,on:bank)
            }
        }
    }
    private func stepParticles(_ dt:CGFloat) {
        for i in particles.indices.reversed() {
            var p=particles[i]; if paused && !p.powder {continue}
            let previous=p.y
            if p.powder {p.vy+=170*dt;p.life-=dt} else {p.phase+=dt;p.x+=(sin(p.phase)*11+wind)*dt}
            p.x+=p.vx*dt;p.y+=p.vy*dt
            if !p.powder, let d=intercept(x:p.x,previous:previous,next:p.y) {
                d.add(at:p.x,amount:0.28+p.radius*0.25);removeParticle(at:i)
            } else if p.y>size.height+6 || p.life<=0 || p.x < -15 || p.x>size.width+15 {removeParticle(at:i)}
            else {particles[i]=p}
        }
    }
    private func removeParticle(at index:Int) {
        if particles[index].powder { powderCount -= 1 }
        // Reverse traversal means the particle at the back has already advanced.
        // The renderer groups particles by color, so their array order is immaterial.
        particles.swapAt(index, particles.count-1)
        particles.removeLast()
    }

    private func rest(_ b: PackedBall,on bank:Drift) {
        b.y=bank.surface(b.x)-b.radius;b.vx=0;b.vy=0;b.support=bank.edge.id
        b.supportFraction=(b.x-bank.edge.x)/bank.edge.width
    }
    private func settle(_ figure: BuiltSnowman,on bank:Drift) {
        figure.support=bank.edge.id;figure.supportFraction=(figure.x-bank.edge.x)/bank.edge.width
        figure.foot=bank.surface(figure.x);figure.vy=0
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
        } else {
            middle.above=b;b.below=middle;b.vx=0;b.vy=0;b.support=nil
            positionUpperBall(on:middle)
        }
        return true
    }
    private func splat(_ b: PackedBall,_ bank:Drift?) {
        let y=bank?.surface(b.x) ?? min(size.height-2,b.y)
        burst(CGPoint(x:b.x,y:y),count:Int(b.radius*2.5),strength:1.2)
        bank?.add(at:b.x,amount:b.radius*0.35,spread:3);balls.removeAll { $0 === b }
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
            figure.support=nil;figure.vy=0;return true
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
            return
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
                if let d=banks.first(where:{ $0.edge.contains(x) && abs($0.surface(x)-y)<b.radius+11 }) {
                    let taken = -d.add(at:x,amount:-min(2,abs(dx)/CGFloat(n)*0.12),spread:1)
                    b.radius=min(42,sqrt(b.radius*b.radius+taken*6))
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
        if let figure=heldSnowman {
            if let bank=banks.filter({$0.edge.contains(figure.x) && abs($0.surface(figure.x)-figure.foot)<9})
                .min(by:{abs($0.surface(figure.x)-figure.foot)<abs($1.surface(figure.x)-figure.foot)}) {
                settle(figure,on:bank)
            }
        } else if let b=held {
            if let first=samples.first,t-first.1>=0.008 {
                let elapsed=CGFloat(t-first.1),vx=(p.x-first.0.x)/elapsed,vy=(p.y-first.0.y)/elapsed
                let speed=hypot(vx,vy)
                if speed>175 {let k=min(1,1100/speed);b.vx=vx*k;b.vy=vy*k;b.thrown=true}
            }
            if !b.thrown,!tryStack(b,previous:b.y+b.radius,next:b.y+b.radius,byHand:true),
               let d=banks.first(where:{$0.edge.contains(b.x) && abs($0.surface(b.x)-(b.y+b.radius))<7}) {rest(b,on:d)}
        } else if let d=initialBank {
            d.add(at:p.x,amount:-3,spread:2);burst(CGPoint(x:p.x,y:d.surface(p.x)),count:23)
        }
        cancel()
    }
    func cancel(){ start=nil;held=nil;heldSnowman=nil;initialBank=nil;samples.removeAll() }
    func clear() {
        cancel();particles.removeAll();balls.removeAll();snowmen.removeAll();spawnBudget=0;powderCount=0
        for d in banks {d.clear()}
    }
}
