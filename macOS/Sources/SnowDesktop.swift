import AppKit

final class SnowCanvas: NSView {
    let world = SnowWorld()
    let giftTrain = GiftTrain()
    let visitors = MacVisitors()
    let workshop = MacWorkshop()
    var animating: Bool { world.hasMotion || giftTrain.isMoving || visitors.isActive || workshop.hasMotion }
    private var bankShapes = [(bank:Drift, revision:UInt, path:CGPath)]()
    private static let flakeColors = [NSColor(calibratedRed:0.79,green:0.89,blue:0.99,alpha:0.58),
                                     NSColor(calibratedWhite:0.97,alpha:0.85),NSColor.white]
    private static let snowColor = NSColor(calibratedRed:0.88,green:0.94,blue:0.99,alpha:0.98)
    private static let ballGradient = NSGradient(starting:.white,ending:NSColor(calibratedRed:0.65,green:0.79,blue:0.91,alpha:1))
    var allowTouch = true
    private(set) var draggingSnow = false
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override init(frame: NSRect) {
        super.init(frame:frame)
        workshop.invalidate = { [weak self] in self?.needsDisplay = true }
        giftTrain.groundY = { [weak self] x in
            guard let view=self else{return 0}
            return view.world.banks.first?.surface(x) ?? view.bounds.maxY
        }
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }

    func frameTick(_ dt:TimeInterval, cursor:CGPoint) {
        let redraw = animating
        world.step(dt)
        visitors.step(dt,world:world)
        giftTrain.step(dt,bounds:bounds)
        workshop.step(dt)
        workshop.sync(world:world)
        if let win=window {
            let inside=win.frame.contains(cursor)
            let local=convert(win.convertPoint(fromScreen:cursor),from:nil)
            // This reads the pointer position without monitoring or intercepting other apps' events.
            let accept = draggingSnow || workshop.isDragging || (inside && NSEvent.pressedMouseButtons == 0 &&
                (workshop.captures(local) || (allowTouch && world.hit(local))))
            if win.ignoresMouseEvents == accept { win.ignoresMouseEvents = !accept }
        }
        if redraw { needsDisplay=true }
    }
    override func mouseDown(with event:NSEvent) {
        let point=convert(event.locationInWindow,from:nil)
        if workshop.down(point) { return }
        draggingSnow = allowTouch && world.down(point,at:event.timestamp)
        needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent) {
        if workshop.isDragging { workshop.drag(convert(event.locationInWindow,from:nil));return }
        if draggingSnow {world.drag(convert(event.locationInWindow,from:nil),at:event.timestamp);needsDisplay=true}
    }
    override func mouseUp(with event:NSEvent) {
        if workshop.isDragging { workshop.up(convert(event.locationInWindow,from:nil));return }
        if draggingSnow {world.up(convert(event.locationInWindow,from:nil),at:event.timestamp)}
        draggingSnow=false;needsDisplay=true
    }
    func releasePointer() {
        world.cancel();draggingSnow=false;window?.ignoresMouseEvents=true
    }

    override func draw(_ dirtyRect:NSRect) {
        // Clear previous flakes even where the next frame draws nothing.
        NSColor.clear.setFill();dirtyRect.fill(using:.copy)
        let layers=[NSBezierPath(),NSBezierPath(),NSBezierPath()]
        for p in world.particles {
            let index=p.powder ? (p.life>0.35 ? 2 : 0) : (p.radius<1.35 ? 0 : p.radius<2 ? 1 : 2)
            let r=p.powder ? p.radius*min(1,p.life*2.6) : p.radius
            layers[index].appendOval(in:CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2))
        }
        for i in layers.indices {Self.flakeColors[i].setFill();layers[i].fill()}
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if bankShapes.count > world.banks.count { bankShapes.removeLast(bankShapes.count-world.banks.count) }
        context.setFillColor(Self.snowColor.cgColor)
        for (index,d) in world.banks.enumerated() {
            if index < bankShapes.count && bankShapes[index].bank === d && bankShapes[index].revision == d.revision {
                context.addPath(bankShapes[index].path);continue
            }
            let path=CGMutablePath()
            for interval in d.edge.visible {
                let l=interval.lowerBound,r=interval.upperBound
                path.move(to:CGPoint(x:l,y:d.edge.y))
                path.addLine(to:CGPoint(x:l,y:d.surface(l)))
                let first=Int(floor((l-d.edge.x)/d.spacing))+1
                var x=d.edge.x+CGFloat(first)*d.spacing
                while x<r {path.addLine(to:CGPoint(x:x,y:d.surface(x)));x+=d.spacing}
                path.addLine(to:CGPoint(x:r,y:d.surface(r)));path.addLine(to:CGPoint(x:r,y:d.edge.y));path.closeSubpath()
            }
            let entry = (d,d.revision,path as CGPath)
            if index < bankShapes.count {bankShapes[index]=entry} else {bankShapes.append(entry)}
            context.addPath(path)
        }
        context.fillPath()
        for b in world.balls {
            let body=NSBezierPath(ovalIn:CGRect(x:b.x-b.radius,y:b.y-b.radius,width:2*b.radius,height:2*b.radius))
            Self.ballGradient?.draw(in:body,relativeCenterPosition:CGPoint(x:-0.38,y:-0.45))
        }
        workshop.draw()
        visitors.draw(in:context)
        giftTrain.draw(in:bounds)
    }
}

final class SnowPanel: NSPanel {
    override var canBecomeKey: Bool {false}
    override var canBecomeMain: Bool {false}
}

@MainActor final class ScreenScene {
    let panel: SnowPanel
    let view: SnowCanvas
    init(frame:CGRect) {
        panel=SnowPanel(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isFloatingPanel=true;panel.hidesOnDeactivate=false;panel.isReleasedWhenClosed=false
        panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=false;panel.ignoresMouseEvents=true
        panel.level = .floating;panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle,.stationary]
        view=SnowCanvas(frame:CGRect(origin:.zero,size:frame.size))
        view.autoresizingMask=[.width,.height];panel.contentView=view
        panel.setFrame(frame,display:true)
        panel.orderFrontRegardless()
    }
}
