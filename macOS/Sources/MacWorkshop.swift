import AppKit

struct WorkshopPiece: Codable {
    var id = UUID()
    var kind: WorkshopKind
    var center: CGPoint
    var scale: CGFloat = 1
    var angle: CGFloat = 0
    var span: CGFloat = 130
    var sag: CGFloat = 22
    var palette: Int = 0
    var onFloor = false

    func wirePoint(_ t: CGFloat) -> CGPoint {
        let u = (t - 0.5) * span
        return CGPoint(x:center.x + cos(angle)*u,y:center.y + sin(angle)*u + 4*sag*t*(1-t))
    }
}

@MainActor final class MacWorkshop: NSObject {
    private struct Saved: Codable {
        let size: CGSize
        let pieces: [WorkshopPiece]
    }
    private struct Mount { var id: UInt32; var fraction: CGFloat }
    private enum Action { case move, size, rotate, start, end, sag, remove, newWire }
    private struct Gesture {
        let action: Action
        let piece: WorkshopPiece
        let origin: CGPoint
    }
    private var settings: UserDefaults?, key = ""
    private weak var world: SnowWorld?
    private var size = CGSize.zero
    private var mounts: [UUID:Mount] = [:]
    private var extents: [UUID:CGRect] = [:]
    private struct Paint {let path:CGPath;let color:CGColor}
    private var wires: [UUID: [Paint]] = [:]
    private var pending: WorkshopKind?, gesture: Gesture?
    private enum PlayTool {case pile, sled, push}
    private var playTool:PlayTool?, brushPoint:CGPoint?
    private var puffClock:TimeInterval=0
    private let sleds=MacSledField()
    private(set) var pieces: [WorkshopPiece] = []
    var onEditingChanged: (() -> Void)?
    private(set) var editing = false {
        // Selecting a different tool should fold a panel the user reopened while editing.
        didSet { if editing || oldValue {onEditingChanged?()} }
    }
    private(set) var selected: UUID?
    private var index: Int? { pieces.firstIndex { $0.id == selected } }
    var isDragging: Bool { gesture != nil || brushPoint != nil || sleds.isDragging }
    var hasMotion: Bool { brushPoint != nil || sleds.hasMotion }
    var invalidate: (() -> Void)?
    private static let limit = 100
    private static let paletteNames = ["Carnival", "Warm white", "Aurora", "Peppermint"]
    private static let bulbs = [
        [0xFF7483,0xFFD36A,0x66E1BA,0x70C9FF,0xB69BFF,0xFFA6D0],
        [0xFFD487,0xFFF1C1,0xFFDDB0], [0x80E6CA,0x75C6F6,0xC19DF6],
        [0xFF8C8F,0xFFF2DB,0x80C9AD]
    ]

    func configure(settings:UserDefaults,displayID:UInt32) {
        let name="workshop.v1.\(displayID)"
        guard self.settings !== settings || key != name else { return }
        self.settings=settings; key=name
        pieces=[];size = .zero;selected=nil;mounts.removeAll();extents.removeAll();wires.removeAll()
        if let data=settings.data(forKey:name),data.count<=120_000,
           let saved=try? JSONDecoder().decode(Saved.self,from:data),
           saved.size.width>0,saved.size.height>0 {
            size=saved.size
            var seen=Set<UUID>()
            for p in saved.pieces.prefix(Self.limit) where seen.insert(p.id).inserted {
                guard (0.4...3.5).contains(p.scale),(26...3200).contains(p.span),(-220...340).contains(p.sag),
                      Self.bulbs.indices.contains(p.palette),abs(p.angle)<=2 * .pi,
                      p.center.x.isFinite,p.center.y.isFinite else {continue}
                pieces.append(p)
            }
        }
        invalidate?()
    }
    private func save() {
        guard let settings=settings,!key.isEmpty,size.width>0,size.height>0 else{return}
        if pieces.isEmpty {settings.removeObject(forKey:key);return}
        if let data=try? JSONEncoder().encode(Saved(size:size,pieces:pieces)) {settings.set(data,forKey:key)}
    }
    private func extent(_ p:WorkshopPiece)->CGRect {
        if let b=extents[p.id] {return b}
        let b=WorkshopSymbol.forKind(p.kind).rotatedBounds(scale:p.scale,angle:p.angle)
        extents[p.id]=b;return b
    }
    private func position(_ p:inout WorkshopPiece, at contact:CGPoint) {
        p.center=CGPoint(x:contact.x,y:contact.y-extent(p).maxY)
    }
    @discardableResult func sync(world:SnowWorld)->Bool {
        self.world=world
        let next=world.size
        guard next.width>0,next.height>0 else{return false}
        var changed=false
        if size != next {
            if size.width>0,size.height>0 {
                for i in pieces.indices {
                    pieces[i].center.x *= next.width/size.width
                    pieces[i].center.y *= next.height/size.height
                }
            }
            size=next;changed=true
            for i in pieces.indices where pieces[i].onFloor {
                mounts[pieces[i].id]=Mount(id:0,fraction:pieces[i].center.x/size.width)
            }
        }
        if !pieces.isEmpty {
            for i in pieces.indices {
                let p=pieces[i]
                guard let m=mounts[p.id] else{
                    if p.onFloor,let ground=world.banks.first {mounts[p.id]=Mount(id:0,fraction:(p.center.x-ground.edge.x)/ground.edge.width)}
                    continue
                }
                guard let bank=world.banks.first(where:{$0.edge.id==m.id}) else {
                    mounts.removeValue(forKey:p.id);continue
                }
                let x=bank.edge.x + bank.edge.width*m.fraction
                guard bank.edge.contains(x) else{continue}
                let y=bank.surface(x)-extent(p).maxY
                if abs(p.center.x-x)>0.04 || abs(p.center.y-y)>0.04 {
                    pieces[i].center=CGPoint(x:x,y:y);changed=true
                }
            }
        }
        if changed {invalidate?()};return changed
    }
    private func snap(_ i:Int) {
        let p=pieces[i]
        guard p.kind != .lights,let world=world else{return}
        let foot=p.center.y+extent(p).maxY
        let candidates=world.banks.filter { $0.edge.contains(p.center.x) && abs($0.surface(p.center.x)-foot)<15 }
        guard let bank=candidates.min(by:{ abs($0.surface(p.center.x)-foot) < abs($1.surface(p.center.x)-foot) }) else{return}
        mounts[p.id]=Mount(id:bank.edge.id,fraction:(p.center.x-bank.edge.x)/bank.edge.width)
        pieces[i].center.y=bank.surface(p.center.x)-extent(p).maxY
        pieces[i].onFloor=bank.edge.id==0
    }
    func beginPlacement(_ kind:WorkshopKind) {
        guard pieces.count < Self.limit else{return}
        resetTools();pending=kind;editing=true;invalidate?()
    }
    private func resetTools() {cancelGesture();playTool=nil;pending=nil;selected=nil}
    func arrange() {resetTools();editing=true;invalidate?()}
    func finishEditing() {resetTools();editing=false;invalidate?()}
    @objc func beginPiling() {resetTools();playTool = .pile;editing=true;invalidate?()}
    @objc func placeSled() {resetTools();playTool = .sled;editing=true;invalidate?()}
    @objc private func pushSleds() {resetTools();playTool = .push;editing=true;invalidate?()}
    func clear() {
        pending=nil;gesture=nil;editing=false;selected=nil;playTool=nil;brushPoint=nil;sleds.clear()
        pieces.removeAll();mounts.removeAll();extents.removeAll();wires.removeAll()
        save();invalidate?()
    }
    private func removeSelected() {
        guard let i=index else{return}
        let id=pieces.remove(at:i).id
        mounts.removeValue(forKey:id);extents.removeValue(forKey:id);wires.removeValue(forKey:id)
        selected=nil;gesture=nil;save();invalidate?()
    }
    private func distance(_ a:CGPoint,_ b:CGPoint)->CGFloat { hypot(a.x-b.x,a.y-b.y) }
    private func box(_ p:WorkshopPiece)->CGRect {
        let b=extent(p).offsetBy(dx:p.center.x,dy:p.center.y).insetBy(dx:-4,dy:-4)
        return b.insetBy(dx:min(0,(b.width-38)/2),dy:min(0,(b.height-36)/2))
    }
    private func handles(_ p:WorkshopPiece)->[(Action,CGPoint)] {
        if p.kind == .lights {return [(.start,p.wirePoint(0)),(.end,p.wirePoint(1)),(.sag,p.wirePoint(0.5))]}
        let b=box(p)
        let lowY=max(8,min(size.height-8,b.minY)),highY=max(8,min(size.height-8,b.maxY))
        return [(.remove,CGPoint(x:b.minX,y:lowY)),(.rotate,CGPoint(x:b.maxX,y:lowY)),(.size,CGPoint(x:b.maxX,y:highY))]
    }
    private func body(_ p:WorkshopPiece, hits q:CGPoint)->Bool {
        if p.kind == .lights {
            let dx=cos(p.angle)*p.span,dy=sin(p.angle)*p.span
            let a=p.wirePoint(0)
            // Broad phase also covers the bulbs extending below a diagonal wire.
            let area=CGRect(x:min(a.x,a.x+dx)-12,y:min(a.y,a.y+dy)+min(0,p.sag)-12,
                            width:abs(dx)+24,height:abs(dy)+abs(p.sag)+28)
            guard area.contains(q) else{return false}
            var last=a
            for i in 1...32 {
                let next=p.wirePoint(CGFloat(i)/32), vx=next.x-last.x,vy=next.y-last.y
                let t=max(0,min(1,((q.x-last.x)*vx+(q.y-last.y)*vy)/max(0.001,vx*vx+vy*vy)))
                if distance(q,CGPoint(x:last.x+t*vx,y:last.y+t*vy))<=max(8,5*p.scale){return true}
                last=next
            }
            return false
        }
        guard box(p).contains(q) else {return false}
        let dx=(q.x-p.center.x)/p.scale,dy=(q.y-p.center.y)/p.scale
        let local=CGPoint(x:dx*cos(p.angle)+dy*sin(p.angle),y:-dx*sin(p.angle)+dy*cos(p.angle))
        return WorkshopSymbol.forKind(p.kind).contains(local)
    }
    private func action(at q:CGPoint)->(Int,Action)? {
        if let i=index {
            for (action,p) in handles(pieces[i]) where distance(q,p)<=9 {return(i,action)}
        }
        for i in pieces.indices.reversed() where body(pieces[i],hits:q) {return(i,.move)}
        return nil
    }
    func captures(_ point:CGPoint)->Bool {
        if isDragging {return true}
        if playTool == .push {return sleds.captures(point)}
        return editing && (playTool != nil || pending != nil || action(at:point) != nil)
    }
    @discardableResult func down(_ point:CGPoint)->Bool {
        if let tool=playTool,let w=world {
            switch tool {
            case .sled: _=sleds.add(at:point,world:w);playTool = .push
            case .push: return sleds.down(point,time:ProcessInfo.processInfo.systemUptime)
            case .pile: brushPoint=point;puffClock=0;pile(at:point,amount:3.4,world:w)
            }
            invalidate?();return true
        }
        guard editing else{return false}
        if let kind=pending {
            guard pieces.count<Self.limit else{pending=nil;return false}
            pending=nil
            var p=WorkshopPiece(kind:kind,center:point)
            if kind != .lights {position(&p,at:point)}
            selected=p.id;pieces.append(p)
            gesture=Gesture(action:kind == .lights ? .newWire : .move,piece:p,origin:point)
        } else if let (i,action)=action(at:point) {
            selected=pieces[i].id
            if action == .remove {removeSelected();return true}
            gesture=Gesture(action:action,piece:pieces[i],origin:point)
        } else {return false}
        invalidate?();return true
    }
    func drag(_ point:CGPoint) {
        if sleds.isDragging {sleds.drag(point,time:ProcessInfo.processInfo.systemUptime);invalidate?();return}
        if let previous=brushPoint,let w=world {
            let distance=hypot(point.x-previous.x,point.y-previous.y)
            let count=min(40,Int(distance/5))
            if count>0 {
                for j in 1...count {
                    let f=CGFloat(j)/CGFloat(count)
                    pile(at:CGPoint(x:previous.x+(point.x-previous.x)*f,y:previous.y+(point.y-previous.y)*f),amount:0.8,world:w)
                }
                invalidate?()
            }
            brushPoint=point;return
        }
        guard let g=gesture,let i=index else{return}
        let old=g.piece
        var p=pieces[i]
        switch g.action {
        case .move:
            p.center=CGPoint(x:old.center.x+point.x-g.origin.x,y:old.center.y+point.y-g.origin.y)
            if p.kind != .lights {
                p.center.x=min(size.width,max(0,p.center.x))
                let bounds=extent(p)
                p.center.y=min(size.height-bounds.maxY,max(-bounds.minY,p.center.y))
            }
            mounts.removeValue(forKey:p.id);p.onFloor=false
        case .size:
            let r=distance(old.center,g.origin)
            p.scale=max(0.4,min(3.5,old.scale*distance(old.center,point)/max(1,r)))
            extents.removeValue(forKey:p.id)
        case .rotate:
            let delta=atan2(point.y-old.center.y,point.x-old.center.x)-atan2(g.origin.y-old.center.y,g.origin.x-old.center.x)
            p.angle=atan2(sin(old.angle+delta),cos(old.angle+delta))
            extents.removeValue(forKey:p.id)
        case .newWire, .start, .end:
            if g.action == .newWire && distance(point,g.origin)<6 {return}
            let fixed=g.action == .newWire ? g.origin : old.wirePoint(g.action == .start ? 1:0)
            let len=max(26,min(3200,distance(fixed,point)))
            let direction=atan2(point.y-fixed.y,point.x-fixed.x)
            p.angle=g.action == .start ? atan2(-sin(direction),-cos(direction)) : direction
            p.span=len
            p.center=CGPoint(x:fixed.x+cos(direction)*len/2,y:fixed.y+sin(direction)*len/2)
            wires.removeValue(forKey:p.id)
        case .sag:
            p.sag=max(-220,min(340,point.y-old.center.y));wires.removeValue(forKey:p.id)
        case .remove: return
        }
        pieces[i]=p;invalidate?()
    }
    func up(_ point:CGPoint) {
        if sleds.isDragging,let w=world {sleds.up(point,time:ProcessInfo.processInfo.systemUptime,world:w);invalidate?();return}
        if brushPoint != nil {drag(point);brushPoint=nil;invalidate?();return}
        guard let g=gesture,let i=index else{return}
        // A click on an existing mounted piece selects it without detaching it.
        if distance(g.origin,point)>0.1 {drag(point)}
        if g.action == .move && mounts[g.piece.id]==nil {snap(i)}
        if let w=world {_=sync(world:w)}
        gesture=nil;save();invalidate?()
    }
    func cancelGesture() {
        brushPoint=nil;sleds.cancel()
        guard gesture != nil else{return}
        if let i=index,let g=gesture,g.action == .move,mounts[g.piece.id]==nil {snap(i)}
        gesture=nil;save();invalidate?()
    }
    private func pile(at point:CGPoint,amount:CGFloat,world:SnowWorld) {
        // Brush the first exposed surface beneath the cursor, including a snowy window sill.
        var target:Drift?,nearest=CGFloat.greatestFiniteMagnitude
        for bank in world.banks where bank.edge.contains(point.x) && bank.edge.y>=point.y-14 {
            let distance=abs(bank.surface(point.x)-point.y)
            if distance<nearest {target=bank;nearest=distance}
        }
        guard let bank=target else{return}
        let added=bank.add(at:point.x,amount:amount,spread:4)
        if added>0.1 && puffClock<=0 {
            world.burst(CGPoint(x:point.x,y:bank.surface(point.x)),count:4,strength:0.3);puffClock=0.13
        }
    }
    func step(_ dt:TimeInterval) {
        guard let w=world else{return}
        if let p=brushPoint {
            let elapsed=min(0.1,max(0,dt));puffClock-=elapsed
            pile(at:p,amount:CGFloat(elapsed)*36,world:w);invalidate?()
        }
        if sleds.step(dt,world:w) {invalidate?()}
    }

    private static func color(_ rgb:Int, _ alpha:CGFloat=1)->CGColor {
        CGColor(red:CGFloat(rgb>>16)/255,green:CGFloat((rgb>>8)&255)/255,blue:CGFloat(rgb&255)/255,alpha:alpha)
    }
    private func strand(_ p:WorkshopPiece)->[Paint] {
        if let existing=wires[p.id] {return existing}
        // Cache each color as one compound path. A long diagonal wire costs as much
        // as a horizontal one; its empty bounding rectangle consumes no bitmap memory.
        var local=p;local.center = .zero
        let a=local.wirePoint(0), b=local.wirePoint(1)
        let wire=CGMutablePath();wire.move(to:a);wire.addQuadCurve(to:b,control:CGPoint(x:0,y:2*local.sag))
        let palette=Self.bulbs[p.palette]
        let sockets=CGMutablePath(), glints=CGMutablePath()
        let glass=palette.map {_ in CGMutablePath()}, haloes=palette.map {_ in CGMutablePath()}
        let count=min(65,max(4,Int((local.span+abs(local.sag)*0.45)/max(11,19*p.scale))))
        for i in 0..<count {
            let q=local.wirePoint((CGFloat(i)+0.5)/CGFloat(count)),r=3.1*p.scale,j=i%palette.count
            let bulb=CGRect(x:q.x-r,y:q.y+r*0.8,width:2*r,height:r*2.5)
            haloes[j].addEllipse(in:bulb.insetBy(dx:-r*0.7,dy:-r*0.6));glass[j].addEllipse(in:bulb)
            sockets.addRect(CGRect(x:q.x-r*0.43,y:q.y,width:r*0.86,height:r*1.15))
            glints.addEllipse(in:CGRect(x:q.x-0.48*r,y:q.y+1.23*r,width:0.55*r,height:0.85*r))
        }
        var paths=[Paint(path:wire.copy(strokingWithWidth:2,lineCap:.round,lineJoin:.round,miterLimit:3),color:Self.color(0x203D42))]
        for j in palette.indices {paths.append(Paint(path:haloes[j],color:Self.color(palette[j],0.16)))}
        paths.append(Paint(path:sockets,color:Self.color(0x2A4D50)))
        for j in palette.indices {paths.append(Paint(path:glass[j],color:Self.color(palette[j])))}
        paths.append(Paint(path:glints,color:Self.color(0xFFF5DF,0.95)))
        wires[p.id]=paths;return paths
    }
    func draw() {
        guard let c=NSGraphicsContext.current?.cgContext else{return}
        for p in pieces {
            if p.kind == .lights {
                c.saveGState();c.translateBy(x:p.center.x,y:p.center.y)
                for ink in strand(p) {c.setFillColor(ink.color);c.addPath(ink.path);c.fillPath()}
                c.restoreGState()
            } else {
                c.saveGState();c.translateBy(x:p.center.x,y:p.center.y);c.rotate(by:p.angle);c.scaleBy(x:p.scale,y:p.scale)
                WorkshopSymbol.forKind(p.kind).draw();c.restoreGState()
            }
        }
        sleds.draw()
        guard editing,let i=index else{return}
        let p=pieces[i]
        c.saveGState();defer{c.restoreGState()}
        if p.kind != .lights {
            c.setLineWidth(1);c.setLineDash(phase:0,lengths:[3,3]);c.setStrokeColor(Self.color(0xBACFD4,0.9))
            c.stroke(box(p));c.setLineDash(phase:0,lengths:[])
        }
        for (action,pt) in handles(p) {
            let circle=CGRect(x:pt.x-6.5,y:pt.y-6.5,width:13,height:13)
            c.setFillColor(Self.color(0x23474D));c.fillEllipse(in:circle);c.setLineWidth(1)
            c.setStrokeColor(Self.color(0xD5F3ED));c.strokeEllipse(in:circle)
            let lines:[(CGFloat,CGFloat)]
            switch action {
            case .size: lines=[(-3,3),(3,-3),(0,-3),(3,-3),(3,0)]
            case .rotate: lines=[(-3,1),(-3,-2),(0,-3),(3,-1),(3,2),(1,0),(3,2),(4,0)]
            case .sag: lines=[(-3,-1),(0,2),(3,-1)]
            case .remove: lines=[(-2.7,-2.7),(2.7,2.7)]
            default: lines=[(-2,0),(2,0)]
            }
            c.beginPath();c.addLines(between:lines.map { CGPoint(x:pt.x+$0.0,y:pt.y+$0.1) })
            if action == .remove {c.move(to:.init(x:pt.x-2.7,y:pt.y+2.7));c.addLine(to:.init(x:pt.x+2.7,y:pt.y-2.7))}
            c.setLineWidth(1.5);c.setLineCap(.round);c.setLineJoin(.round);c.strokePath()
        }
    }

    func appendMenu(to menu:NSMenu) {
        let root=NSMenuItem(title:"Decorate",action:nil,keyEquivalent:"")
        let list=NSMenu(title:"Decorate");list.autoenablesItems=false;root.submenu=list;menu.addItem(root)
        func item(_ title:String,_ action:Selector)->NSMenuItem {
            let item=NSMenuItem(title:title,action:action,keyEquivalent:"")
            item.target=self;list.addItem(item);return item
        }
        for kind in WorkshopKind.allCases {
            let add=item(kind.rawValue,#selector(place(_:)));add.representedObject=kind.rawValue
            add.state=pending==kind ? .on : .off;add.isEnabled=pieces.count < Self.limit
        }
        list.addItem(.separator())
        let edit=item("Arrange decorations",#selector(startArranging));edit.isEnabled = !pieces.isEmpty
        edit.state=editing && pending==nil && playTool==nil ? .on : .off
        if let i=index,editing {
            let p=pieces[i]
            if p.kind == .lights {
                let palettes=NSMenu(title:"Light colors")
                let colors=NSMenuItem(title:"Light colors",action:nil,keyEquivalent:"");colors.submenu=palettes;list.addItem(colors)
                for (j,title) in Self.paletteNames.enumerated() {
                    let choice=NSMenuItem(title:title,action:#selector(setPalette(_:)),keyEquivalent:"")
                    choice.target=self;choice.tag=j;choice.state=p.palette==j ? .on : .off;palettes.addItem(choice)
                }
            }
            for (title,k) in [("Make larger",1),("Make smaller",-1)] {
                let sz=item(title,#selector(resizeSelected(_:)));sz.tag=k
                sz.isEnabled=k>0 ? p.scale<3.5 : p.scale>0.4
            }
            _=item("Remove selected decoration",#selector(removeCurrent))
        }
        let done=item("Done arranging",#selector(endArranging));done.isEnabled=editing
        let playRoot=NSMenuItem(title:"Play on the snow",action:nil,keyEquivalent:"")
        let tools=NSMenu(title:"Play on the snow");tools.autoenablesItems=false;playRoot.submenu=tools;menu.addItem(playRoot)
        let pile=NSMenuItem(title:"Pile snow",action:#selector(beginPiling),keyEquivalent:"")
        pile.target=self;pile.state=playTool == .pile ? .on : .off;tools.addItem(pile)
        let sled=NSMenuItem(title:"Place a sled",action:#selector(placeSled),keyEquivalent:"")
        sled.target=self;sled.state=playTool == .sled ? .on : .off;tools.addItem(sled)
        let push=NSMenuItem(title:"Push existing sleds",action:#selector(pushSleds),keyEquivalent:"")
        push.target=self;push.isEnabled = !sleds.sleds.isEmpty;push.state=playTool == .push ? .on : .off;tools.addItem(push)
        let stop=NSMenuItem(title:"Done playing",action:#selector(endArranging),keyEquivalent:"")
        stop.target=self;stop.isEnabled=playTool != nil || brushPoint != nil;tools.addItem(stop)
    }
    @objc private func place(_ sender:NSMenuItem) {
        if let raw=sender.representedObject as? String,let kind=WorkshopKind(rawValue:raw){beginPlacement(kind)}
    }
    @objc private func startArranging(){arrange()}
    @objc private func endArranging(){finishEditing()}
    @objc private func removeCurrent(){removeSelected()}
    @objc private func setPalette(_ sender:NSMenuItem) {
        guard let i=index,pieces[i].kind == .lights,Self.bulbs.indices.contains(sender.tag) else{return}
        pieces[i].palette=sender.tag;wires.removeValue(forKey:pieces[i].id);save();invalidate?()
    }
    @objc private func resizeSelected(_ sender:NSMenuItem) {
        guard let i=index else{return}
        pieces[i].scale=max(0.4,min(3.5,pieces[i].scale*(sender.tag>0 ? 1.2:1/1.2)))
        extents.removeValue(forKey:pieces[i].id);wires.removeValue(forKey:pieces[i].id)
        if let w=world {_=sync(world:w)};save();invalidate?()
    }
}
