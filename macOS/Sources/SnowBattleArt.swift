import AppKit

enum SnowBattleArt {
    static func powder(in c:CGContext,world:SnowWorld) {
        for f in world.fragments {
            c.setFillColor(red:0.82,green:0.91,blue:0.97,alpha:0.94)
            c.fillEllipse(in:CGRect(x:f.x-f.r,y:f.y-f.r*0.82,width:f.r*1.98,height:f.r*1.7))
            c.setFillColor(red:1,green:1,blue:1,alpha:0.92)
            c.fillEllipse(in:CGRect(x:f.x-f.r*0.77,y:f.y-f.r*0.79,width:f.r*1.45,height:f.r*1.3))
        }
        for shot in world.battle.shots {
            c.setStrokeColor(red:0.83,green:0.94,blue:1,alpha:0.53);c.setLineCap(.round)
            c.setLineWidth(shot.r*0.8);c.beginPath();c.move(to:CGPoint(x:shot.x-shot.vx*0.037,y:shot.y-shot.vy*0.037))
            c.addLine(to:CGPoint(x:shot.x,y:shot.y));c.strokePath()
            c.setFillColor(CGColor(gray:1,alpha:1))
            c.fillEllipse(in:CGRect(x:shot.x-shot.r,y:shot.y-shot.r,width:2*shot.r,height:2*shot.r))
        }
    }
    static func arm(_ p:SnowFighter,in c:CGContext) {
        let m=p.man,r=m.middle,shoulder=CGPoint(x:p.face*r*0.62,y:-m.base-0.78*(m.base+r))
        let angle = -0.32-p.windup*1.63+p.follow*0.65
        let hand=CGPoint(x:shoulder.x+p.face*cos(angle)*r*1.38,y:shoulder.y+sin(angle)*r*1.38)
        c.setLineCap(.round);c.setLineWidth(max(1.6,r*0.14));c.setStrokeColor(red:0.43,green:0.29,blue:0.20,alpha:1)
        c.beginPath();c.move(to:shoulder);c.addLine(to:hand)
        c.addLine(to:CGPoint(x:hand.x+p.face*r*0.18,y:hand.y-r*0.25));c.strokePath()
        if p.windup>0.14 && p.follow<0.1 {
            let ball=max(4,r*0.30);c.setFillColor(CGColor(gray:1,alpha:1))
            c.fillEllipse(in:CGRect(x:hand.x-ball,y:hand.y-ball*1.6,width:2*ball,height:2*ball))
        }
    }
}
