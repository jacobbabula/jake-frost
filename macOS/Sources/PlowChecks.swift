import AppKit

@MainActor func runMacPlowContactChecks() -> Bool {
    var passed=true
    func check(_ result:Bool,_ message:String) {
        print((result ? "PASS: " : "FAIL: ")+message);if !result {passed=false}
    }
    let size=CGSize(width:650,height:360), suite="io.jakefrost.plow-tests."+UUID().uuidString
    guard let prefs=UserDefaults(suiteName:suite) else {return false}
    defer {prefs.removePersistentDomain(forName:suite)}
    func canvas() -> SnowCanvas {
        let view=SnowCanvas(frame:CGRect(origin:.zero,size:size))
        view.world.setDesktop(size:size,edges:[SnowEdge(id:10,x:330,y:306,width:155,visible:[330...485])])
        view.world.clear();view.world.amount=0;view.world.paused=true
        view.workshop.configure(settings:prefs,displayID:35);view.workshop.sync(world:view.world)
        return view
    }
    let terrain=canvas(), road=terrain.world.banks[0]
    terrain.world.setAccumulation(140)
    for i in road.depth.indices {road.add(at:CGFloat(i)*road.spacing,amount:34,spread:0)}
    // A one-column spike and a steep wall followed by a plateau, as in the reported scene.
    road.add(at:120,amount:100,spread:0)
    for x in stride(from:CGFloat(260),through:350,by:10) {road.add(at:x,amount:95,spread:0)}
    terrain.visitors.summon(.snowplow,in:terrain.world)
    var pitch:CGFloat=0,wheelDepth:CGFloat=0,wall:CGFloat=0,bareMetal=false,gradedFrames=0
    for _ in 0..<620 {
        terrain.visitors.step(1.0/30,world:terrain.world)
        if let pose=terrain.visitors.plowPose,pose.x>30,pose.x<590 {
            pitch=max(pitch,abs(pose.angle))
            for dx:CGFloat in [-19,0,16] {wheelDepth=max(wheelDepth,road.height(pose.x+dx))}
            let lip=pose.x+35.8
            let end=min(road.depth.count-1,Int(floor(lip/road.spacing+0.5)))
            if end+2<road.depth.count {
                wall=max(wall,road.depth[end+1]-road.depth[end],road.depth[end+2]-road.depth[end+1])
            }
            gradedFrames+=1
            if !bareMetal && pose.x>285 {
                let shot=NSImage(size:size,flipped:true) { _ in
                    guard let c=NSGraphicsContext.current?.cgContext else{return false}
                    terrain.visitors.draw(in:c);return true
                }
                if let data=shot.tiffRepresentation,let pixels=NSBitmapImageRep(data:data) {
                    var orange=0
                    for yy in stride(from:0,to:pixels.pixelsHigh,by:3) {
                        for xx in stride(from:0,to:pixels.pixelsWide,by:3) {
                            if let p=pixels.colorAt(x:xx,y:yy)?.usingColorSpace(.deviceRGB),p.alphaComponent>0.8,
                               p.redComponent>0.75,p.greenComponent>0.32,p.blueComponent<0.4 {orange+=1}
                        }
                    }
                    bareMetal=orange>15
                }
            }
        }
    }
    check(gradedFrames>100 && pitch<=4 * .pi/180 && wheelDepth<=1.11 && road.depth.allSatisfy{$0<=1.11},
          "the chassis stays level and both wheels cut a continuous lane through flat snow, a spike and a tall wall")
    check(wall<15 && bareMetal,"the upright blade carries a low rounded roll and its rendered cab stays visible")

    let view=canvas(),world=view.world,workshop=view.workshop,ground=world.banks[0]
    func place(_ kind:WorkshopKind,_ x:CGFloat,_ y:CGFloat) -> WorkshopPiece {
        let here=CGPoint(x:x,y:y);workshop.beginPlacement(kind);_=workshop.down(here);workshop.up(here);return workshop.pieces.last!
    }
    func strand(_ x:CGFloat,_ y:CGFloat) -> WorkshopPiece {
        let a=CGPoint(x:x,y:y),b=CGPoint(x:x+42,y:y)
        workshop.beginPlacement(.lights);_=workshop.down(a);workshop.up(b);return workshop.pieces.last!
    }
    let tree=place(.tree,165,ground.surface(165))
    let ornament=place(.bauble,tree.center.x+5,tree.center.y)
    let present=place(.present,228,ground.surface(228))
    let mounted=place(.candle,420,306)
    let floating=place(.wreath,310,236)
    let lowWire=strand(295,size.height-15),highWire=strand(227,220)
    workshop.finishEditing()
    ground.add(at:14,amount:8,spread:1)
    let start=CGPoint(x:14,y:ground.surface(14)+1)
    _=world.down(start,at:0);world.drag(CGPoint(x:29,y:ground.surface(29)),at:0.08)
    guard let ball=world.balls.first else {return false}
    let drop=CGPoint(x:94,y:ground.surface(94)-ball.radius+6)
    world.drag(drop,at:0.6);world.up(drop,at:1)
    var gift=FrostGift();gift.kind = .snowman
    guard world.receiveSnowman(gift,at:CGPoint(x:136,y:ground.surface(136))),let figure=world.snowmen.first else{return false}
    let sleds=MacSledField(),sled=sleds.add(at:CGPoint(x:384,y:ground.surface(384)),world:world)
    let suspendedSled=sleds.add(at:CGPoint(x:400,y:306),world:world)
    view.visitors.pushWorkshop={ blade in workshop.plow(blade);sleds.plow(blade,world:world) }
    view.visitors.summon(.snowplow,in:world)
    func advance(_ n:Int) {
        for _ in 0..<n {
            world.step(1.0/30);view.visitors.step(1.0/30,world:world)
            _=sleds.step(1.0/30,world:world);workshop.step(1.0/30);workshop.sync(world:world)
        }
    }
    advance(355)
    func piece(_ old:WorkshopPiece) -> WorkshopPiece? {workshop.pieces.first(where:{$0.id==old.id})}
    check(ball.x>150 && figure.x>190 && sled.x>432,"the blade pushes loose snowballs, completed snowmen and desktop sleds")
    if let movedTree=piece(tree),let onTree=piece(ornament),let movedPresent=piece(present) {
        check(movedTree.center.x>220 && movedPresent.center.x>275 && onTree.attachment?.tree==tree.id &&
              abs((onTree.center.x-movedTree.center.x)-(ornament.center.x-tree.center.x))<0.05,
              "trees move with their ornaments and the plow pushes standalone ground decorations")
    } else {check(false,"the plow keeps swept decorations visible along the lane")}
    check((piece(lowWire)?.center.x ?? 0)>lowWire.center.x+10 && piece(highWire)?.center==highWire.center,
          "contact with the visible lower wire moves the strand while overhead lights stay put")
    advance(330)
    check([tree,ornament,present,lowWire].allSatisfy{piece($0)==nil},
          "the plow drives contacted ground decorations and attached ornaments completely off screen")
    check(piece(mounted)?.center==mounted.center && piece(floating)?.center==floating.center && abs(suspendedSled.x-400)<0.1,
          "window-mounted decorations and sleds and floating artwork outside the blade remain in place")
    return passed
}
