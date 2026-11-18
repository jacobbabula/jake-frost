import Foundation

final class Drift {
    var edge: SnowEdge
    var depth: [CGFloat]
    var spacing: CGFloat { edge.width / CGFloat(depth.count - 1) }

    init(_ edge: SnowEdge) {
        self.edge = edge
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
    @discardableResult func add(at x: CGFloat, amount: CGFloat, spread: Int = 2) -> CGFloat {
        let mid = min(depth.count-1,max(0,Int(((x-edge.x)/spacing).rounded())))
        var changed: CGFloat = 0
        for i in max(0,mid-spread)...min(depth.count-1,mid+spread) {
            let weight = CGFloat(spread+1-abs(i-mid))/CGFloat(spread+1)
            let cap: CGFloat = edge.id == 0 ? 55 : min(27, 1.5+CGFloat(min(i,depth.count-1-i))*spacing*0.55)
            let next = min(cap,max(0,depth[i] + amount*weight))
            changed += next - depth[i]; depth[i] = next
        }
        return changed
    }
    func move(to next: SnowEdge) {
        if abs(next.width-edge.width) > 0.5 {
            let count = max(3, Int(ceil(next.width/10))+1)
            depth = (0..<count).map { height(edge.x + edge.width*CGFloat($0)/CGFloat(count-1)) }
        }
        edge = next
    }
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
    var support: UInt32?
    var supportFraction: CGFloat = 0
    init(_ x: CGFloat,_ y: CGFloat,_ radius: CGFloat) { self.x=x; self.y=y; self.radius=radius }
}

final class SnowWorld {
    private(set) var size = CGSize.zero
    private(set) var banks = [Drift]()
    private var byID = [UInt32:Drift]()
    private(set) var particles = [SnowParticle]()
    private(set) var balls = [PackedBall]()
    private var spawnBudget: CGFloat = 0
    var amount: CGFloat = 1
    var paused = false
    private var start: CGPoint?, last = CGPoint.zero
    private var initialBank: Drift?, held: PackedBall?, ballOffset = CGPoint.zero
    private var samples = [(CGPoint,TimeInterval)]()

    func setDesktop(size newSize: CGSize, edges: [SnowEdge]) {
        guard newSize.width > 1 && newSize.height > 1 else { return }
        let first = size == .zero
        size = newSize
        let floor = SnowEdge(id: 0, x: 0, y: size.height, width: size.width, visible: [0...size.width])
        // Keep recently covered window banks while the window remains reported on this screen
        // only through its visible segments. Removing a window also frees its snow.
        var next = [UInt32:Drift]()
        for edge in [floor] + edges {
            if let bank = byID[edge.id] { bank.move(to: edge); next[edge.id]=bank }
            else { next[edge.id]=Drift(edge) }
        }
        byID=next; banks=([floor]+edges).compactMap { next[$0.id] }
        if first {
            for _ in 0..<min(280,Int(size.width*0.08)) { spawn(randomHeight:true) }
        }
    }

    private func spawn(randomHeight: Bool) {
        let r=CGFloat.random(in:0.8...2.5)
        particles.append(SnowParticle(x:.random(in:0...size.width),y:randomHeight ? .random(in:0...size.height) : -3,
                         vx:.random(in:-6...8),vy:18+12*r,radius:r,phase:.random(in:0...6.28)))
    }

    func burst(_ point: CGPoint, count: Int, strength: CGFloat = 1) {
        guard particles.count < 1800 else { return }
        for _ in 0..<min(count,1800-particles.count) {
            particles.append(SnowParticle(x:point.x,y:point.y,vx:.random(in:-70...70)*strength,
                vy:.random(in:-112 ... -23)*strength,radius:.random(in:1...2.7),
                phase:0,powder:true,life:.random(in:0.45...0.85)))
        }
    }

    private func intercept(x:CGFloat, previous:CGFloat, next:CGFloat) -> Drift? {
        var bank: Drift?, earliest = CGFloat.greatestFiniteMagnitude
        for d in banks where d.edge.contains(x) {
            let y=d.surface(x)
            if previous <= y+1.2 && next >= y && y < earliest { earliest=y;bank=d }
        }
        return bank
    }

    func step(_ seconds: TimeInterval) {
        guard size.width>1 else { return }
        let dt=CGFloat(min(0.08,max(0,seconds)))
        if !paused {
            spawnBudget += dt*amount*size.width*0.023
            while spawnBudget>=1 { if particles.count<1600 {spawn(randomHeight:false)};spawnBudget-=1 }
        }
        for i in particles.indices.reversed() {
            var p=particles[i]; if paused && !p.powder {continue}
            let previous=p.y
            if p.powder {p.vy+=170*dt;p.life-=dt} else {p.phase+=dt;p.x+=sin(p.phase)*11*dt}
            p.x+=p.vx*dt;p.y+=p.vy*dt
            if !p.powder, let d=intercept(x:p.x,previous:previous,next:p.y) {
                d.add(at:p.x,amount:0.28+p.radius*0.25);particles.remove(at:i)
            } else if p.y>size.height+6 || p.life<=0 || p.x < -15 || p.x>size.width+15 {particles.remove(at:i)}
            else {particles[i]=p}
        }
        for i in balls.indices.reversed() {
            let b=balls[i]; if b===held {continue}
            if let id=b.support,let d=byID[id] {
                let x=d.edge.x+b.supportFraction*d.edge.width
                if d.edge.contains(x) {b.x=x;b.y=d.surface(x)-b.radius;continue}
            }
            b.support=nil
            let old=b.y+b.radius;b.vy+=340*dt;b.x+=b.vx*dt;b.y+=b.vy*dt
            if let d=intercept(x:b.x,previous:old,next:b.y+b.radius) {
                if b.thrown { splat(b,i,d) }
                else { rest(b,on:d) }
            } else if b.y+b.radius>=size.height || b.x < -b.radius || b.x > size.width+b.radius {
                if b.thrown {splat(b,i,nil)} else if let floor=byID[0] {
                    b.x=min(max(b.radius,b.x),size.width-b.radius);rest(b,on:floor)
                }
            }
        }
    }

    private func rest(_ b: PackedBall,on bank:Drift) {
        b.y=bank.surface(b.x)-b.radius;b.vx=0;b.vy=0;b.support=bank.edge.id
        b.supportFraction=(b.x-bank.edge.x)/bank.edge.width
    }
    private func splat(_ b: PackedBall,_ index:Int,_ bank:Drift?) {
        let y=bank?.surface(b.x) ?? min(size.height-2,b.y)
        burst(CGPoint(x:b.x,y:y),count:Int(b.radius*2.5),strength:1.2)
        bank?.add(at:b.x,amount:b.radius*0.35,spread:3);balls.remove(at:index)
    }
    private func snowyBank(_ p:CGPoint)->Drift? {
        banks.first { d in
            d.edge.contains(p.x) && d.height(p.x)>0.7 && p.y>=d.surface(p.x)-2 && p.y<=d.edge.y+1
        }
    }
    private func ball(_ p:CGPoint)->PackedBall? {
        balls.reversed().first { hypot(p.x-$0.x,p.y-$0.y)<=$0.radius+1 }
    }
    func hit(_ p:CGPoint)->Bool {ball(p) != nil || snowyBank(p) != nil}
    @discardableResult func down(_ p:CGPoint,at t:TimeInterval)->Bool {
        cancel();let b=ball(p), d=snowyBank(p)
        guard b != nil || d != nil else {return false}
        start=p;last=p;initialBank=d;held=b;samples=[(p,t)]
        if let b=b {ballOffset=CGPoint(x:b.x-p.x,y:b.y-p.y);b.support=nil;b.vx=0;b.vy=0;b.thrown=false}
        return true
    }
    func drag(_ p:CGPoint,at t:TimeInterval) {
        guard let origin=start else{return}
        if held==nil {
            guard hypot(p.x-origin.x,p.y-origin.y)>=4,balls.count<55 else{return}
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
        if let b=held {
            if let first=samples.first,t-first.1>=0.008 {
                let elapsed=CGFloat(t-first.1),vx=(p.x-first.0.x)/elapsed,vy=(p.y-first.0.y)/elapsed
                let speed=hypot(vx,vy)
                if speed>175 {let k=min(1,1100/speed);b.vx=vx*k;b.vy=vy*k;b.thrown=true}
            }
            if !b.thrown,let d=banks.first(where:{$0.edge.contains(b.x) && abs($0.surface(b.x)-(b.y+b.radius))<7}) {rest(b,on:d)}
        } else if let d=initialBank {
            d.add(at:p.x,amount:-3,spread:2);burst(CGPoint(x:p.x,y:d.surface(p.x)),count:23)
        }
        cancel()
    }
    func cancel(){ start=nil;held=nil;initialBank=nil;samples.removeAll() }
    func clear() {
        cancel();particles.removeAll();balls.removeAll();spawnBudget=0
        for d in banks {d.depth=Array(repeating:0,count:d.depth.count)}
    }
}
