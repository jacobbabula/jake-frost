import AppKit

final class SnowCanvas: NSView {
    let world = SnowWorld()
    let giftTrain = GiftTrain()
    let santaPresent = MacSantaPresent()
    let visitors = MacVisitors()
    let workshop = MacWorkshop()
    let weatherEffects = MacWeatherEffects()
    let ice = WindowIce()
    var iceLevel = 0
    var giftExistsElsewhere: ((String) -> Bool)?
    func containsReceivedGift(_ id: String) -> Bool {
        world.containsReceivedGift(id) || workshop.containsReceivedGift(id) || giftTrain.containsParcel(id)
    }
    var animating: Bool { world.hasMotion || (!world.paused && weatherEffects.isActive) || giftTrain.isMoving || visitors.isActive || workshop.hasMotion || santaPresent.animating }
    private var bankShapes = [(bank:Drift, revision:UInt, path:CGPath)]()
    private static let flakeColors = [NSColor(calibratedRed:0.79,green:0.89,blue:0.99,alpha:0.58),
                                     NSColor(calibratedWhite:0.97,alpha:0.85),NSColor.white]
    private static let snowColor = NSColor(calibratedRed:0.88,green:0.94,blue:0.99,alpha:0.98)
    private static let wispGradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),
        colors:[CGColor(gray:1,alpha:0.76),CGColor(red:0.88,green:0.96,blue:1,alpha:0.36),
                CGColor(gray:1,alpha:0)] as CFArray,locations:[0,0.43,1])
    private static let ballGradient = NSGradient(starting:.white,ending:NSColor(calibratedRed:0.65,green:0.79,blue:0.91,alpha:1))
    var allowTouch = true
    var puffFallingSnow = true
    private var leftWasDown = false
    private(set) var draggingSnow = false
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override init(frame: NSRect) {
        super.init(frame:frame)
        visitors.workshop=workshop
        workshop.invalidate = { [weak self] in self?.needsDisplay = true }
        visitors.onSantaDrop = { [weak self] point in self?.santaPresent.drop(at:point) }
        visitors.onPlow = { [weak self] blade in
            guard let self=self else {return}
            self.santaPresent.plow(blade,world:self.world)
        }
        visitors.pushWorkshop = { [weak self] blade in self?.workshop.plow(blade) }
        visitors.finishPlowing = { [weak self] in self?.workshop.finishPlowing() }
        giftTrain.groundY = { [weak self] x in
            guard let view=self else{return 0}
            return view.world.banks.first?.surface(x) ?? view.bounds.maxY
        }
        giftTrain.unload = { [weak self] parcel, foot in
            guard let self=self else { return false }
            if self.giftExistsElsewhere?(parcel.gift.id) == true { return true }
            switch parcel.gift.kind {
            case .tree: return self.workshop.receiveTree(parcel,at:foot)
            case .snowman: return self.world.receiveSnowman(parcel.gift,at:foot)
            case .note: return true
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }

    func frameTick(_ dt:TimeInterval, cursor:CGPoint) {
        let redraw = animating
        if giftTrain.needsParcelReconciliation && world.size.width > 1 {
            // Recover if the app closed after an overflow gift was saved to the workshop
            // and before its old train parcel was removed from preferences.
            giftTrain.reconcileParcels { workshop.containsReceivedGift($0) || world.containsReceivedGift($0) }
        }
        world.step(dt)
        visitors.step(dt,world:world)
        santaPresent.step(dt,world:world)
        giftTrain.step(dt,bounds:bounds)
        workshop.step(dt)
        workshop.sync(world:world)
        var pointer: CGPoint?
        if let win=window {
            let inside=win.frame.contains(cursor)
            let local=convert(win.convertPoint(fromScreen:cursor),from:nil)
            pointer = inside ? local : nil
            // Read the normal pointer state. Falling flakes never make the window catch input.
            let buttons=NSEvent.pressedMouseButtons
            sampleFlakeClick(at:pointer,down:buttons & 1 != 0,passThrough:win.ignoresMouseEvents) {
                NSApp.windows.contains { $0 !== win && $0.canBecomeKey && $0.isVisible && $0.frame.contains(cursor) }
            }
            let accept = draggingSnow || workshop.isDragging || (inside && buttons == 0 &&
                (santaPresent.captures(local) || workshop.captures(local) || (allowTouch && world.hit(local))))
            if win.ignoresMouseEvents == accept { win.ignoresMouseEvents = !accept }
        }
        weatherEffects.step(dt,world:world,pointer:pointer,paused:world.paused)
        if redraw || animating { needsDisplay=true }
    }
    override func mouseDown(with event:NSEvent) {
        leftWasDown=true
        let point=convert(event.locationInWindow,from:nil)
        if santaPresent.open(at:point,world:world) {needsDisplay=true;return}
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
    func sampleFlakeClick(at point:CGPoint?,down:Bool,passThrough:Bool,overControls:()->Bool) {
        defer {leftWasDown=down}
        guard down,!leftWasDown,puffFallingSnow,passThrough,world.snowEnabled,!world.paused,!workshop.editing,!draggingSnow,
              let p=point,!santaPresent.captures(p),!(allowTouch && world.hit(p)),!overControls() else {return}
        if world.puff(at:p,brush:false) {needsDisplay=true}
    }
    override func scrollWheel(with event:NSEvent) {
        let rotate=event.modifierFlags.contains(.shift)
        let delta=rotate && event.scrollingDeltaY==0 ? event.scrollingDeltaX : event.scrollingDeltaY
        if event.momentumPhase.isEmpty,workshop.scroll(at:convert(event.locationInWindow,from:nil),
                                                       delta:delta,precise:event.hasPreciseScrollingDeltas,rotating:rotate) {return}
        super.scrollWheel(with:event)
    }
    func releasePointer() {
        world.cancel();draggingSnow=false;window?.ignoresMouseEvents=true
    }

    override func draw(_ dirtyRect:NSRect) {
        // Clear previous flakes even where the next frame draws nothing.
        NSColor.clear.setFill();dirtyRect.fill(using:.copy)
        let layers=[NSBezierPath(),NSBezierPath(),NSBezierPath()]
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        for p in world.particles {
            if p.wisp,let gradient=Self.wispGradient {
                let pos=CGPoint(x:p.x,y:p.y),radius=p.radius*(1.55-min(1,p.life)*0.7)
                context.saveGState();context.setAlpha(min(0.85,p.life*1.8))
                context.drawRadialGradient(gradient,startCenter:pos,startRadius:0,endCenter:pos,endRadius:radius,options:[])
                context.restoreGState();continue
            }
            let index=p.powder ? (p.life>0.35 ? 2 : 0) : (p.radius<1.35 ? 0 : p.radius<2 ? 1 : 2)
            let r=p.powder ? p.radius*min(1,p.life*2.6) : p.radius
            layers[index].appendOval(in:CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2))
        }
        for i in layers.indices {Self.flakeColors[i].setFill();layers[i].fill()}
        weatherEffects.draw(in:context)
        ice.draw(context,banks:world.banks,level:world.snowEnabled ? iceLevel : 0)
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
                var previous=CGPoint(x:l,y:d.surface(l))
                while x<r {
                    let sample=CGPoint(x:x,y:d.surface(x))
                    let mid=CGPoint(x:(previous.x+x)/2,y:(previous.y+sample.y)/2)
                    path.addQuadCurve(to:mid,control:previous)
                    previous=sample;x+=d.spacing
                }
                path.addQuadCurve(to:CGPoint(x:r,y:d.surface(r)),control:previous)
                path.addLine(to:CGPoint(x:r,y:d.edge.y));path.closeSubpath()
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
        for figure in world.snowmen {
            context.saveGState();context.translateBy(x:figure.x,y:figure.foot)
            let fighter=world.battle.player(for:figure),face=fighter?.face ?? figure.facing
            if let p=fighter {
                context.rotate(by:face*(p.recoil*0.18-p.windup*0.065+p.follow*0.09))
                context.scaleBy(x:1+p.recoil*0.045+p.duck*0.045,y:1-p.recoil*0.12-p.duck*0.27)
            }
            giftTrain.drawSnowman(base:figure.base,middle:figure.middle,head:figure.head,style:figure.style,facing:face,in:context)
            if let p=fighter {SnowBattleArt.arm(p,in:context)}
            context.restoreGState()
        }
        SnowBattleArt.powder(in:context,world:world)
        workshop.draw()
        visitors.draw(in:context)
        giftTrain.draw(in:bounds)
        santaPresent.draw(in:bounds)
        weatherEffects.sky.drawForeground(in:context)
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
