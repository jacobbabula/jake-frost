import AppKit

/// Draws in the snow view's flipped, display-local coordinate system.
@MainActor final class GiftTrain {
    private final class Delivery {
        let gift: FrostGift
        var receipt: (() -> Void)?
        var x: CGFloat = -25, travel: CGFloat = 0
        var dwell: TimeInterval = 0
        init(_ gift: FrostGift, _ receipt: (() -> Void)?) { self.gift = gift; self.receipt = receipt }
    }
    private struct Ornament {
        var kind: Int, x: CGFloat, y: CGFloat, scale: CGFloat = 1, angle: CGFloat = 0
    }
    private struct Parcel {
        let gift: FrostGift
        var x: CGFloat, tilt: CGFloat = 0, ornaments: [Ornament] = []
        init(_ gift: FrostGift, x: CGFloat) {
            self.gift = gift; self.x = x
            guard gift.kind == .tree else { return }
            for row in gift.dress.components(separatedBy: ";") {
                let a = row.components(separatedBy: ",")
                func n(_ i: Int) -> CGFloat? {
                    guard i < a.count, let v = Double(a[i]), v.isFinite, abs(v) < 1_000_000 else { return nil }
                    return CGFloat(v)
                }
                if a[0] == "angles" {
                    tilt = n(1) ?? 0
                    for i in ornaments.indices { ornaments[i].angle = n(i + 2) ?? 0 }
                } else if a[0] == "scale" {
                    for i in stride(from: 1, to: a.count - 1, by: 2) {
                        if let index = Int(a[i]), ornaments.indices.contains(index), let scale = n(i + 1) {
                            ornaments[index].scale = max(0.35, min(4, scale))
                        }
                    }
                } else if a.count == 3, ornaments.count < 160, let k = Int(a[0]), (2...16).contains(k),
                          let x = n(1), let y = n(2) {
                    ornaments.append(Ornament(kind: k, x: max(-0.35,min(0.35,x)), y: max(-1.02,min(-0.08,y))))
                }
            }
        }
    }

    var groundY: ((CGFloat) -> CGFloat)?
    private var trains: [Delivery] = [], parcels: [Parcel] = []
    private var station: CGFloat = 320
    private var scale: CGFloat = 1, pace: CGFloat = 1
    var hasActivity: Bool { !trains.isEmpty || !parcels.isEmpty }
    var isMoving: Bool { !trains.isEmpty }

    func configure(_ controls: MacVisitorControls) {
        scale = controls.scale(for:.train)
        pace = controls.pace(for:.train)
    }

    // An ordinary elf visit passes straight through. Only real gifts dock and acknowledge.
    func visit() {
        guard trains.isEmpty else { return }
        let train = Delivery(FrostGift(),nil)
        train.x = -25 * scale
        trains.append(train)
    }

    @discardableResult func start(_ gift: FrostGift, onArrival: @escaping () -> Void) -> Bool {
        guard trains.count < 4, trains.allSatisfy({ $0.receipt == nil && $0.x > station + 130 * scale }) else { return false }
        let train = Delivery(gift, onArrival)
        train.x = -25 * scale
        trains.append(train)
        return true
    }
    @discardableResult func cancel() -> Bool {
        let interrupted = trains.contains { $0.receipt != nil }
        trains.removeAll()
        return interrupted
    }
    @discardableResult func clear() -> Bool { parcels.removeAll(); return cancel() }

    func step(_ dt: TimeInterval, bounds: CGRect) {
        station = min(540, max(80, bounds.width * 0.46))
        let delta = CGFloat(max(0,min(0.1,dt)))
        for train in trains {
            let old = train.x
            if train.receipt != nil {
                train.x = min(station, train.x + delta * 64 * pace)
                if train.x >= station {
                    if train.gift.kind != .note {
                        if parcels.count == 48 { parcels.removeFirst() }
                        let offset = CGFloat(parcels.count % 5) * 32
                        parcels.append(Parcel(train.gift, x: max(35, station - 83 - offset)))
                    }
                    train.dwell = max(11, 7 + Double(train.gift.note.utf16.count) / 16)
                    let done = train.receipt
                    train.receipt = nil
                    done?()
                }
            } else if train.dwell > 0 { train.dwell -= Double(delta) }
            else { train.x += delta * 73 * pace }
            train.travel += abs(train.x - old)
        }
        trains.removeAll { $0.x > bounds.maxX + 110 * scale }
    }

    func draw(in bounds: CGRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        for parcel in parcels {
            let x = max(18,min(bounds.width - 18,parcel.x))
            c.saveGState(); c.translateBy(x: x, y: groundY?(x) ?? bounds.maxY - 2)
            if parcel.gift.kind == .tree { drawTree(parcel,c) } else {
                let g=parcel.gift
                drawSnowman(base:CGFloat(g.size),middle:CGFloat(g.mid),head:CGFloat(g.head),style:g.style,facing:CGFloat(g.facing),in:c)
            }
            c.restoreGState()
        }
        for train in trains {
            let y = groundY?(train.x) ?? bounds.maxY - 2
            c.saveGState(); c.translateBy(x: train.x, y: y)
            c.scaleBy(x:scale,y:scale)
            drawEngine(train.travel/scale,c); c.restoreGState()
            if train.receipt == nil && train.dwell > 0 { caption(train.gift, at: CGPoint(x:train.x,y:y-43*scale), bounds:bounds,c) }
        }
    }

    private func color(_ rgb: Int, alpha: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((rgb>>16)&255)/255, green: CGFloat((rgb>>8)&255)/255, blue: CGFloat(rgb&255)/255, alpha: alpha)
    }
    private func rect(_ c: CGContext,_ rgb: Int,_ x: CGFloat,_ y: CGFloat,_ w: CGFloat,_ h: CGFloat,_ r: CGFloat=1) {
        c.setFillColor(color(rgb))
        c.addPath(CGPath(roundedRect:CGRect(x:x,y:y,width:w,height:h),cornerWidth:r,cornerHeight:r,transform:nil)); c.fillPath()
    }
    private func dot(_ c: CGContext,_ rgb: Int,_ x:CGFloat,_ y:CGFloat,_ rx:CGFloat,_ ry:CGFloat) {
        c.setFillColor(color(rgb)); c.fillEllipse(in:CGRect(x:x-rx,y:y-ry,width:2*rx,height:2*ry))
    }
    private func polygon(_ c:CGContext,_ rgb:Int,_ points:[CGPoint]) {
        c.setFillColor(color(rgb)); c.beginPath(); c.addLines(between:points); c.closePath(); c.fillPath()
    }
    private func point(_ x:CGFloat,_ y:CGFloat) -> CGPoint { CGPoint(x:x,y:y) }
    private func line(_ c:CGContext,_ rgb:Int,_ width:CGFloat,_ a:CGPoint,_ b:CGPoint) {
        c.setStrokeColor(color(rgb)); c.setLineWidth(width); c.setLineCap(.round)
        c.beginPath();c.move(to:a);c.addLine(to:b);c.strokePath()
    }

    private func drawEngine(_ travel: CGFloat,_ c: CGContext) {
        // Wheels and coupling rods rotate in proportion to distance travelled.
        line(c,0xD7BA87,2,point(-39,-7),point(-23,-7))
        rect(c,0x804A44,-78,-18,39,12,2);rect(c,0xDCAD71,-78,-18,39,3)
        for i in 0..<3 {
            let x = -75 + CGFloat(i)*12
            rect(c,[0xD05D58,0x74B3A1,0xE2B663][i],x,-24,10,8)
            rect(c,0xF5D787,x+4,-25,2,9)
        }
        rect(c,0x9D4B45,-26,-30,19,23,2);rect(c,0x5D98A3,-23,-27,11,10)
        rect(c,0xF6DFB3,-24,-28,13,2)
        dot(c,0xE1BA93,-18,-21.5,2.5,2.7)
        polygon(c,0x39765B,[point(-21,-22),point(-19,-27),point(-15,-23)])
        dot(c,0xF3D590,-18.7,-26.7,0.9,0.9)
        rect(c,0x374951,-29,-33,24,4,2);rect(c,0xE7E9DD,-29,-34,24,2)
        rect(c,0x387467,-9,-22,27,15,5);rect(c,0xD3AA63,5,-22,3,15)
        rect(c,0x283C44,10,-31,6,13);rect(c,0x35454A,8,-33,10,4)
        rect(c,0xA24B42,-26,-10,47,4)
        dot(c,0xF5CF7A,18,-17,2.8,2.8)
        for x: CGFloat in [-71,-48,-19,-3,12] {
            dot(c,0x263940,x,-5,5,5);dot(c,0xAB6752,x,-5,3.6,3.6)
            let angle=travel/5
            line(c,0xE7CB9C,1,point(x,-5),point(x+cos(angle)*3,-5+sin(angle)*3))
        }
        let d = point(cos(travel/5)*2.3,sin(travel/5)*2.3)
        line(c,0xE2D5B7,1.2,point(-19+d.x,-5+d.y),point(12+d.x,-5+d.y))
    }

    private func drawTree(_ parcel: Parcel,_ c: CGContext) {
        let s=CGFloat(parcel.gift.size), a=parcel.tilt * .pi / 180
        let contour=[point(-0.04,0),point(0.04,0),point(-0.34,-0.15),point(0.34,-0.15),point(0,-1)]
        let bottom = contour.map { $0.x*sin(a)+$0.y*cos(a) }.max() ?? 0
        c.translateBy(x:0,y:-s*bottom); c.rotate(by:a); c.scaleBy(x:s,y:s)
        rect(c,0x84624C,-0.045,-0.24,0.09,0.24,0.02)
        let pine = [0x34634F,0x3B7463,0x487859][parcel.gift.style % 3]
        for (tip,y,w) in [(-0.77,-0.14,0.34),(-0.89,-0.37,0.27),(-1.0,-0.58,0.19)] {
            let t=CGFloat(tip), b=CGFloat(y), width=CGFloat(w)
            polygon(c,pine,[point(0,t),point(width,b-0.04),point(width*0.68,b-0.055),point(width*0.45,b),point(0,b-0.035),point(-width*0.50,b),point(-width,b-0.04)])
            polygon(c,0xD2E6DD,[point(0,t),point(width*0.44,t+(b-t)*0.52),point(width*0.16,t+(b-t)*0.43),point(-width*0.23,t+(b-t)*0.57),point(-width*0.46,t+(b-t)*0.53)])
        }
        let localTreeHeight = WorkshopSymbol.forKind(.tree).bounds.height
        for ornament in parcel.ornaments {
            guard let kind = WorkshopKind(giftOrnamentID: ornament.kind) else { continue }
            c.saveGState(); c.translateBy(x:ornament.x,y:ornament.y); c.rotate(by:ornament.angle * .pi/180)
            let unit = TreeAttachment.ornamentScale * ornament.scale / localTreeHeight
            c.scaleBy(x:unit,y:unit)
            WorkshopSymbol.forKind(kind).draw()
            c.restoreGState()
        }
    }

    func drawSnowman(base b:CGFloat,middle m:CGFloat,head h:CGFloat,style:Int,facing:CGFloat,in c:CGContext) {
        let base = -b, middle=base-0.78*(b+m), top=middle-0.78*(m+h), dir:CGFloat=facing<0 ? -1:1
        for (r,y) in [(b,base),(m,middle),(h,top)] {
            dot(c,0xC1DCE6,0,y,r,r);dot(c,0xF4F9F8,-r*0.07,y-r*0.06,r*0.90,r*0.90)
        }
        let scarf=[0xBA524B,0x467B73,0x577C9F][style % 3]
        rect(c,scarf,-h,top+h*0.55,2*h,h*0.36,h*0.15)
        rect(c,scarf,h*0.08,top+h*0.77,h*0.39,h*0.9)
        for y in [middle-m*0.20,middle+m*0.32,base-b*0.25] { dot(c,0x394548,0,y,max(0.8,m*0.12),max(0.8,m*0.12)) }
        dot(c,0x364149,-h*0.3,top-h*0.1,h*0.1,h*0.1);dot(c,0x364149,h*0.33,top-h*0.13,h*0.1,h*0.1)
        polygon(c,0xD99052,[point(0,top),point(h*0.91*dir,top+h*0.20),point(0,top+h*0.24)])
        rect(c,0x36474E,-h*1.08,top-h,2.16*h,h*0.23);rect(c,0x36474E,-h*0.7,top-h*1.88,1.4*h,h*0.96)
    }

    private func caption(_ gift:FrostGift,at p:CGPoint,bounds:CGRect,_ c:CGContext) {
        let sender=gift.sender.isEmpty ? "A friend" : gift.sender
        let text=(gift.note.isEmpty ? "A \(gift.kind.rawValue.lowercased()) from \(sender)" : "\(sender)\n\(gift.note)") as NSString
        let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byWordWrapping
        let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:13,weight:.medium),.foregroundColor:NSColor.white,.paragraphStyle:paragraph]
        let maxWidth=max(40,min(262,bounds.width-36))
        let box=text.boundingRect(with:CGSize(width:maxWidth,height:500),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attributes)
        let w=ceil(box.width)+20,h=ceil(box.height)+14
        let x=max(3,min(bounds.width-w-3,p.x-w/2)),y=max(3,p.y-h)
        rect(c,0x243A40,x,y,w,h,8)
        text.draw(with:CGRect(x:x+10,y:y+7,width:w-19,height:h-12),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attributes)
    }
}
