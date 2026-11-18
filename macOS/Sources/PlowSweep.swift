import Foundation

/// The steel blade swept between two rendered poses on one display (y grows downward).
struct PlowSweep {
    private let outlines: [[CGPoint]]
    let bounds: CGRect
    let advance, speed, direction: CGFloat
    var truckID:ObjectIdentifier?
    private var pushedSnow = CGRect.null

    init(from old: CGPoint, angle oldAngle: CGFloat, to new: CGPoint, angle: CGFloat, scale: CGFloat, speed: CGFloat, direction: CGFloat = 1) {
        let sign:CGFloat = direction < 0 ? -1 : 1
        let steel: [(CGFloat,CGFloat)] = [(30.6,-14),(34.6,-14.2),(31.6,-8),(33.4,-2.6),(35.8,-0.3),(31.9,-0.3),(28.5,-7.7)]
        func points(_ p:CGPoint,_ a:CGFloat) -> [CGPoint] {
            let c=cos(a)*scale,s=sin(a)*scale
            return steel.map { CGPoint(x:p.x+$0.0*sign*c-$0.1*s,y:p.y+$0.0*sign*s+$0.1*c) }
        }
        let a=points(old,oldAngle), b=points(new,angle)
        var faces=[a,b]
        for i in a.indices { let j=(i+1)%a.count;faces.append([a[i],a[j],b[j],b[i]]) }
        outlines=faces
        let all=a+b
        let left=all.map(\.x).min()!,right=all.map(\.x).max()!,top=all.map(\.y).min()!,bottom=all.map(\.y).max()!
        bounds=CGRect(x:left,y:top,width:right-left,height:bottom-top)
        self.advance=new.x-old.x;self.speed=speed;self.direction=sign
    }
    private func contains(_ point: CGPoint) -> Bool {
        for polygon in outlines {
            var inside=false
            for i in polygon.indices {
                let a=polygon[i],b=polygon[(i+1)%polygon.count]
                if (a.y>point.y) != (b.y>point.y), point.x < (b.x-a.x)*(point.y-a.y)/(b.y-a.y)+a.x {inside.toggle()}
            }
            if inside { return true }
        }
        return false
    }
    mutating func carryingSnow(on floor: Drift, scale: CGFloat) {
        let lip=direction>0 ? bounds.maxX:bounds.minX
        let a=lip+direction*floor.spacing*0.5,b=a+direction*min(14*scale,floor.spacing)
        let start=max(floor.edge.x,min(a,b)),end=min(floor.edge.x+floor.edge.width,max(a,b))
        guard end>start else {return}
        let depth=min(floor.height(start),floor.height(end),6*scale)
        if depth>1.2 { pushedSnow=CGRect(x:start,y:floor.edge.y-depth,width:end-start,height:depth) }
    }
    func touches(_ box: CGRect, includingSnow: Bool = false, ink: (CGPoint) -> Bool) -> Bool {
        let contact = includingSnow ? bounds.union(pushedSnow) : bounds
        let area=contact.intersection(box)
        guard !area.isNull,area.width>0,area.height>0 else {return false}
        let nx=max(1,Int(ceil(area.width/2.5))),ny=max(1,Int(ceil(area.height/2.5)))
        for j in 0..<ny {
            let y=area.minY+(CGFloat(j)+0.5)*area.height/CGFloat(ny)
            for i in 0..<nx {
                let p=CGPoint(x:area.minX+(CGFloat(i)+0.5)*area.width/CGFloat(nx),y:y)
                if (contains(p) || (includingSnow && pushedSnow.contains(p))) && ink(p) {return true}
            }
        }
        return false
    }
}
