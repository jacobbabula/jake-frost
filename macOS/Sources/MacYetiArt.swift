import CoreGraphics

// The desktop visitors share the Windows character's authored curves and palette.
// Each component has its own pivot so grounded legs, scarf, horns and tool move together.
enum YetiArt {
    private enum PointCommand { case m(CGFloat,CGFloat), l(CGFloat,CGFloat), q(CGFloat,CGFloat,CGFloat,CGFloat), z }
    private struct Ink {
        let color:CGColor, path:CGPath
        let width:CGFloat
        init(_ rgb:Int,_ path:CGPath,_ width:CGFloat=0) {
            color=CGColor(red:CGFloat(rgb>>16 & 255)/255,green:CGFloat(rgb>>8 & 255)/255,blue:CGFloat(rgb & 255)/255,alpha:1)
            self.path=path;self.width=width
        }
    }
    private static func outline(_ rgb:Int,_ steps:[PointCommand])->Ink {
        let p=CGMutablePath()
        for step in steps {
            switch step {
            case let .m(x,y): p.move(to:CGPoint(x:x,y:y))
            case let .l(x,y): p.addLine(to:CGPoint(x:x,y:y))
            case let .q(cx,cy,x,y): p.addQuadCurve(to:CGPoint(x:x,y:y),control:CGPoint(x:cx,y:cy))
            case .z: p.closeSubpath()
            }
        }
        return Ink(rgb,p)
    }
    private static func oval(_ rgb:Int,_ x:CGFloat,_ y:CGFloat,_ rx:CGFloat,_ ry:CGFloat)->Ink {
        Ink(rgb,CGPath(ellipseIn:CGRect(x:x-rx,y:y-ry,width:2*rx,height:2*ry),transform:nil))
    }
    private static func line(_ rgb:Int,_ width:CGFloat,_ x:CGFloat,_ y:CGFloat,_ xx:CGFloat,_ yy:CGFloat)->Ink {
        let p=CGMutablePath();p.move(to:CGPoint(x:x,y:y));p.addLine(to:CGPoint(x:xx,y:yy));return Ink(rgb,p,width)
    }
    private static func box(_ rgb:Int,_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat,_ r:CGFloat)->Ink {
        Ink(rgb,CGPath(roundedRect:CGRect(x:x,y:y,width:w,height:h),cornerWidth:r,cornerHeight:r,transform:nil))
    }
    private static func draw(_ layer:[Ink],in c:CGContext) {
        for ink in layer {
            c.addPath(ink.path)
            if ink.width>0 {c.setStrokeColor(ink.color);c.setLineWidth(ink.width);c.strokePath()}
            else {c.setFillColor(ink.color);c.fillPath()}
        }
    }
    private static let back:[Ink] = [
        outline(0x798FA2,[.m(-14,-29),.q(-20,-26,-20,-17),.q(-22,-12,-17,-12),.q(-14,-10,-11,-18),.z])
    ]
    private static let body:[Ink] = [
        outline(0x95AEBB,[.m(-12,-28),.q(-19,-22,-18,-12),.l(-19,-9),.l(-16,-10),.q(-13,-3,-8,-4),.l(-7,-2),.l(-4,-4),.q(1,-2,5,-4),.l(8,-3),.l(9,-5),.q(17,-5,17,-16),.q(17,-28,9,-30),.z]),
        outline(0xEDF0E7,[.m(-11,-28),.q(-17,-20,-15,-13),.l(-17,-11),.l(-14,-12),.q(-14,-6,-9,-7),.l(-8,-5),.l(-5,-7),.q(1,-4,5,-6),.l(7,-5),.l(9,-7),.q(16,-8,15,-18),.q(15,-27,8,-29),.z]),
        outline(0xBED4D7,[.m(-10,-15),.q(-8,-11,-6,-12),.l(-4,-10),.l(-3,-12),.l(1,-10),.l(2,-12),.l(4,-11),.l(7,-14),.q(2,-7,-4,-9),.q(-10,-9,-10,-15),.z]),
        outline(0xA7504A,[.m(-9,-25),.q(-12,-20,-14,-17),.l(-11,-17),.l(-11,-15),.q(-6,-17,-4,-23),.z]),
        line(0xE89472,1.8,-12,-18,-9,-17.5),
        oval(0xBD6056,1,-26.2,13.1,3.8),
        oval(0xE58B71,2,-27,10,1.6)
    ]
    private static let head:[Ink] = [
        outline(0x756B70,[.m(-12,-38),.q(-20,-40,-18,-48),.q(-17,-52,-14,-53),.q(-16,-46,-9,-45),.z,.m(10,-41),.q(15,-47,12,-52),.q(20,-49,18,-43),.q(17,-38,12,-37),.z]),
        outline(0xD9AE87,[.m(-13,-41),.q(-18,-43,-16,-49),.q(-16,-45,-10,-44),.z,.m(12,-42),.q(16,-46,14,-49),.q(18,-46,16,-42),.z]),
        outline(0x91AFBC,[.m(-16,-40),.q(-15,-49,-6,-50),.l(-2,-55),.l(1,-52),.l(6,-54),.l(7,-51),.q(16,-49,18,-39),.l(20,-36),.l(17,-36),.l(19,-32),.l(16,-32),.q(13,-25,5,-25),.l(3,-23),.l(0,-25),.l(-3,-23),.l(-5,-25),.q(-15,-25,-17,-33),.l(-19,-32),.l(-18,-37),.l(-20,-37),.z]),
        outline(0xF6F3E6,[.m(-15,-40),.q(-14,-48,-5,-48),.l(-2,-52),.l(0,-49),.l(5,-52),.l(5,-49),.q(15,-48,16,-39),.l(18,-37),.l(15,-37),.l(17,-34),.l(14,-34),.q(13,-28,5,-27),.l(2,-25),.l(0,-27),.l(-3,-25),.l(-5,-27),.q(-13,-27,-15,-34),.l(-17,-34),.l(-16,-38),.l(-18,-38),.z]),
        oval(0xA7C6CC,2,-36.7,11.8,7.6),
        oval(0xBBDADD,3,-36,10,5.7),
        oval(0xDDACA5,-6,-34.9,2.5,1.35),
        oval(0xDDACA5,11.4,-35.5,2.1,1.2),
        oval(0x293944,-1.3,-38,1.9,2.4),
        oval(0x293944,8.1,-38.6,1.8,2.25),
        oval(0xFFFFFF,-1.8,-38.9,0.68,0.82),
        oval(0xFFFFFF,7.6,-39.35,0.65,0.75),
        oval(0x526674,4,-35.6,2.1,1.25),
        outline(0x485762,[.m(0.3,-33.6),.q(3,-31.9,7,-33.7),.q(6.4,-30,3.8,-30.3),.q(1.5,-30.2,0.3,-33.6),.z]),
        outline(0xFFFBE8,[.m(1,-33.3),.l(3.2,-32.8),.l(2.5,-31.7),.z])
    ]
    private static let log:[Ink] = [
        box(0x946543,-16,-27,36,10,4),
        line(0xC99A69,1.3,-12,-24,11,-24),
        oval(0xE3B579,18,-22,4.8,5),
        oval(0xAD7B51,18,-22,2.8,3.4),
        oval(0xE3B579,18,-22,1.7,2.1)
    ]
    private static let arm:[Ink] = [
        outline(0x9AB6C0,[.m(8,-24),.q(12,-28,15,-22),.l(19,-16),.q(21,-11,17,-10),.q(13,-8,10,-15),.z]),
        outline(0xE1EAE4,[.m(9,-24),.q(12,-26,14,-21),.l(17,-17),.l(16,-15),.l(18,-15),.q(17,-12,14,-13),.q(11,-15,9,-20),.z])
    ]
    private static let axe:[Ink] = [
        line(0x7C5948,2.9,14,-14,25,-19),
        line(0xD4AF82,0.95,16,-15,24,-18.6),
        outline(0x647D8A,[.m(21,-21),.l(25,-23),.q(26,-21,29,-21),.l(29,-16),.q(26,-13,24,-13),.l(23,-17),.l(20,-18),.z]),
        outline(0xD3E4E3,[.m(27,-20),.l(29,-21),.l(29,-16),.q(26,-13,24,-13),.l(24,-15),.q(27,-17,27,-20),.z]),
        oval(0xAEC8CC,15,-15,2.4,2.4)
    ]
    static func paint(in c:CGContext,gait:CGFloat,tilt:CGFloat,lift:CGFloat,armAngle:CGFloat,tool:Bool,carrying:Bool) {
        func rotated(_ angle:CGFloat,_ x:CGFloat,_ y:CGFloat,_ layer:[Ink]) {
            c.saveGState();c.translateBy(x:x,y:y);c.rotate(by:angle);c.translateBy(x:-x,y:-y)
            draw(layer,in:c);c.restoreGState()
        }
        c.translateBy(x:0,y:-4.1-lift);c.translateBy(x:0,y:-14)
        c.rotate(by:tilt);c.translateBy(x:0,y:14);c.setLineCap(.round);c.setLineJoin(.round)
        rotated(-gait*0.24,-11,-27,back);draw(body,in:c);rotated(gait*0.018,1,-28,head)
        if carrying {rotated(-0.24,8,-20,log)}
        rotated(armAngle,10,-21,arm)
        if tool {rotated(armAngle,10,-21,axe)}
    }
}
