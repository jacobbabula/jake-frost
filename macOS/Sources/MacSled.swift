import AppKit

@MainActor final class MacSledField {
    final class Sled {
        var x:CGFloat, y:CGFloat, vx:CGFloat=0, vy:CGFloat=0, angle:CGFloat=0
        var support:UInt32?, edgeX:CGFloat=0, edgeWidth:CGFloat=0
        init(at p:CGPoint) {x=p.x;y=p.y}
    }
    private(set) var sleds:[Sled]=[]
    private var held:Sled?, origin=CGPoint.zero, offset=CGPoint.zero
    private var samples:[(CGPoint,TimeInterval)]=[]
    private var moved=false
    private let halfSki:CGFloat=18
    var isDragging:Bool {held != nil}
    var hasMotion:Bool {isDragging || sleds.contains { $0.support==nil || abs($0.vx)>0.05 }}

    @discardableResult func add(at point:CGPoint,world:SnowWorld)->Sled {
        if sleds.count>=12 {sleds.removeFirst()}
        let s=Sled(at:point);sleds.append(s)
        if let bank=world.banks.filter({$0.edge.contains(s.x) && abs($0.surface(s.x)-point.y)<15})
            .min(by:{abs($0.surface(s.x)-point.y)<abs($1.surface(s.x)-point.y)}) {
            attach(s,to:bank)
        }
        return s
    }
    private func hit(_ point:CGPoint)->Sled? {
        sleds.reversed().first { s in
            let dx=point.x-s.x, dy=point.y-s.y
            let x=cos(s.angle)*dx+sin(s.angle)*dy, y = -sin(s.angle)*dx+cos(s.angle)*dy
            return abs(x)<=29 && (-19...3).contains(y)
        }
    }
    func captures(_ point:CGPoint)->Bool {hit(point) != nil}
    func down(_ point:CGPoint,time:TimeInterval)->Bool {
        guard let s=hit(point) else{return false}
        held=s;origin=point;offset=CGPoint(x:s.x-point.x,y:s.y-point.y);moved=false
        samples=[(point,time)];s.vx=0;s.vy=0;return true
    }
    func drag(_ point:CGPoint,time:TimeInterval) {
        guard let s=held else{return}
        moved = moved || hypot(point.x-origin.x,point.y-origin.y)>3
        guard moved else{return}
        s.support=nil;s.x=point.x+offset.x;s.y=point.y+offset.y
        samples.append((point,time));samples.removeAll {time-$0.1>0.16}
        if samples.count>30 {samples.removeFirst(samples.count-30)}
    }
    func up(_ point:CGPoint,time:TimeInterval,world:SnowWorld) {
        guard let s=held else{return}
        drag(point,time:time)
        if moved {
            if let first=samples.first,time-first.1>0.012 {
                let elapsed=CGFloat(time-first.1)
                s.vx=max(-540,min(540,(point.x-first.0.x)/elapsed))
                s.vy=max(-360,min(360,(point.y-first.0.y)/elapsed))
            }
            s.x=max(0,min(world.size.width,s.x))
            if let bank=world.banks.first(where:{$0.edge.contains(s.x) && abs($0.surface(s.x)-s.y)<9}) {
                attach(s,to:bank)
            }
        } else {
            // Push from the rear or the nose to send it away from the click.
            s.vx = point.x>s.x+2 ? -86:86
        }
        cancel()
    }
    func cancel() {held=nil;samples.removeAll();moved=false}
    func clear() {cancel();sleds.removeAll()}
    func plow(_ blade:PlowSweep,world:SnowWorld) {
        guard let floor=world.banks.first else {return}
        for s in sleds where s !== held && (s.support == nil || s.support == 0) {
            let box=CGRect(x:s.x-32,y:s.y-29,width:65,height:44)
            guard blade.touches(box,includingSnow:s.support==0,ink:{ pt in
                let dx=pt.x-s.x,dy=pt.y-s.y
                let x=dx*cos(s.angle)+dy*sin(s.angle),y=dy*cos(s.angle)-dx*sin(s.angle)
                return abs(x)<=23 && (-13 ... -6).contains(y) || abs(x)<=21 && (-3...0).contains(y)
            }) else {continue}
            s.x=min(max(0,world.size.width-27),s.x+blade.advance+0.6)
            s.vx=max(s.vx,blade.speed*1.22)
            if s.support==0 {attach(s,to:floor)}
        }
    }
    private func terrain(_ bank:Drift,at x:CGFloat)->(CGFloat,CGFloat) {
        let mid=bank.surface(x)
        let left=bank.edge.contains(x-halfSki) ? bank.surface(x-halfSki):mid
        let right=bank.edge.contains(x+halfSki) ? bank.surface(x+halfSki):mid
        return (min(mid,(left+right)/2),(right-left)/(2*halfSki))
    }
    private func attach(_ s:Sled,to bank:Drift) {
        let (height,slope)=terrain(bank,at:s.x)
        s.support=bank.edge.id;s.y=height;s.angle=atan(slope);s.vy=0
        s.edgeX=bank.edge.x;s.edgeWidth=bank.edge.width
    }
    @discardableResult func step(_ seconds:TimeInterval,world:SnowWorld) -> Bool {
        guard !sleds.isEmpty,world.size.width>1,seconds>0 else{return false}
        var changed=false
        let dt=CGFloat(min(0.1,seconds))
        let steps=max(1,Int(ceil(dt*60))),delta=dt/CGFloat(steps)
        for s in sleds where s !== held {
            let last=CGPoint(x:s.x,y:s.y),angle=s.angle
            for _ in 0..<steps {
                if let id=s.support,let bank=world.banks.first(where:{$0.edge.id==id}) {
                    if s.edgeWidth>0 && (s.edgeX != bank.edge.x || s.edgeWidth != bank.edge.width) {
                        s.x=bank.edge.x+(s.x-s.edgeX)/s.edgeWidth*bank.edge.width
                    }
                    if bank.edge.contains(s.x) {
                        let slope=terrain(bank,at:s.x).1
                        s.vx += 310*slope/(1+slope*slope)*delta
                        let speed=max(0,abs(s.vx)-(12+0.43*abs(s.vx))*delta)
                        s.vx=s.vx<0 ? -speed:speed
                        s.x+=s.vx*delta
                        if bank.edge.contains(s.x) {
                            attach(s,to:bank);continue
                        }
                        s.vy=s.vx*slope
                    }
                }
                s.support=nil
                let oldY=s.y
                s.vy+=350*delta;s.x+=s.vx*delta;s.y+=s.vy*delta
                if s.x<0 || s.x>world.size.width {
                    s.x=min(world.size.width,max(0,s.x));s.vx *= -0.32
                }
                var landing:Drift?,firstY=CGFloat.greatestFiniteMagnitude
                for d in world.banks where d.edge.contains(s.x) {
                    let y=terrain(d,at:s.x).0
                    if y>=oldY-2.5 && y<=s.y+0.3 && y<firstY {firstY=y;landing=d}
                }
                if let d=landing {
                    if s.vy>95 {world.burst(CGPoint(x:s.x,y:firstY),count:7,strength:0.45)}
                    attach(s,to:d)
                } else if s.y>=world.size.height,let floor=world.banks.first {attach(s,to:floor)}
            }
            changed=changed || abs(last.x-s.x)+abs(last.y-s.y)+abs(angle-s.angle)>0.01
        }
        return changed
    }

    private static let image:NSImage = {
        let image=NSImage(size:CGSize(width:64,height:30),flipped:true) { _ in
            guard let c=NSGraphicsContext.current?.cgContext else{return false}
            c.saveGState();defer {c.restoreGState()}
            c.translateBy(x:30,y:25);c.setLineJoin(.round);c.setLineCap(.round)
            func color(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat)->CGColor {CGColor(red:r,green:g,blue:b,alpha:1)}
            func line(_ ink:CGColor,_ width:CGFloat,_ path:(CGContext)->Void) {
                c.setStrokeColor(ink);c.setLineWidth(width);c.beginPath();path(c);c.strokePath()
            }
            func bar(_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat,_ ink:CGColor) {
                c.setFillColor(ink);c.addPath(CGPath(roundedRect:CGRect(x:x,y:y,width:w,height:h),cornerWidth:1.3,cornerHeight:1.3,transform:nil));c.fillPath()
            }
            let metal=color(0.51,0.63,0.67),shine=color(0.86,0.91,0.87)
            let runner:(CGContext)->Void={ c in
                c.move(to:.init(x:-25,y:-6));c.addQuadCurve(to:.init(x:-16,y:-1.3),control:.init(x:-23,y:-1.3))
                c.addLine(to:.init(x:17,y:-1.3));c.addQuadCurve(to:.init(x:27,y:-9),control:.init(x:24,y:-1.3))
            }
            line(metal,2.7,runner);line(shine,0.85,runner)
            for x:CGFloat in [-15,11] {
                line(metal,2.8) {p in p.move(to:.init(x:x,y:-2));p.addLine(to:.init(x:x+3,y:-10))}
            }
            bar(-24,-13,45,6,color(0.58,0.25,0.20));bar(-23,-13,44,2.4,color(0.97,0.66,0.39))
            for x:CGFloat in [-16,-2,13] {bar(x,-13,1.9,6,color(0.73,0.44,0.24))}
            line(color(0.8,0.28,0.32),1.6) {p in
                p.move(to:.init(x:19,y:-11));p.addQuadCurve(to:.init(x:28,y:-16),control:.init(x:26,y:-8))
                p.addQuadCurve(to:.init(x:31,y:-16),control:.init(x:30,y:-20))
            }
            return true
        }
        image.cacheMode = .always;return image
    }()
    func draw() {
        guard !sleds.isEmpty,let c=NSGraphicsContext.current?.cgContext else{return}
        for s in sleds {
            c.saveGState();c.translateBy(x:s.x,y:s.y);c.rotate(by:s.angle)
            Self.image.draw(in:CGRect(x:-30,y:-25,width:64,height:30),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            c.restoreGState()
        }
    }
}
