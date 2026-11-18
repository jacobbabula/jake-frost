import AppKit

@MainActor final class MacYeti {
    let wild:Bool,facing:CGFloat
    private(set) var x:CGFloat,y:CGFloat=0,carrying=false,greeted=false
    private var travel:CGFloat=0,age:CGFloat=0,dwell:CGFloat=0,walking=true,finishedVisit=false
    private var tree:UUID?,friend:BuiltSnowman?,strikes=0,selected=false
    private var feet=[CGPoint.zero,CGPoint.zero]
    private var phase:CGFloat=0,bob:CGFloat=0
    init(x:CGFloat,facing:CGFloat,wild:Bool) {self.x=x;self.facing=facing;self.wild=wild}

    func step(_ dt:CGFloat,scale:CGFloat,pace:CGFloat,world:SnowWorld,workshop:MacWorkshop?) {
        guard let floor=world.banks.first else{return}
        age+=dt
        if !wild && !selected {
            selected=true
            if let target=workshop?.nearestTreeForYeti(to:x) {tree=target.id}
            else {friend=world.snowmen.filter{!$0.guest && $0.support==0}.min{abs($0.x-x)<abs($1.x-x)}}
        }
        var destination:CGFloat?
        if !finishedVisit {
            if let id=tree,let prop=workshop?.pieces.first(where:{$0.id==id}) {destination=prop.center.x-facing*24*scale}
            else if let pal=friend,world.availableForPlay(pal) {destination=pal.x-facing*(pal.base+21*scale)}
        }
        walking=true
        let speed=(wild ? 103:31)*pace*(wild ? sqrt(scale):1)
        var distance=speed*dt
        if let mark=destination {
            let gap=(mark-x)*facing
            if gap < -30*scale {finishedVisit=true}
            else if gap<=0.5 {
                walking=false;distance=0;dwell+=dt
                if let id=tree {
                    let hits=min(3,Int((dwell+0.21)/0.74))
                    if hits>strikes {
                        strikes=hits
                        let point=CGPoint(x:x+facing*26*scale,y:floor.surface(x)-17*scale)
                        world.burst(point,count:hits==3 ? 18:7,strength:hits==3 ? 1:0.45)
                    }
                    if strikes==3, dwell>=2.25 {carrying=workshop?.chopTree(id) ?? false;finishedVisit=true}
                } else if dwell>=2.6 {greeted=true;finishedVisit=true}
            } else {distance=min(gap,distance)}
        }
        x+=distance*facing;travel+=distance
        let stride=(wild ? 30:23)*scale,cycle=travel/stride
        phase=cycle*2*CGFloat.pi
        // Each sole stays at a fixed world coordinate during stance. The swing sole
        // follows a smooth horizontal arc and samples the actual snow beneath it.
        for i in 0..<2 {
            let offset=CGFloat(i)*0.5,t=(cycle+offset).truncatingRemainder(dividingBy:1)
            let swing=max(0,(t-0.55)/0.45),ease=swing*swing*(3-2*swing)
            let along=(0.275-t+ease)*stride
            let fx=x+facing*(along+(i==0 ? -3:3)*scale)
            let lift=(walking ? 1:max(0,1-dwell*8))*(wild ? 6.5:4.1)*scale*sin(.pi*swing)
            feet[i]=CGPoint(x:fx,y:floor.surface(fx)-lift)
        }
        y=(floor.surface(feet[0].x)+floor.surface(feet[1].x))*0.5
        bob=walking ? (1-cos(phase*2))*(wild ? 0.85:0.42):0.32*sin(age*2.5)
    }
    func draw(in c:CGContext,scale:CGFloat) {
        c.saveGState();defer{c.restoreGState()}
        c.translateBy(x:x,y:y);c.scaleBy(x:facing*scale,y:scale)
        c.setLineCap(.round);c.setLineJoin(.round)
        for (i,sole) in feet.enumerated() {
            let fx=(sole.x-x)*facing/scale,fy=(sole.y-y)/scale
            let hip=CGFloat(i==0 ? -5:5),knee=(hip+fx)*0.5+1.8
            c.setStrokeColor(red:i==0 ? 0.54:0.75,green:i==0 ? 0.65:0.83,blue:i==0 ? 0.71:0.84,alpha:1)
            c.setLineWidth(5.8);c.beginPath();c.move(to:CGPoint(x:hip,y:-12-bob))
            c.addQuadCurve(to:CGPoint(x:fx,y:fy-2.4),control:CGPoint(x:knee,y:fy-6));c.strokePath()
            c.setFillColor(red:0.47,green:0.57,blue:0.62,alpha:1)
            c.fillEllipse(in:CGRect(x:fx-3.5,y:fy-4.0,width:9.1,height:4.0))
            c.setFillColor(red:0.83,green:0.89,blue:0.87,alpha:1)
            c.fillEllipse(in:CGRect(x:fx-3.1,y:fy-4.4,width:8.0,height:3.1))
        }
        let gait=walking ? sin(phase):0
        var arm:CGFloat=gait*(wild ? 0.84:0.43)
        if !walking,tree != nil {
            let t=dwell.truncatingRemainder(dividingBy:0.74)/0.74
            arm=(t<0.54 ? -25-78*t/0.54 : t<0.72 ? -103+127*(t-0.54)/0.18:24-49*(t-0.72)/0.28)*CGFloat.pi/180
        } else if carrying {arm = -0.84+gait*0.04}
        else if !walking {arm = -1.55+sin(dwell*5)*0.24}
        YetiArt.paint(in:c,gait:gait,tilt:walking ? (wild ? 0.11:0.02)+gait*0.012:0,
                      lift:bob,armAngle:arm,tool:tree != nil && !finishedVisit,carrying:carrying)
    }
}
