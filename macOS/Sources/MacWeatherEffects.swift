import AppKit

/// Seasonal particles share the same exposed ledges as the snow simulation.
@MainActor final class MacWeatherEffects {
    struct Particle {
        var x:CGFloat, y:CGFloat, vx:CGFloat, vy:CGFloat, size:CGFloat
        var angle:CGFloat, phase:CGFloat, age:CGFloat=0, life:CGFloat
        var tint:Int, rest:UInt32?, fraction:CGFloat=0, splash=false
    }
    private(set) var particles:[Particle]=[]
    private(set) var mode:MacWeatherMode = .snow
    private var wind:CGFloat=0, intensity:CGFloat=1, budget:CGFloat=0
    private var seedNext=false, lightning=false
    private var previousPointer:CGPoint?
    private var pointerStill:CGFloat=0
    private var size=CGSize.zero
    private var stormClock:CGFloat=17, flash:CGFloat=0, strike:[CGPoint]=[]
    private var randomState:UInt64
    var isActive:Bool { !mode.isSnow && mode != .off && intensity>0 }
    var hasLightning:Bool { flash>0 }

    init(seed:UInt64=UInt64.random(in:1...UInt64.max)) {randomState=seed}
    private func random(_ low:CGFloat,_ high:CGFloat)->CGFloat {
        // SplitMix64 gives each display an independent stream without a system call per streak.
        randomState &+= 0x9E3779B97F4A7C15
        var n=randomState
        n=(n ^ (n>>30)) &* 0xBF58476D1CE4E5B9
        n=(n ^ (n>>27)) &* 0x94D049BB133111EB
        n ^= n>>31
        return low + (high-low)*CGFloat(n>>11)/9_007_199_254_740_992
    }
    func configure(mode:MacWeatherMode,wind:CGFloat,lightning:Bool,intensity:CGFloat) {
        if mode != self.mode {
            clear();self.mode=mode;seedNext=true
        }
        self.wind=wind;self.lightning=lightning;self.intensity=max(0,intensity)
        if !lightning {flash=0;strike.removeAll(keepingCapacity:true)}
        if !isActive && !particles.isEmpty {clear()}
    }
    func clear() {
        particles.removeAll(keepingCapacity:true);previousPointer=nil;pointerStill=0;budget=0
        seedNext=false;flash=0;strike.removeAll(keepingCapacity:true);stormClock=random(14,28)
    }
    private func target(_ area:CGFloat)->Int {
        let divisor,cap:CGFloat
        switch mode {
        case .rain: (divisor,cap)=(14500,330)
        case .sakura: (divisor,cap)=(34500,170)
        case .leaves: (divisor,cap)=(49000,125)
        case .fireflies: (divisor,cap)=(56000,105)
        case .starfall: (divisor,cap)=(280000,14)
        default:return 0
        }
        return min(Int(cap),max(1,Int(max(3,area/divisor)*intensity)))
    }
    private func spawn(scattered:Bool) -> Particle {
        var x=random(0,size.width), y=scattered ? random(0,size.height) : -15
        var vx:CGFloat=0, vy:CGFloat=0, life:CGFloat=35
        switch mode {
        case .rain: vy=random(360,640)
        case .sakura: vy=random(20,44)
        case .leaves: vy=random(34,64)
        case .fireflies: y=random(size.height*0.12,size.height*0.91);vx=random(-9,9);vy=random(-5,5);life=random(5,11)
        case .starfall:
            y=random(-10,size.height*0.30);x=random(-12,size.width*0.95);vx=random(135,250);vy=random(98,180);life=random(1.0,2.3)
        default:break
        }
        return Particle(x:x,y:y,vx:vx,vy:vy,size:random(0.67,1.25),angle:random(-3.14,3.14),
            phase:random(0,6.28),life:life,tint:Int(random(0,3)))
    }
    private func updateStorm(_ dt:CGFloat) {
        guard mode == .rain && lightning else {return}
        flash=max(0,flash-dt);stormClock-=dt
        guard stormClock<=0 else{return}
        stormClock=random(16,34);flash=0.3
        var p=CGPoint(x:random(size.width*0.12,size.width*0.88),y:-4)
        strike=[p]
        let reach=min(250,size.height*0.55)
        for i in 1...6 {p=CGPoint(x:p.x+random(-22,22),y:reach*CGFloat(i)/6);strike.append(p)}
    }
    func step(_ seconds:TimeInterval,world:SnowWorld,pointer:CGPoint?,paused:Bool) {
        size=world.size
        guard isActive,!paused,size.width>2,size.height>2,!world.banks.isEmpty else{return}
        let dt=CGFloat(max(0,min(0.08,seconds)))
        let count=target(size.width*size.height)
        if seedNext {
            for _ in particles.count..<max(particles.count,count/2+1) {particles.append(spawn(scattered:true))}
            seedNext=false
        }
        let replenish=mode == .starfall ? 0.42 : mode == .rain ? 1.2 : 0.23
        budget=min(CGFloat(count),budget+dt*CGFloat(count)*CGFloat(replenish))
        let add=min(Int(budget),max(0,count-particles.count))
        for _ in 0..<add {particles.append(spawn(scattered:false))}
        budget-=CGFloat(add)
        updateStorm(dt)
        let sweep:CGPoint?
        if let a=previousPointer, let b=pointer, hypot(a.x-b.x,a.y-b.y)>2 {
            sweep=CGPoint(x:b.x-a.x,y:b.y-a.y)
        } else {sweep=nil}
        pointerStill = pointer != nil && previousPointer != nil && sweep == nil ? pointerStill+dt : 0
        previousPointer=pointer
        for i in particles.indices.reversed() {
            var p=particles[i]
            p.age+=dt
            if p.age>=p.life || p.x < -65 || p.x > size.width+65 || p.y > size.height+30 {
                particles.swapAt(i,particles.count-1);particles.removeLast();continue
            }
            if p.splash {
                if mode == .starfall {p.vy+=135*dt;p.x+=p.vx*dt;p.y+=p.vy*dt}
                particles[i]=p;continue
            }
            if let id=p.rest {
                if let bank=world.banks.first(where:{$0.edge.id==id}) {
                    p.x=bank.edge.x+bank.edge.width*p.fraction
                    if bank.edge.contains(p.x) {p.y=bank.surface(p.x)-1} else {p.rest=nil}
                } else {p.rest=nil}
            }
            let oldY=p.y
            if mode == .leaves || mode == .sakura {
                if let pointer=pointer, let sweep=sweep, hypot(p.x-pointer.x,p.y-pointer.y)<43 {
                    p.rest=nil;p.vx=max(-135,min(135,sweep.x*2));p.vy = -53
                    p.age=min(p.age,max(0,p.life-2))
                }
                if p.rest != nil {particles[i]=p;continue}
                let leaf=mode == .leaves, rate:CGFloat=leaf ? 40:26
                p.vx += ((wind+sin(p.phase+p.age*1.8)*(leaf ? 26:18))-p.vx)*min(1,dt*2)
                p.vy += (rate*p.size-p.vy)*min(1,dt*1.8)
                p.angle += (leaf ? 1.3:0.8)*dt*(p.tint==1 ? -1:1)
            } else if mode == .rain {
                p.vx=wind*2+12
            } else if mode == .fireflies {
                p.vx=(sin(p.age*0.8+p.phase)*13+wind*0.28)
                p.vy=cos(p.age*1.3+p.phase)*9
                if let cursor=pointer,pointerStill>0.45,hypot(cursor.x-p.x,cursor.y-p.y)<230 {
                    p.vx+=max(-70,min(70,(cursor.x+cos(p.age+p.phase)*25-p.x)*0.68))
                    p.vy+=max(-65,min(65,(cursor.y+sin(p.age+p.phase)*20-p.y)*0.68))
                }
            }
            p.x+=(p.vx+(mode == .starfall ? wind*0.45:0))*dt;p.y+=p.vy*dt
            if mode != .fireflies,p.y>oldY,
               let bank=world.intercept(x:p.x,previous:oldY,next:p.y) {
                p.y=bank.surface(p.x)-1;p.age=0
                if mode == .rain {p.splash=true;p.life=0.17}
                else if mode == .starfall {
                    p.splash=true;p.life=0.34;p.vx=random(-50,50);p.vy=random(-68,-15)
                    if particles.count<64 {
                        for _ in 0..<4 {
                            var shard=p;shard.vx=random(-56,56);shard.vy=random(-76,-18)
                            shard.life=random(0.20,0.43);particles.append(shard)
                        }
                    }
                }
                else {p.rest=bank.edge.id;p.fraction=(p.x-bank.edge.x)/bank.edge.width;p.life=random(2,5);p.angle*=0.22}
            }
            particles[i]=p
        }
    }
    private static func ink(_ r:Int,_ g:Int,_ b:Int,_ a:CGFloat=1)->CGColor {
        CGColor(red:CGFloat(r)/255,green:CGFloat(g)/255,blue:CGFloat(b)/255,alpha:a)
    }
    private static let rain=ink(154,209,241,0.72), rainFoam=ink(207,235,250,0.8)
    private static let petals=[ink(251,193,213),ink(248,160,195),ink(255,215,224)]
    private static let leaves=[ink(220,119,46),ink(201,75,49),ink(234,176,65)]
    private static let vein=ink(106,56,38,0.72), pollen=ink(255,235,197)
    private static let glow=ink(173,218,71,0.19), fly=ink(255,240,135)
    private static let starlight=ink(240,244,255), tail=ink(164,202,255,0.55)
    private static let petal:CGPath = {
        let p=CGMutablePath();p.move(to:CGPoint(x:0,y:4))
        p.addQuadCurve(to:CGPoint(x:-2.8,y:-3.4),control:CGPoint(x:-6,y:0))
        p.addQuadCurve(to:CGPoint(x:0,y:-3),control:CGPoint(x:-1.2,y:-5))
        p.addQuadCurve(to:CGPoint(x:2.8,y:-3.4),control:CGPoint(x:2,y:-5))
        p.addQuadCurve(to:CGPoint(x:0,y:4),control:CGPoint(x:5,y:0));p.closeSubpath();return p
    }()
    private static let leaf:CGPath = {
        let p=CGMutablePath();p.move(to:CGPoint(x:-6,y:2))
        let points:[(CGFloat,CGFloat)]=[(-4,-1),(-4,-3),(-1,-2),(1,-5),(2,-3),(6,-5),(5,-1),(6,0),(3,2),(3,3),(0,3)]
        for xy in points {
            p.addLine(to:CGPoint(x:xy.0,y:xy.1))
        }
        p.closeSubpath();return p
    }()
    func draw(in c:CGContext) {
        guard isActive else{return}
        c.saveGState();defer{c.restoreGState()}
        switch mode {
        case .rain:
            c.setLineCap(.round);c.setLineWidth(1);c.setStrokeColor(Self.rain);c.beginPath()
            for p in particles where !p.splash {
                c.move(to:CGPoint(x:p.x,y:p.y));c.addLine(to:CGPoint(x:p.x-p.vx*0.023,y:p.y-p.vy*0.023))
            }
            c.strokePath();c.setStrokeColor(Self.rainFoam);c.beginPath()
            for p in particles where p.splash {
                let r=1+4*p.age/p.life
                c.move(to:CGPoint(x:p.x-r,y:p.y-2));c.addLine(to:CGPoint(x:p.x-r*0.35,y:p.y))
                c.move(to:CGPoint(x:p.x+r*0.35,y:p.y));c.addLine(to:CGPoint(x:p.x+r,y:p.y-2))
            }
            c.strokePath()
            if flash>0,strike.count>4 {
                c.setAlpha(flash/0.3);c.setStrokeColor(Self.starlight);c.setLineWidth(1.7)
                c.beginPath();c.addLines(between:strike)
                let b=strike[3];c.move(to:b);c.addLine(to:CGPoint(x:b.x+17,y:b.y+9));c.addLine(to:CGPoint(x:b.x+24,y:b.y+27));c.strokePath()
            }
        case .sakura,.leaves:
            let leaf=mode == .leaves
            for p in particles {
                c.saveGState();c.translateBy(x:p.x,y:p.y);c.rotate(by:p.angle)
                c.scaleBy(x:p.size*(p.rest == nil ? 0.6+0.4*abs(cos(p.phase+p.age*1.3)) : 1),y:p.size)
                c.setFillColor((leaf ? Self.leaves : Self.petals)[p.tint]);c.addPath(leaf ? Self.leaf : Self.petal);c.fillPath()
                if leaf {
                    c.setStrokeColor(Self.vein);c.setLineWidth(0.8);c.move(to:CGPoint(x:-7,y:3));c.addLine(to:CGPoint(x:3.7,y:-1.9));c.strokePath()
                } else {c.setFillColor(Self.pollen);c.fillEllipse(in:CGRect(x:-0.7,y:1,width:1.4,height:1.4))}
                c.restoreGState()
            }
        case .fireflies:
            for p in particles {
                let pulse=0.3+0.7*(1+cos(p.age*3+p.phase))*0.5,r=p.size*(2.5+pulse*2.5)
                c.setAlpha(pulse*min(1,(p.life-p.age)*2));c.setFillColor(Self.glow)
                c.fillEllipse(in:CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2))
                c.setFillColor(Self.fly);c.fillEllipse(in:CGRect(x:p.x-1.3,y:p.y-1.3,width:2.6,height:2.6))
            }
        case .starfall:
            for p in particles {
                if p.splash {
                    c.setAlpha(max(0,1-p.age/p.life));c.setFillColor(Self.starlight)
                    c.fillEllipse(in:CGRect(x:p.x-1.1,y:p.y-1.1,width:2.2,height:2.2));continue
                }
                c.setAlpha(min(1,p.age*6,(p.life-p.age)*3));c.setFillColor(Self.tail)
                c.beginPath();c.move(to:CGPoint(x:p.x-p.vx*0.13,y:p.y-p.vy*0.13))
                c.addLine(to:CGPoint(x:p.x-1.2,y:p.y+1.6));c.addLine(to:CGPoint(x:p.x+1,y:p.y-1.2));c.closePath();c.fillPath()
                c.setStrokeColor(Self.starlight);c.setLineWidth(1);let r=2.5*p.size
                c.beginPath();c.move(to:CGPoint(x:p.x-r,y:p.y));c.addLine(to:CGPoint(x:p.x+r,y:p.y))
                c.move(to:CGPoint(x:p.x,y:p.y-r));c.addLine(to:CGPoint(x:p.x,y:p.y+r));c.strokePath()
            }
        default:break
        }
    }
}
