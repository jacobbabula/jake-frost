import AppKit

extension WorkshopKind {
    // Catalog order is part of the Windows and Mac gift-file format.
    private static let giftOrnaments: [WorkshopKind] = [
        .candle, .bauble, .goldBauble, .star, .wreath, .stocking, .candy, .present,
        .bells, .gingerbread, .holly, .santaHat, .snowGlobe, .cocoa, .boat
    ]
    var giftOrnamentID: Int? { Self.giftOrnaments.firstIndex(of: self).map { $0 + 2 } }
    init?(giftOrnamentID id: Int) {
        guard (2...16).contains(id) else { return nil }
        self = Self.giftOrnaments[id - 2]
    }
}

struct TreeAttachment: Codable {
    let tree: UUID
    let anchor: CGPoint  // Fractions of the tree height, measured from the trunk's foot.
    var magnification: CGFloat
    var angle: CGFloat

    static let ornamentScale: CGFloat = 0.4
    var isValid: Bool {
        (-0.35...0.35).contains(anchor.x) && (-1.02 ... -0.08).contains(anchor.y)
            && (0.35...4).contains(magnification) && abs(angle) <= .pi
    }
}

struct WorkshopPiece: Codable {
    struct WirePin: Codable {let bank:UInt32, fraction:CGFloat}
    var id = UUID()
    var kind: WorkshopKind
    var center: CGPoint
    var scale: CGFloat = 1
    var angle: CGFloat = 0
    var span: CGFloat = 130
    var sag: CGFloat = 22
    var palette: Int = 0
    var onFloor = false
    var attachment: TreeAttachment?
    var giftID: String?
    var giftStyle: Int?
    var treeTrim: Int?
    var treePalette: Int?
    var firstPin: WirePin?
    var lastPin: WirePin?
    var trim: Int { treeTrim ?? 7 }

    func wirePoint(_ t: CGFloat) -> CGPoint {
        let u = (t - 0.5) * span
        return CGPoint(x:center.x + cos(angle)*u,y:center.y + sin(angle)*u + 4*sag*t*(1-t))
    }
    mutating func endpoints(_ a:CGPoint,_ b:CGPoint) {
        center=CGPoint(x:(a.x+b.x)/2,y:(a.y+b.y)/2)
        angle=atan2(b.y-a.y,b.x-a.x);span=max(26,min(3200,hypot(b.x-a.x,b.y-a.y)))
    }
}

@MainActor final class MacWorkshop: NSObject {
    private struct Saved: Codable {
        let size: CGSize
        let pieces: [WorkshopPiece]
        let designedTree: UUID?
        let savedMounts: [UUID:Mount]?
    }
    private struct Mount: Codable { var id: UInt32; var fraction: CGFloat }
    private enum Action { case move, size, rotate, start, end, sag, remove, newWire }
    private struct Gesture {
        let action: Action
        let piece: WorkshopPiece
        let origin: CGPoint
        var isPlacement = false
    }
    private var settings: UserDefaults?, key = ""
    private weak var world: SnowWorld?
    private var size = CGSize.zero
    private var mounts: [UUID:Mount] = [:]
    private var extents: [UUID:CGRect] = [:]
    private struct Paint {let path:CGPath;let color:CGColor;var solid=true;var phase:Int?}
    private var wires: [UUID: [Paint]] = [:]
    private var pending: WorkshopKind?, gesture: Gesture?
    private enum PlayTool {case pile, puff, sled, push, roll, toss}
    private var scrollTarget: UUID?, scrollRotating=false, scrollCarry:CGFloat=0, lastScroll:TimeInterval=0
    private var playTool:PlayTool?, brushPoint:CGPoint?
    private var puffClock:TimeInterval=0
    private let sleds=MacSledField()
    private var plowMovedDecorations=false
    private var carriedByBlade=Set<UUID>()
    private var bladeExit:CGFloat=0
    private var clearingDirection:CGFloat=0
    private var snowGesture=false, pickingTree=false
    private var clock:TimeInterval=0
    private var falling:[(tree:WorkshopPiece,ornaments:[WorkshopPiece],age:TimeInterval)]=[]
    var twinkleEnabled=true {didSet {invalidate?()}}
    private var treeEditor:MacTreeEditor?
    private(set) var pieces: [WorkshopPiece] = []
    var onEditingChanged: (() -> Void)?
    var onPlantTree: (() -> Void)?
    private(set) var editing = false {
        // Selecting a different tool should fold a panel the user reopened while editing.
        didSet { if editing || oldValue {setEditorToolActive(editing);onEditingChanged?()} }
    }
    private(set) var selected: UUID?
    private var lastTree: UUID?
    private var index: Int? { pieces.firstIndex { $0.id == selected } }
    var isDragging: Bool { gesture != nil || brushPoint != nil || sleds.isDragging || snowGesture }
    private var animatingLights:Bool {
        twinkleEnabled && world?.paused != true && pieces.contains { $0.kind == .lights || ($0.kind == .tree && $0.trim & 6 == 6) }
    }
    var hasMotion: Bool { brushPoint != nil || sleds.hasMotion || animatingLights || !falling.isEmpty || clearingDirection != 0 }
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
        NotificationCenter.default.removeObserver(self,name:Self.twinkleChange,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(readTwinkle),name:Self.twinkleChange,object:settings)
        readTwinkle()
        pieces=[];size = .zero;selected=nil;lastTree=nil;mounts.removeAll();extents.removeAll();wires.removeAll()
        if MacSceneMemory.remembers(settings),let data=settings.data(forKey:name),data.count<=120_000,
           let saved=try? JSONDecoder().decode(Saved.self,from:data),
           saved.size.width>0,saved.size.height>0 {
            size=saved.size
            var seen=Set<UUID>()
            for p in saved.pieces.prefix(Self.limit) where seen.insert(p.id).inserted {
                let importedTree = p.kind == .tree && p.giftID.map(FrostGift.validID) == true
                let range:ClosedRange<CGFloat> = p.kind == .lights ? 0.4...5 : (importedTree ? 0.02...3.5 : 0.4...3.5)
                guard p.scale.isFinite,(p.attachment != nil || range.contains(p.scale)),
                      (26...3200).contains(p.span),(-220...340).contains(p.sag),
                      Self.bulbs.indices.contains(p.palette),(0...7).contains(p.trim),(-1...2).contains(p.treePalette ?? -1),
                      abs(p.angle)<=2 * .pi,
                      p.center.x.isFinite,p.center.y.isFinite else {continue}
                pieces.append(p)
            }
            let trees = Dictionary(uniqueKeysWithValues: pieces.filter { $0.kind == .tree }.map { ($0.id, $0) })
            lastTree = saved.designedTree.flatMap { trees[$0]?.id }
            mounts=(saved.savedMounts ?? [:]).filter { seen.contains($0.key) && $0.value.fraction.isFinite && (0...1).contains($0.value.fraction) }
            for i in pieces.indices {
                guard let a = pieces[i].attachment else { continue }
                if pieces[i].kind.giftOrnamentID != nil, a.isValid, let tree = trees[a.tree] {
                    fit(i, attachment: a, to: tree)
                } else {
                    pieces[i].attachment = nil
                    pieces[i].scale = max(0.4, min(3.5, pieces[i].scale))
                }
            }
        }
        invalidate?()
    }
    private func save() {
        guard let settings=settings,MacSceneMemory.remembers(settings),!key.isEmpty,size.width>0,size.height>0 else{return}
        if pieces.isEmpty {settings.removeObject(forKey:key);return}
        if let data=try? JSONEncoder().encode(Saved(size:size,pieces:pieces,designedTree:lastTree,savedMounts:mounts)) {settings.set(data,forKey:key)}
    }
    func rememberLayoutNow() { save() }
    func finishPlowing() {
        clearingDirection=carriedByBlade.isEmpty ? 0 : bladeExit
        if plowMovedDecorations {plowMovedDecorations=false;save()}
    }
    func plow(_ blade:PlowSweep) {
        guard let world=world else{return}
        sleds.plow(blade,world:world)
        if blade.advance != 0 {bladeExit=blade.advance<0 ? -1 : 1}
        var moved=false
        var cleared=Set<UUID>()
        for i in pieces.indices {
            let p=pieces[i]
            guard p.attachment==nil,gesture?.piece.id != p.id,gesture?.piece.attachment?.tree != p.id,
                  mounts[p.id].map({$0.id==0}) ?? true else {continue}
            let captive=carriedByBlade.contains(p.id)
            var area:CGRect
            if p.kind == .lights {
                if p.firstPin.map({$0.bank != 0}) == true || p.lastPin.map({$0.bank != 0}) == true {continue}
                // The cached strand contains the actual wire, sockets and bulbs.
                let local=blade.bounds.offsetBy(dx:-p.center.x,dy:-p.center.y)
                let a=p.wirePoint(0),b=p.wirePoint(1)
                let minX=min(a.x,b.x)-10*p.scale,maxX=max(a.x,b.x)+10*p.scale
                let minY=min(a.y,b.y)+min(0,p.sag)-8*p.scale,maxY=max(a.y,b.y)+max(0,p.sag)+16*p.scale
                area=CGRect(x:minX,y:minY,width:maxX-minX,height:maxY-minY)
                guard captive || blade.bounds.intersects(area) else {continue}
                let inks=strand(p)
                guard captive || inks.contains(where:{ ink in
                    guard ink.solid else {return false}
                    let area=ink.path.boundingBoxOfPath.intersection(local)
                    guard !area.isNull else {return false}
                    return blade.touches(area.offsetBy(dx:p.center.x,dy:p.center.y)) { q in
                        ink.path.contains(CGPoint(x:q.x-p.center.x,y:q.y-p.center.y))
                    }
                }) else {continue}
            } else {
                area=extent(p).offsetBy(dx:p.center.x,dy:p.center.y)
                guard captive || blade.touches(area,includingSnow:p.onFloor,ink:{ body(p,hits:$0) }) else {continue}
            }
            carriedByBlade.insert(p.id)
            let dx=blade.advance
            guard dx != 0 else {continue}
            pieces[i].firstPin=nil;pieces[i].lastPin=nil
            pieces[i].center.x+=dx
            if area.minX+dx>=size.width || area.maxX+dx<=0 {cleared.insert(p.id);moved=true;continue}
            if p.onFloor || mounts[p.id]?.id == 0, let floor=world.banks.first {
                let x=pieces[i].center.x
                mounts[p.id]=Mount(id:0,fraction:x/floor.edge.width)
                pieces[i].center.y=floor.surface(x)-extent(p).maxY
            }
            moveOrnaments(on:pieces[i]);moved=true
        }
        if !cleared.isEmpty { removeFamily(cleared) }
        if moved {plowMovedDecorations=true;invalidate?()}
    }
    private func removeFamily(_ parents:Set<UUID>) {
        let ids=Set(pieces.compactMap { p in
            parents.contains(p.id) || p.attachment.map{parents.contains($0.tree)} == true ? p.id : nil
        })
        pieces.removeAll {ids.contains($0.id)}
        for id in ids {mounts[id]=nil;extents[id]=nil;wires[id]=nil;carriedByBlade.remove(id)}
        if let s=selected,ids.contains(s){selected=nil;gesture=nil}
        if let t=lastTree,ids.contains(t){lastTree=nil}
        treeEditor?.refresh()
    }
    private func extent(_ p:WorkshopPiece)->CGRect {
        if let b=extents[p.id] {return b}
        let b=WorkshopSymbol.forKind(p.kind).rotatedBounds(scale:p.scale,angle:p.angle)
        extents[p.id]=b;return b
    }
    private func position(_ p:inout WorkshopPiece, at contact:CGPoint) {
        p.center=CGPoint(x:contact.x,y:contact.y-extent(p).maxY)
    }
    private func rotate(_ offset: CGPoint, by angle: CGFloat) -> CGPoint {
        CGPoint(x: offset.x*cos(angle) - offset.y*sin(angle), y: offset.x*sin(angle) + offset.y*cos(angle))
    }
    private func signed(_ angle: CGFloat) -> CGFloat { atan2(sin(angle), cos(angle)) }
    private func fit(_ i: Int, attachment: TreeAttachment, to tree: WorkshopPiece) {
        let bounds = WorkshopSymbol.forKind(.tree).bounds
        let offset = CGPoint(x: attachment.anchor.x * bounds.height,
                             y: bounds.maxY + attachment.anchor.y * bounds.height)
        let arm = rotate(offset, by: tree.angle)
        pieces[i].center = CGPoint(x: tree.center.x + arm.x * tree.scale, y: tree.center.y + arm.y * tree.scale)
        let scale = attachment.magnification * TreeAttachment.ornamentScale * tree.scale
        let angle = signed(tree.angle + attachment.angle)
        if pieces[i].scale != scale || pieces[i].angle != angle { extents.removeValue(forKey: pieces[i].id) }
        pieces[i].scale = scale; pieces[i].angle = angle; pieces[i].attachment = attachment
        pieces[i].onFloor = false
    }
    private func moveOrnaments(on tree: WorkshopPiece) {
        guard tree.kind == .tree else { return }
        for i in pieces.indices {
            if let a = pieces[i].attachment, a.tree == tree.id { fit(i, attachment: a, to: tree) }
        }
    }
    private func releaseOrnament(_ i: Int, at point: CGPoint, magnification: CGFloat) -> Bool {
        guard pieces[i].kind.giftOrnamentID != nil,
              let ti = pieces.indices.reversed().first(where: { pieces[$0].kind == .tree && body(pieces[$0], hits: point) })
        else { return false }
        let tree = pieces[ti], bounds = WorkshopSymbol.forKind(.tree).bounds
        let offset = CGPoint(x: (point.x-tree.center.x)/tree.scale, y: (point.y-tree.center.y)/tree.scale)
        let local = rotate(offset, by: -tree.angle)
        let anchor = CGPoint(x: max(-0.35, min(0.35, local.x/bounds.height)),
                             y: max(-1.02, min(-0.08, (local.y-bounds.maxY)/bounds.height)))
        let a = TreeAttachment(tree: tree.id, anchor: anchor, magnification: magnification,
                               angle: signed(pieces[i].angle-tree.angle))
        mounts.removeValue(forKey: pieces[i].id)
        fit(i, attachment: a, to: tree)
        // A piece created before the tree must draw and take clicks above its new branches.
        if i < ti { let piece = pieces.remove(at: i); pieces.append(piece) }
        lastTree = tree.id
        return true
    }
    private func detach(_ i: Int, magnification: CGFloat) {
        pieces[i].attachment = nil
        pieces[i].scale = max(0.4,min(3.5,magnification))
        extents.removeValue(forKey: pieces[i].id)
    }
    private func settle(_ i: Int, _ g: Gesture, at point: CGPoint) {
        guard g.action == .move, mounts[pieces[i].id] == nil, pieces[i].attachment == nil else { return }
        let magnification = g.piece.attachment?.magnification ?? pieces[i].scale
        if releaseOrnament(i, at: g.isPlacement ? point : pieces[i].center, magnification: magnification) { return }
        if g.piece.attachment != nil { detach(i, magnification: magnification) }
        snap(i)
        moveOrnaments(on: pieces[i])
    }

    func treeGiftTemplate() -> FrostGift? {
        let chosen = index.map { pieces[$0] }
        let wanted = chosen?.kind == .tree ? chosen?.id : (chosen?.attachment?.tree ?? lastTree)
        guard let tree = pieces.first(where: { $0.kind == .tree && $0.id == wanted }) ?? pieces.last(where: { $0.kind == .tree })
        else { return nil }

        // Four decimal places keep a full desktop's ornaments inside the 8 KiB dress field.
        let locale = Locale(identifier: "en_US_POSIX")
        func number(_ value: CGFloat) -> String { String(format: "%.4f", locale: locale, Double(value)) }
        var ornaments: [String] = [], scales: [String] = [], angles = [number(tree.angle * 180 / .pi)]
        for piece in pieces {
            guard let a = piece.attachment, a.tree == tree.id, let kind = piece.kind.giftOrnamentID else { continue }
            if a.magnification != 1 { scales.append(contentsOf: [String(ornaments.count), number(a.magnification)]) }
            angles.append(number(a.angle * 180 / .pi))
            ornaments.append("\(kind),\(number(a.anchor.x)),\(number(a.anchor.y))")
        }
        if !scales.isEmpty { ornaments.append("scale," + scales.joined(separator: ",")) }
        ornaments.append("angles," + angles.joined(separator: ","))
        if tree.treePalette != nil || tree.trim != 7 {ornaments.append("trim,\(tree.trim),\(tree.treePalette ?? -1)")}
        var result = FrostGift()
        result.kind = .tree
        result.style = tree.giftStyle ?? 0
        result.size = Double(max(3, min(160, WorkshopSymbol.forKind(.tree).bounds.height * tree.scale)))
        result.dress = ornaments.joined(separator: ";")
        return result
    }
    func containsReceivedGift(_ id: String) -> Bool { pieces.contains { $0.giftID == id } }
    func receiveTree(_ parcel: GiftTrain.Parcel, at foot: CGPoint) -> Bool {
        let gift = parcel.gift
        guard gift.kind == .tree else { return false }
        if containsReceivedGift(gift.id) { return true }
        guard size.width > 1, size.height > 1, pieces.count + 1 + parcel.ornaments.count <= Self.limit else { return false }
        let symbol = WorkshopSymbol.forKind(.tree)
        var tree = WorkshopPiece(kind:.tree,center:foot)
        tree.giftID = gift.id; tree.giftStyle = gift.style
        tree.treeTrim = parcel.trim;tree.treePalette = parcel.palette
        tree.scale = CGFloat(gift.size)/symbol.bounds.height
        tree.angle = signed(parcel.tilt * .pi/180)
        position(&tree,at:foot);pieces.append(tree)
        snap(pieces.count-1)
        tree = pieces[pieces.count-1]
        for ornament in parcel.ornaments {
            guard let kind = WorkshopKind(giftOrnamentID:ornament.kind) else { continue }
            let a = TreeAttachment(tree:tree.id,anchor:CGPoint(x:ornament.x,y:ornament.y),
                                   magnification:ornament.scale,angle:signed(ornament.angle * .pi/180))
            pieces.append(WorkshopPiece(kind:kind,center:tree.center))
            fit(pieces.count-1,attachment:a,to:tree)
        }
        save();invalidate?()
        return true
    }
    @discardableResult func sync(world:SnowWorld)->Bool {
        self.world=world
        let next=world.size
        guard next.width>0,next.height>0 else{return false}
        var changed=false
        var movedTrees: [UUID:WorkshopPiece] = [:]
        if size != next {
            if size.width>0,size.height>0 {
                for i in pieces.indices {
                    pieces[i].center.x *= next.width/size.width
                    pieces[i].center.y *= next.height/size.height
                }
            }
            size=next;changed=true
            for p in pieces where p.kind == .tree { movedTrees[p.id] = p }
            for i in pieces.indices where pieces[i].onFloor {
                mounts[pieces[i].id]=Mount(id:0,fraction:pieces[i].center.x/size.width)
            }
        }
        if !pieces.isEmpty {
            for i in pieces.indices {
                let p=pieces[i]
                if p.kind == .lights,gesture?.piece.id != p.id,(p.firstPin != nil || p.lastPin != nil) {
                    let a=p.wirePoint(0),b=p.wirePoint(1)
                    let left=resolve(pin:p.firstPin,world:world) ?? a,right=resolve(pin:p.lastPin,world:world) ?? b
                    if distance(a,left)>0.08 || distance(b,right)>0.08 {
                        pieces[i].endpoints(left,right);wires[p.id]=nil;changed=true
                    }
                    continue
                }
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
                    if p.kind == .tree { movedTrees[p.id] = pieces[i] }
                }
            }
        }
        if changed {
            if !movedTrees.isEmpty {
                for i in pieces.indices {
                    if let a = pieces[i].attachment, let tree = movedTrees[a.tree] { fit(i, attachment: a, to: tree) }
                }
            }
            invalidate?()
        }
        return changed
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
    private func resolve(pin:WorkshopPiece.WirePin?,world:SnowWorld)->CGPoint? {
        guard let pin=pin,pin.fraction.isFinite,(0...1).contains(pin.fraction),
              let bank=world.banks.first(where:{$0.edge.id==pin.bank}) else{return nil}
        let x=bank.edge.x+pin.fraction*bank.edge.width
        guard bank.edge.contains(x) else{return nil}
        return CGPoint(x:x,y:bank.surface(x))
    }
    private func wireSupport(near p:CGPoint)->Drift? {
        world?.banks.filter{$0.edge.contains(p.x) && abs($0.surface(p.x)-p.y)<=10}
            .min{abs($0.surface(p.x)-p.y)<abs($1.surface(p.x)-p.y)}
    }
    private func wirePin(at p:CGPoint)->WorkshopPiece.WirePin? {
        guard let bank=wireSupport(near:p) else{return nil}
        return WorkshopPiece.WirePin(bank:bank.edge.id,fraction:(p.x-bank.edge.x)/bank.edge.width)
    }
    func beginPlacement(_ kind:WorkshopKind) {
        guard pieces.count < Self.limit else{return}
        if kind == .tree {onPlantTree?()}
        resetTools();pending=kind;editing=true;invalidate?()
    }
    private func resetTools() {cancelGesture();playTool=nil;pending=nil;selected=nil;pickingTree=false}
    func arrange() {resetTools();editing=true;invalidate?()}
    func finishEditing() {resetTools();editing=false;invalidate?()}
    @objc func beginPiling() {resetTools();playTool = .pile;editing=true;invalidate?()}
    @objc func beginPuffing() {resetTools();playTool = .puff;editing=true;invalidate?()}
    @objc func beginRolling() {resetTools();playTool = .roll;editing=true;invalidate?()}
    @objc func beginThrowing() {resetTools();playTool = .toss;editing=true;invalidate?()}
    @objc func placeSled() {resetTools();playTool = .sled;editing=true;invalidate?()}
    @objc private func pushSleds() {resetTools();playTool = .push;editing=true;invalidate?()}
    func clear() {
        pending=nil;gesture=nil;editing=false;selected=nil;lastTree=nil;playTool=nil;brushPoint=nil;sleds.clear()
        pieces.removeAll();mounts.removeAll();extents.removeAll();wires.removeAll()
        falling.removeAll();carriedByBlade.removeAll();clearingDirection=0;pickingTree=false;snowGesture=false;treeEditor?.refresh()
        save();invalidate?()
    }
    private func removeSelected() {
        guard let i=index else{return}
        let removed = pieces.remove(at:i), id = removed.id
        if removed.kind == .tree {
            for j in pieces.indices {
                if let a = pieces[j].attachment, a.tree == id { detach(j, magnification: a.magnification) }
            }
            if lastTree == id { lastTree = nil }
        }
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
            let padding=max(12,13*p.scale)
            let area=CGRect(x:min(a.x,a.x+dx)-padding,y:min(a.y,a.y+dy)+min(0,p.sag)-padding,
                            width:abs(dx)+padding*2,height:abs(dy)+abs(p.sag)+padding*2)
            guard area.contains(q) else{return false}
            let local=CGPoint(x:q.x-p.center.x,y:q.y-p.center.y)
            if strand(p).contains(where:{$0.solid && $0.path.contains(local)}) {return true}
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
        if pickingTree {return pieces.contains{$0.kind == .tree && body($0,hits:point)}}
        if playTool == .push {return sleds.captures(point)}
        return editing && (playTool != nil || pending != nil || action(at:point) != nil)
    }
    @discardableResult func down(_ point:CGPoint)->Bool {
        if pickingTree {
            guard let p=pieces.last(where:{$0.kind == .tree && body($0,hits:point)}) else{return false}
            finishEditing();selectTree(p.id);openTreeEditor();return true
        }
        if let tool=playTool,let w=world {
            switch tool {
            case .roll: snowGesture=w.rollDown(point,at:ProcessInfo.processInfo.systemUptime)
            case .toss: snowGesture=w.throwDown(point,at:ProcessInfo.processInfo.systemUptime)
            case .sled: _=sleds.add(at:point,world:w);playTool = .push
            case .push: return sleds.down(point,time:ProcessInfo.processInfo.systemUptime)
            case .pile: brushPoint=point;puffClock=0;pile(at:point,amount:3.4,world:w)
            case .puff: brushPoint=point;w.puff(at:point,brush:true)
            }
            invalidate?();return true
        }
        guard editing else{return false}
        if let kind=pending {
            guard pieces.count<Self.limit else{pending=nil;return false}
            pending=nil
            var p=WorkshopPiece(kind:kind,center:point)
            if kind == .lights {p.scale=defaultBulbSize;p.palette=defaultWirePalette}
            if kind == .tree {p.treeTrim=defaultTrim;p.treePalette=defaultTreePalette}
            if kind != .lights {position(&p,at:point)}
            selected=p.id;pieces.append(p)
            if kind == .tree { lastTree = p.id }
            gesture=Gesture(action:kind == .lights ? .newWire : .move,piece:p,origin:point,isPlacement:true)
        } else if let (i,action)=action(at:point) {
            selected=pieces[i].id
            if pieces[i].kind == .tree { lastTree = selected }
            else if let a = pieces[i].attachment { lastTree = a.tree }
            if action == .remove {removeSelected();return true}
            gesture=Gesture(action:action,piece:pieces[i],origin:point)
        } else {return false}
        invalidate?();return true
    }
    func drag(_ point:CGPoint) {
        if snowGesture {world?.drag(point,at:ProcessInfo.processInfo.systemUptime);invalidate?();return}
        if sleds.isDragging {sleds.drag(point,time:ProcessInfo.processInfo.systemUptime);invalidate?();return}
        if let previous=brushPoint,let w=world {
            let distance=hypot(point.x-previous.x,point.y-previous.y)
            let puffing = playTool == .puff
            let count=min(puffing ? 12 : 40,Int(distance/(puffing ? 14 : 5)))
            if puffing && count==0 {return}
            if count>0 {
                for j in 1...count {
                    let f=CGFloat(j)/CGFloat(count)
                    let stamp=CGPoint(x:previous.x+(point.x-previous.x)*f,y:previous.y+(point.y-previous.y)*f)
                    if puffing {w.puff(at:stamp,brush:true)} else {pile(at:stamp,amount:0.8,world:w)}
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
            p.attachment = nil
            p.center=CGPoint(x:old.center.x+point.x-g.origin.x,y:old.center.y+point.y-g.origin.y)
            if p.kind != .lights {
                p.center.x=min(size.width,max(0,p.center.x))
                let bounds=extent(p)
                p.center.y=min(size.height-bounds.maxY,max(-bounds.minY,p.center.y))
            }
            mounts.removeValue(forKey:p.id);p.onFloor=false
        case .size:
            let r=distance(old.center,g.origin)
            let factor = distance(old.center,point)/max(1,r)
            if let a = old.attachment { p.attachment?.magnification = max(0.4, min(3.5, a.magnification*factor)) }
            else { p.scale=max(0.4,min(3.5,old.scale*factor)) }
            extents.removeValue(forKey:p.id)
        case .rotate:
            let delta=atan2(point.y-old.center.y,point.x-old.center.x)-atan2(g.origin.y-old.center.y,g.origin.x-old.center.x)
            p.angle=atan2(sin(old.angle+delta),cos(old.angle+delta))
            if let a = old.attachment { p.attachment?.angle = signed(a.angle + delta) }
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
        pieces[i]=p
        if let a = p.attachment, let tree = pieces.first(where: { $0.id == a.tree }) { fit(i, attachment: a, to: tree) }
        moveOrnaments(on: p);invalidate?()
    }
    func up(_ point:CGPoint) {
        if snowGesture {world?.up(point,at:ProcessInfo.processInfo.systemUptime);snowGesture=false;invalidate?();return}
        if sleds.isDragging,let w=world {sleds.up(point,time:ProcessInfo.processInfo.systemUptime,world:w);invalidate?();return}
        if brushPoint != nil {drag(point);brushPoint=nil;invalidate?();return}
        guard let g=gesture,let i=index else{return}
        // A click on an existing mounted piece selects it without detaching it.
        let moved = distance(g.origin,point)>0.1
        if moved { drag(point) }
        if pieces[i].kind == .lights {
            if g.action == .newWire && !moved,let bank=wireSupport(near:point),bank.edge.id != 0,
               let visible=bank.edge.visible.first(where:{$0.contains(point.x)}),visible.upperBound-visible.lowerBound>30 {
                let left=visible.lowerBound+3,right=visible.upperBound-3
                pieces[i].endpoints(CGPoint(x:left,y:bank.surface(left)),CGPoint(x:right,y:bank.surface(right)))
                wires[pieces[i].id]=nil
            }
            if g.action == .newWire || (moved && (g.action == .start || g.action == .move)){pieces[i].firstPin=wirePin(at:pieces[i].wirePoint(0))}
            if g.action == .newWire || (moved && (g.action == .end || g.action == .move)){pieces[i].lastPin=wirePin(at:pieces[i].wirePoint(1))}
        }
        if g.isPlacement || moved { settle(i, g, at: point) }
        if let w=world {_=sync(world:w)}
        gesture=nil;save();invalidate?()
    }
    func cancelGesture() {
        if snowGesture {world?.cancel();snowGesture=false}
        brushPoint=nil;sleds.cancel()
        guard gesture != nil else{return}
        if let i=index,let g=gesture, g.isPlacement || distance(pieces[i].center, g.piece.center)>0.1 {
            let p = pieces[i]
            let point = g.isPlacement ? CGPoint(x: p.center.x, y: p.center.y + extent(p).maxY) : p.center
            settle(i, g, at: point)
        }
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
        if animatingLights {clock+=max(0,min(dt,0.12));invalidate?()}
        if !falling.isEmpty {
            for i in falling.indices {falling[i].age+=max(0,min(dt,0.12))}
            falling.removeAll{$0.age>=0.86};invalidate?()
        }
        if clearingDirection != 0 {
            let distance=clearingDirection*max(0,min(CGFloat(dt),0.12))*160
            var gone=Set<UUID>()
            for i in pieces.indices where carriedByBlade.contains(pieces[i].id) {
                let p=pieces[i]
                pieces[i].center.x+=distance;mounts[p.id]=nil;pieces[i].onFloor=false
                moveOrnaments(on:pieces[i])
                let radius=p.kind == .lights ? p.span/2+20*p.scale : max(extent(p).width,extent(p).height)
                if pieces[i].center.x+radius<0 || pieces[i].center.x-radius>size.width {gone.insert(p.id)}
            }
            if !gone.isEmpty {removeFamily(gone);save()}
            if carriedByBlade.isEmpty {clearingDirection=0}
            invalidate?()
        }
        if let p=brushPoint, playTool == .pile {
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
        for j in palette.indices {paths.append(Paint(path:haloes[j],color:Self.color(palette[j],0.30),solid:false,phase:j))}
        paths.append(Paint(path:sockets,color:Self.color(0x2A4D50)))
        for j in palette.indices {paths.append(Paint(path:glass[j],color:Self.color(palette[j]),phase:j))}
        paths.append(Paint(path:glints,color:Self.color(0xFFF5DF,0.95)))
        wires[p.id]=paths;return paths
    }
    func draw() {
        guard let c=NSGraphicsContext.current?.cgContext else{return}
        for p in pieces {
            if p.kind == .lights {
                c.saveGState();c.translateBy(x:p.center.x,y:p.center.y)
                for ink in strand(p) {
                    c.setAlpha(twinkleEnabled && ink.phase != nil ? MacTreeLights.brightness(clock,ink.phase!) : 1)
                    c.setFillColor(ink.color);c.addPath(ink.path);c.fillPath()
                }
                c.restoreGState()
            } else {
                c.saveGState();c.translateBy(x:p.center.x,y:p.center.y);c.rotate(by:p.angle);c.scaleBy(x:p.scale,y:p.scale)
                drawSymbol(p,in:c);c.restoreGState()
            }
        }
        for f in falling {
            let trunk=f.tree, bounds=WorkshopSymbol.forKind(.tree).bounds
            let pivot=rotate(CGPoint(x:0,y:bounds.maxY*trunk.scale),by:trunk.angle)
            let u=CGFloat(f.age/0.86), ax=trunk.center.x+pivot.x, ay=trunk.center.y+pivot.y
            c.saveGState();c.translateBy(x:ax,y:ay);c.rotate(by:u*u*1.40);c.translateBy(x:-ax,y:-ay)
            c.setAlpha(min(1,(1-u)*4))
            for p in [trunk]+f.ornaments {
                c.saveGState();c.translateBy(x:p.center.x,y:p.center.y);c.rotate(by:p.angle);c.scaleBy(x:p.scale,y:p.scale)
                drawSymbol(p,in:c);c.restoreGState()
            }
            c.restoreGState()
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
        let editor=NSMenuItem(title:"Decorate a tree…",action:#selector(openTreeEditor),keyEquivalent:"")
        editor.target=self;menu.addItem(editor)
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
        let twinkle=item("Twinkle string and tree lights",#selector(toggleTwinkle));twinkle.state=twinkleEnabled ? .on : .off
        addWireOptions(to:list,selectedIndex:nil)
        let edit=item("Arrange decorations",#selector(startArranging));edit.isEnabled = !pieces.isEmpty
        edit.state=editing && pending==nil && playTool==nil ? .on : .off
        if let i=index,editing {
            let p=pieces[i]
            if p.kind == .lights {
                addWireOptions(to:list,selectedIndex:i)
                let palettes=NSMenu(title:"Light colors")
                let colors=NSMenuItem(title:"Light colors",action:nil,keyEquivalent:"");colors.submenu=palettes;list.addItem(colors)
                for (j,title) in Self.paletteNames.enumerated() {
                    let choice=NSMenuItem(title:title,action:#selector(setPalette(_:)),keyEquivalent:"")
                    choice.target=self;choice.tag=j;choice.state=p.palette==j ? .on : .off;palettes.addItem(choice)
                }
            }
            for (title,k) in [("Make larger",1),("Make smaller",-1)] {
                let sz=item(title,#selector(resizeSelected(_:)));sz.tag=k
                let adjustable = p.attachment?.magnification ?? p.scale
                sz.isEnabled=k>0 ? adjustable<(p.kind == .lights ? 5 : 3.5) : adjustable>(p.kind == .lights ? 0.5 : 0.4)
            }
            if p.attachment != nil { _=item("Detach from tree",#selector(detachSelected)) }
            _=item("Remove selected decoration",#selector(removeCurrent))
        }
        let done=item("Done arranging",#selector(endArranging));done.isEnabled=editing
        let playRoot=NSMenuItem(title:"Play on the snow",action:nil,keyEquivalent:"")
        let tools=NSMenu(title:"Play on the snow");tools.autoenablesItems=false;playRoot.submenu=tools;menu.addItem(playRoot)
        for (name,action,active) in [("Roll snowball",#selector(beginRolling),playTool == .roll),
                                     ("Throw snowball",#selector(beginThrowing),playTool == .toss)] {
            let tool=NSMenuItem(title:name,action:action,keyEquivalent:"");tool.target=self;tool.state=active ? .on : .off;tools.addItem(tool)
        }
        let pile=NSMenuItem(title:"Pile snow",action:#selector(beginPiling),keyEquivalent:"")
        pile.target=self;pile.state=playTool == .pile ? .on : .off;tools.addItem(pile)
        let puff=NSMenuItem(title:"Puff snow",action:#selector(beginPuffing),keyEquivalent:"")
        puff.target=self;puff.state=playTool == .puff ? .on : .off;tools.addItem(puff)
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
    @objc private func detachSelected() {
        guard let i=index, let a=pieces[i].attachment else { return }
        detach(i, magnification: a.magnification);save();invalidate?()
    }
    @objc private func setPalette(_ sender:NSMenuItem) {
        guard let i=index,pieces[i].kind == .lights,Self.bulbs.indices.contains(sender.tag) else{return}
        pieces[i].palette=sender.tag;wires.removeValue(forKey:pieces[i].id);save();invalidate?()
    }
    @objc private func resizeSelected(_ sender:NSMenuItem) {
        guard let i=index else{return}
        let factor: CGFloat = sender.tag>0 ? 1.2 : 1/1.2
        resize(i,by:factor)
        finishAdjustment(i)
    }
    private func resize(_ i:Int,by factor:CGFloat) {
        if var a = pieces[i].attachment, let tree = pieces.first(where: { $0.id == a.tree }) {
            a.magnification = max(0.4,min(3.5,a.magnification*factor))
            fit(i, attachment: a, to: tree)
        } else {
            let wire=pieces[i].kind == .lights
            pieces[i].scale=max(wire ? 0.5 : 0.4,min(wire ? 5 : 3.5,pieces[i].scale*factor))
            moveOrnaments(on: pieces[i])
        }
    }
    private func finishAdjustment(_ i:Int) {
        extents.removeValue(forKey:pieces[i].id);wires.removeValue(forKey:pieces[i].id)
        if let w=world {_=sync(world:w)};save();invalidate?()
    }
    @discardableResult func scroll(at point:CGPoint,delta:CGFloat,precise:Bool,rotating:Bool)->Bool {
        guard editing, pending==nil, playTool==nil, !isDragging,delta.isFinite,delta != 0,
              let (i,_) = action(at:point) else {return false}
        let id=pieces[i].id,now=ProcessInfo.processInfo.systemUptime
        if scrollTarget != id || scrollRotating != rotating || now-lastScroll>0.35 {scrollCarry=0}
        scrollTarget=id;scrollRotating=rotating;lastScroll=now
        var steps:CGFloat = delta>0 ? 1 : -1
        if precise {
            scrollCarry += delta/22
            steps=scrollCarry.rounded(.towardZero);scrollCarry-=steps
            if steps==0 {return true}
            steps=max(-5,min(5,steps))
        }
        selected=id
        if rotating {
            let radians=steps * .pi/12
            if var a=pieces[i].attachment,let tree=pieces.first(where:{$0.id==a.tree}) {
                a.angle=signed(a.angle+radians);fit(i,attachment:a,to:tree)
            } else {
                pieces[i].angle=signed(pieces[i].angle+radians);moveOrnaments(on:pieces[i])
            }
        } else {resize(i,by:pow(1.16,steps))}
        finishAdjustment(i);return true
    }
}

extension MacWorkshop {
    private static let twinkleChange=Notification.Name("JakeFrostLightTwinkleChanged")
    @objc private func readTwinkle() {twinkleEnabled=settings?.object(forKey:"twinkleLights") as? Bool ?? true}
    @objc func toggleTwinkle() {
        settings?.set(!twinkleEnabled,forKey:"twinkleLights")
        if let settings=settings {NotificationCenter.default.post(name:Self.twinkleChange,object:settings)}
        else {twinkleEnabled.toggle()}
        treeEditor?.refresh()
    }
    private var defaultBulbSize:CGFloat {
        let value=settings?.object(forKey:"newLightPercent") as? Int ?? 100
        return CGFloat(min(500,max(50,value)))/100
    }
    private var defaultWirePalette:Int {min(Self.bulbs.count-1,max(0,settings?.integer(forKey:"newLightPalette") ?? 0))}
    private var defaultTrim:Int? {(settings?.object(forKey:"newTreeTrim") as? Int).flatMap{(0...7).contains($0) ? $0:nil}}
    private var defaultTreePalette:Int? {(settings?.object(forKey:"newTreePalette") as? Int).flatMap{(0...2).contains($0) ? $0:nil}}
    private func addWireOptions(to list:NSMenu,selectedIndex:Int?) {
        let defaultSize=selectedIndex.map{pieces[$0].scale} ?? defaultBulbSize
        let label=selectedIndex==nil ? "New string bulb size" : "Bulb size"
        let row=NSMenuItem(title:label,action:nil,keyEquivalent:"")
        let menu=NSMenu(title:label);row.submenu=menu;list.addItem(row)
        for percent in [50,75,100,125,150,200,300,400,500] {
            let option=NSMenuItem(title:"\(percent)%",action:#selector(chooseBulbs(_:)),keyEquivalent:"")
            option.target=self;option.tag=percent;option.representedObject=selectedIndex.map{pieces[$0].id.uuidString}
            option.state=abs(CGFloat(percent)-100*defaultSize)<0.01 ? .on:.off;menu.addItem(option)
        }
        if selectedIndex==nil {
            let colors=NSMenuItem(title:"New string colors",action:nil,keyEquivalent:"")
            let choices=NSMenu(title:colors.title);colors.submenu=choices;list.addItem(colors)
            for (i,name) in Self.paletteNames.enumerated() {
                let option=NSMenuItem(title:name,action:#selector(chooseWirePalette(_:)),keyEquivalent:"")
                option.target=self;option.tag=i;option.state=i==defaultWirePalette ? .on:.off;choices.addItem(option)
            }
        }
    }
    @objc private func chooseBulbs(_ sender:NSMenuItem) {
        if let target=sender.representedObject as? String {
            guard let i=pieces.firstIndex(where:{$0.kind == .lights && $0.id.uuidString==target}) else{return}
            pieces[i].scale=CGFloat(sender.tag)/100;finishAdjustment(i)
        } else {settings?.set(sender.tag,forKey:"newLightPercent")}
    }
    @objc private func chooseWirePalette(_ sender:NSMenuItem){settings?.set(sender.tag,forKey:"newLightPalette")}

    var trees:[WorkshopPiece] {pieces.filter{$0.kind == .tree}}
    var designedTree:WorkshopPiece? {pieces.first{$0.kind == .tree && $0.id==lastTree}}
    func nearestTreeForYeti(to x:CGFloat)->WorkshopPiece? {
        pieces.filter{$0.kind == .tree && $0.onFloor && gesture?.piece.id != $0.id && !carriedByBlade.contains($0.id)}
            .min{abs($0.center.x-x)<abs($1.center.x-x)}
    }
    @discardableResult func chopTree(_ id:UUID)->Bool {
        guard let tree=pieces.first(where:{$0.id==id && $0.kind == .tree && $0.onFloor && gesture?.piece.id != id}) else{return false}
        let ornaments=pieces.filter{$0.attachment?.tree==id}
        falling.append((tree,ornaments,0));removeFamily([id]);save();invalidate?();return true
    }
    @objc func openTreeEditor() {
        finishEditing()
        if designedTree==nil {
            if let tree=trees.last {selectTree(tree.id)} else {plantForEditor()}
        }
        if treeEditor==nil {treeEditor=MacTreeEditor(workshop:self)}
        treeEditor?.show()
    }
    func setEditorToolActive(_ active:Bool){treeEditor?.setPicking(active)}
    func selectTree(_ id:UUID) {
        guard pieces.contains(where:{$0.id==id && $0.kind == .tree}) else{return}
        lastTree=id;save();treeEditor?.refresh();invalidate?()
    }
    func pickTreeOnDesktop() {
        guard !trees.isEmpty else{return}
        resetTools();pickingTree=true;editing=true;treeEditor?.setPicking(true);invalidate?()
    }
    func plantForEditor() {
        guard pieces.count<Self.limit,let floor=world?.banks.first,size.width>0 else{return}
        onPlantTree?()
        let options=[0.67,0.29,0.49,0.83,0.15].map{CGFloat($0)*size.width}
        let trunks=trees
        let x=options.max { a,b in
            (trunks.map{abs($0.center.x-a)}.min() ?? 0)<(trunks.map{abs($0.center.x-b)}.min() ?? 0)
        } ?? size.width/2
        let foot=CGPoint(x:x,y:floor.surface(x))
        var tree=WorkshopPiece(kind:.tree,center:foot);tree.treeTrim=defaultTrim;tree.treePalette=defaultTreePalette
        position(&tree,at:foot);tree.onFloor=true;pieces.append(tree)
        mounts[tree.id]=Mount(id:0,fraction:x/size.width);selectTree(tree.id)
    }
    func setTreeDesign(trim:Int,color:Int) {
        guard (0...7).contains(trim),(0...2).contains(color),
              let i=pieces.firstIndex(where:{$0.id==lastTree && $0.kind == .tree}) else{return}
        pieces[i].treeTrim=trim;pieces[i].treePalette=color;save();treeEditor?.refresh();invalidate?()
    }
    func rememberTreeDefaults() {
        guard let p=designedTree else{return}
        settings?.set(p.trim,forKey:"newTreeTrim");settings?.set(p.treePalette ?? 1,forKey:"newTreePalette")
    }
    @discardableResult func hang(_ kind:WorkshopKind)->Bool {
        guard pieces.count<Self.limit,kind.giftOrnamentID != nil,let tree=designedTree else{return false}
        let n=pieces.filter{$0.attachment?.tree==tree.id}.count
        let row=0.26+0.55*CGFloat((Double(n)*0.381966).truncatingRemainder(dividingBy:1))
        let x=(0.055+0.22*row)*(n.isMultiple(of:2) ? 1 : -1)
        let a=TreeAttachment(tree:tree.id,anchor:CGPoint(x:x,y:row-1),magnification:0.72,angle:0)
        pieces.append(WorkshopPiece(kind:kind,center:tree.center));fit(pieces.count-1,attachment:a,to:tree)
        save();treeEditor?.refresh();invalidate?();return true
    }
    func unhang() {
        guard let id=lastTree,let i=pieces.lastIndex(where:{$0.attachment?.tree==id}) else{return}
        removeFamily([pieces[i].id]);save();invalidate?()
    }
    private func drawSymbol(_ piece:WorkshopPiece,in c:CGContext) {
        WorkshopSymbol.forKind(piece.kind).draw()
        if piece.kind == .tree {
            MacTreeLights.draw(trim:piece.trim,palette:piece.treePalette ?? 1,time:twinkleEnabled ? clock:nil,in:c)
        }
    }
    func drawPreview(in rect:CGRect) {
        guard let tree=designedTree,let c=NSGraphicsContext.current?.cgContext else{return}
        let h=WorkshopSymbol.forKind(.tree).bounds.height, zoom=(rect.height-12)/(h*tree.scale)
        c.saveGState();defer{c.restoreGState()}
        c.translateBy(x:rect.midX,y:rect.midY);c.scaleBy(x:zoom,y:zoom);c.translateBy(x:-tree.center.x,y:-tree.center.y)
        for p in pieces where p.id==tree.id || p.attachment?.tree==tree.id {
            c.saveGState();c.translateBy(x:p.center.x,y:p.center.y);c.rotate(by:p.angle);c.scaleBy(x:p.scale,y:p.scale)
            drawSymbol(p,in:c);c.restoreGState()
        }
    }
}
