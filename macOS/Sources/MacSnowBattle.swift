import Foundation

struct MacSnowFragment {
    var x,y,vx,vy,r,area:CGFloat
}

final class SnowFighter {
    let man:BuiltSnowman
    var team=0,health=2
    var next:CGFloat=0,last:CGFloat = -10,recoil:CGFloat=0,face:CGFloat=1,windup:CGFloat=0,follow:CGFloat=0
    var duck:CGFloat=0,wave:CGFloat=0
    init(_ man:BuiltSnowman) {self.man=man}
}

struct BattlePellet {
    var x,y,vx,vy,r,life:CGFloat
    let shooter:BuiltSnowman
    var friendly:Bool
}

final class MacSnowBattle {
    private(set) var players=[SnowFighter](),shots=[BattlePellet]()
    private(set) var age:CGFloat=0,throwsMade=0,hits=0,knockouts=0
    private var finish:CGFloat=24,idle:CGFloat=16
    var active:Bool {!players.isEmpty || !shots.isEmpty}
    func player(for man:BuiltSnowman)->SnowFighter? {players.first{$0.man===man && $0.health>0}}

    func end(in world:SnowWorld) {
        world.removeGuests();players.removeAll();shots.removeAll();idle=16
    }
    func start(in world:SnowWorld)->Bool {
        end(in:world)
        guard let anchor=world.snowmen.last(where:world.availableForPlay) else{return false}
        let local=world.snowmen.filter{world.availableForPlay($0) && abs($0.x-anchor.x)<850 && abs($0.foot-anchor.foot)<240}
            .sorted{abs($0.x-anchor.x)<abs($1.x-anchor.x)}
        var cast=Array(local.prefix(6))
        let radius=max(14,min(36,anchor.base*0.42+15)),center=max(min(world.size.width/2,200),min(anchor.x,max(world.size.width/2,world.size.width-200)))
        let span=min(world.size.width*0.43,285)
        while cast.count<4 {
            var bestSpace:CGFloat = -1,bestX=center
            for i in 0...14 {
                let x=max(radius+4,min(world.size.width-radius-4,center-span+2*span*CGFloat(i)/14))
                let space=world.snowmen.reduce(CGFloat.greatestFiniteMagnitude){min($0,abs($1.x-x)-$1.base)}
                if space>bestSpace {bestX=x;bestSpace=space}
            }
            guard bestSpace>radius*0.9,let m=world.addGuest(at:CGPoint(x:bestX,y:anchor.foot),radius:radius,style:cast.count%5) else{break}
            cast.append(m)
        }
        guard cast.count>=2 else{end(in:world);return false}
        players=cast.sorted{$0.x<$1.x}.map(SnowFighter.init)
        age=0;finish=24;throwsMade=0;hits=0;knockouts=0
        let split=(players.count+1)/2
        for (i,p) in players.enumerated() {
            p.team=i<split ? 0:1;p.face=p.team==0 ? 1 : -1
            p.next=1.30+CGFloat(i%split)*0.85+CGFloat(p.team)*0.53
        }
        return true
    }
    private func launch(from m:BuiltSnowman,to target:BuiltSnowman,wild:Bool,friendly:Bool,world:SnowWorld) {
        let face:CGFloat=target.x>=m.x ? 1:-1,r=max(4.2,min(9,m.middle*0.30))
        let x=m.x+face*(m.middle*1.3+r),y=m.foot-m.hitBounds.height*0.58
        let ty=target.foot-target.hitBounds.height*(wild ? 1.20:0.56)
        let duration=min(1.45,max(0.62,0.62+abs(target.x-x)*0.0013))/world.battlePace
        shots.append(BattlePellet(x:x,y:y,vx:(target.x-x)/duration,vy:(ty-y)/duration-130*duration,
                                  r:r,life:duration+1.2,shooter:m,friendly:friendly))
        world.burst(CGPoint(x:x,y:y),count:5,strength:0.35)
    }
    func step(_ dt:CGFloat,world:SnowWorld) {
        if !players.isEmpty {
            age+=dt*world.battlePace
            if age>=finish {end(in:world);return}
            for p in players where !world.availableForPlay(p.man) {p.health=0}
            if !players.contains(where:{$0.team==0 && $0.health>0}) || !players.contains(where:{$0.team==1 && $0.health>0}) {
                finish=min(finish,age+1)
            }
            for (i,p) in players.enumerated() where p.health>0 {
                p.recoil=max(0,p.recoil-dt*2.5)
                let rivals=players.filter{$0.team != p.team && $0.health>0}
                p.duck=0.33*max(0,sin(age*3.7+CGFloat(i)*1.2))
                p.wave=rivals.isEmpty ? abs(sin(7*age)):0
                guard !rivals.isEmpty else{p.windup=0;p.follow=0;continue}
                let rival=rivals[(i+throwsMade)%rivals.count];p.face=rival.man.x>=p.man.x ? 1:-1
                p.windup=max(0,min(1,1-(p.next-age)/0.72));p.follow=max(0,1-(age-p.last)/0.48)
                guard age>=p.next,shots.count<20 else{continue}
                launch(from:p.man,to:rival.man,wild:throwsMade%5==4,friendly:false,world:world)
                throwsMade+=1;p.last=age;p.next=age+2.45+CGFloat(i%3)*0.24
            }
        } else if world.snowEnabled && world.snowmen.count>=2 {
            idle-=dt
            if idle<=0 {
                idle=16
                let resting=world.snowmen.filter{$0.support != nil && world.availableForPlay($0)}
                if resting.count>=2 {launch(from:resting[0],to:resting[1],wild:false,friendly:true,world:world)}
            }
        }
        for i in shots.indices.reversed() {
            var s=shots[i],done=false
            let n=max(1,Int(ceil(hypot(s.vx,s.vy)*dt/6))),slice=dt/CGFloat(n)
            for _ in 0..<n {
                let old=s.y;s.x+=s.vx*slice;s.y+=s.vy*slice+130*slice*slice;s.vy+=260*slice;s.life-=slice
                if let target=world.snowmen.first(where:{$0 !== s.shooter && world.availableForPlay($0) &&
                    $0.contains(CGPoint(x:s.x,y:s.y),padding:s.r)}) {
                    world.scatter(x:s.x,y:s.y,r:s.r,vx:s.vx,speed:abs(s.vy)+110,contact:nil)
                    if !s.friendly,let p=player(for:target) {
                        hits+=1;p.health-=1;p.recoil=1
                        if p.health==0 {knockouts+=1;world.crumble(target,vx:s.vx,vy:abs(s.vy)+140)}
                    }
                    done=true;break
                }
                if let d=world.intercept(x:s.x,previous:old+s.r,next:s.y+s.r) {
                    world.scatter(x:s.x,y:d.surface(s.x)-s.r,r:s.r,vx:s.vx,speed:abs(s.vy),contact:d)
                    done=true;break
                }
                if s.life<=0 || s.x < -30 || s.x>world.size.width+30 || s.y>world.size.height+30 {done=true;break}
            }
            if done {shots.remove(at:i)} else {shots[i]=s}
        }
    }
}
