import AppKit

@MainActor func runSceneTests()->Bool {
    var failures=0
    func check(_ value:Bool,_ label:String){
        print((value ? "PASS: " : "FAIL: ")+label)
        if !value {failures+=1}
    }
    let screen=CGRect(x:-250,y:30,width:640,height:360)
    let front=WindowFrame(id:2,rect:CGRect(x:-130,y:50,width:80,height:150))
    let back=WindowFrame(id:3,rect:CGRect(x:-230,y:135,width:310,height:200))
    let list=DesktopEdges.visible([front,back],in:screen)
    guard let top=list.first(where:{$0.id==3}) else{return false}
    check(top.visible.count==2 && !top.contains(150) && top.contains(45) && top.contains(265),"occluding window splits an exposed top edge")
    check(top.y==105 && top.x==20,"secondary-screen coordinates convert correctly")
    let view=SnowCanvas(frame:CGRect(origin:.zero,size:screen.size))
    let s=view.world
    s.setDesktop(size:screen.size,edges:list);s.clear();s.amount=0
    guard let floor=s.banks.first,let ledge=s.banks.first(where:{$0.edge.id==3}) else{return false}
    check(!s.hit(CGPoint(x:300,y:50)),"empty desktop passes mouse input through")
    for x in stride(from:CGFloat(45),through:220,by:8) {floor.add(at:x,amount:7,spread:3)}
    ledge.add(at:45,amount:10)
    check(s.hit(CGPoint(x:45,y:ledge.surface(45)+1)) && !s.hit(CGPoint(x:150,y:top.y)),"only exposed snowy pixels can be grabbed")
    let tap=CGPoint(x:70,y:floor.surface(70)+1),depth=floor.height(70)
    _=s.down(tap,at:0);s.up(tap,at:0.2)
    check(s.balls.isEmpty && s.particles.contains(where:{$0.powder}) && floor.height(70)<depth,"tap dislodges powder from a drift")
    let start=CGPoint(x:90,y:floor.surface(90)+1)
    _=s.down(start,at:1);s.drag(CGPoint(x:125,y:floor.surface(125)),at:1.05)
    check((s.balls.first?.radius ?? 0)>7,"dragging through snow grows a ball")
    s.drag(CGPoint(x:160,y:230),at:1.08);s.up(CGPoint(x:199,y:215),at:1.10)
    check(s.balls.count==1 && s.balls[0].thrown,"a mouse flick supplies throw velocity")
    var splat=false
    for _ in 0..<500 {s.step(0.016);if s.balls.isEmpty {splat=s.particles.contains(where:{$0.powder});break}}
    check(splat,"snowball disperses on impact")
    var moved=top;moved.x+=25;moved.y+=12;moved.visible=[50...260]
    let heldDepth=ledge.height(45);s.setDesktop(size:screen.size,edges:[moved])
    check(abs(ledge.height(70)-heldDepth)<0.01 && ledge.edge.y==117,"snow follows a moved window")
    var correctContacts=true
    for x in [CGFloat(-1),45,70,149,260,261,639] {
        for y in stride(from:CGFloat(-4),through:screen.height+2,by:3.25) {
            for distance in [CGFloat(1.1),8,72] {
                let expected=s.banks.filter { bank in
                    let surface=bank.surface(x)
                    return bank.edge.contains(x) && y<=surface+1.2 && y+distance>=surface
                }.min { $0.surface(x)<$1.surface(x) }
                if s.intercept(x:x,previous:y,next:y+distance) !== expected {correctContacts=false}
            }
        }
    }
    check(correctContacts,"indexed flake and snowball contacts match a full scan across row and window edges")
    let rendered=NSImage(size:screen.size,flipped:true) { _ in view.draw(view.bounds);return true }
    var painted=false
    if let tiff=rendered.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff) {
        for y in stride(from:0,to:rep.pixelsHigh,by:2) {
            if (rep.colorAt(x:70,y:y)?.alphaComponent ?? 0)>0.85 {painted=true;break}
        }
    }
    check(painted,"AppKit raster contains visible snow")
    s.clear();check(s.balls.isEmpty && s.particles.isEmpty && floor.depth.allSatisfy{$0==0},"clear empties the desktop")
    s.paused=true
    check(!s.hasMotion,"a paused empty scene can stop redrawing")
    s.burst(.zero,count:14)
    check(s.hasMotion,"powder still animates while snowfall is paused")
    for _ in 0..<100 {s.step(1.0/30)}
    check(!s.hasMotion,"the scene returns to idle when the powder settles")
    if let gift=try? FrostGift.make(.tree,sender:"Windows friend",note:"Snow day!",senderID:FrostGift.newID(),template:nil) {
        let train=GiftTrain(), area=CGRect(x:0,y:0,width:360,height:160)
        var arrivals=0
        check(train.start(gift) {arrivals+=1},"gift train accepts a portable dressed tree")
        for _ in 0..<15 {train.step(1.0/30,bounds:area)}
        check(arrivals==0 && train.cancel(),"early train can be interrupted before its receipt")
        _=train.start(gift) {arrivals+=1}
        for _ in 0..<1300 {train.step(1.0/30,bounds:area)}
        check(arrivals==1 && train.hasActivity,"gift unloads once and leaves its tree after departure")
        let drawing=NSImage(size:area.size,flipped:true) { _ in train.draw(in:area);return true }
        var treePixels=0
        if let tiff=drawing.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff) {
            for y in stride(from:0,to:rep.pixelsHigh,by:3) {for x in stride(from:0,to:rep.pixelsWide,by:3) {
                if let p=rep.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB),p.alphaComponent>0.8,
                   p.greenComponent>p.redComponent+0.05 {treePixels+=1}
            }}
        }
        check(treePixels>16,"AppKit draws the delivered evergreen onto the desktop")
        _=train.clear()
        check(!train.hasActivity,"clearing removes delivered scenery")
    } else { check(false,"portable dressed tree creation") }
    let snowmenOK=runBuiltSnowmanChecks()
    let visitorsOK=runMacVisitorChecks()
    let workshopOK=runWorkshopChecks()
    let panelsOK=runAnchoredPanelChecks()
    let weatherOK=runMacWeatherChecks()
    let windowsOK=runMacWindowChecks()
    let dressingOK=runMacTreeDressingChecks()
    let memoryOK=runMacSceneMemoryChecks()
    return failures==0 && snowmenOK && visitorsOK && workshopOK && panelsOK && weatherOK && windowsOK && dressingOK && memoryOK
}

@MainActor private func runBuiltSnowmanChecks() -> Bool {
    let size=CGSize(width:510,height:320)
    let canvas=SnowCanvas(frame:CGRect(origin:.zero,size:size)), center:CGFloat=225
    let world=canvas.world
    var edge=SnowEdge(id:19,x:160,y:170,width:170,visible:[160...330])
    world.setDesktop(size:size,edges:[edge]);world.clear();world.paused=true
    guard let ground=world.banks.first else {return false}
    var failures=0
    func check(_ value:Bool,_ name:String) {
        print((value ? "PASS: " : "FAIL: ")+name);if !value {failures+=1}
    }
    // Use the same down/drag/up entry points used by the desktop view.
    func roll(until target:(PackedBall)->CGPoint,time:TimeInterval) -> PackedBall? {
        ground.add(at:50,amount:16,spread:3)
        let start=CGPoint(x:50,y:ground.surface(50)+1)
        guard world.down(start,at:time) else {return nil}
        world.drag(CGPoint(x:61,y:ground.surface(61)),at:time+0.08)
        guard let ball=world.balls.last else {return nil}
        let aim=target(ball)
        world.drag(aim,at:time+0.5);world.up(aim,at:time+0.8)
        return ball
    }
    guard let bottom=roll(until:{ CGPoint(x:center,y:edge.y-$0.radius+6) },time:1) else {return false}
    check(bottom.support==edge.id,"rolled snowball rests on a window ledge")
    guard let middle=roll(until:{ _ in CGPoint(x:center,y:bottom.y) },time:3) else {return false}
    check(middle.below === bottom && bottom.above === middle && !world.hasMotion,"gentle drop makes a stable two-ball stack while paused")
    let grip=CGPoint(x:middle.x,y:middle.y)
    check(world.down(grip,at:4) && middle.below == nil && bottom.above == nil,"picking up a stacked ball detaches it")
    world.up(grip,at:4.4)
    edge.x+=25;edge.y+=9;edge.visible=[185...355]
    world.setDesktop(size:size,edges:[edge]);world.step(1.0/30)
    check(abs(middle.x-center-25)<0.1 && middle.x==bottom.x,"both stacked balls follow a moved window")
    guard roll(until:{ _ in CGPoint(x:bottom.x,y:middle.y-middle.radius-63) },time:5) != nil else {return false}
    for _ in 0..<70 {world.step(1.0/30)}
    guard let figure=world.snowmen.first else {check(false,"third falling ball completes a snowman");return false}
    check(world.balls.isEmpty && world.snowmen.count==1 && figure.base>=figure.middle && figure.middle>=figure.head,
          "a third falling ball makes one proportioned snowman")
    check(world.hit(CGPoint(x:figure.x,y:figure.foot-figure.base)) && !world.hit(CGPoint(x:figure.x+figure.base+3,y:figure.foot-figure.base)),
          "only the visible snowman catches desktop clicks")
    let artwork=NSImage(size:size,flipped:true) { _ in canvas.draw(canvas.bounds);return true }
    var hatPixels=0
    if let tiff=artwork.tiffRepresentation,let image=NSBitmapImageRep(data:tiff) {
        for y in 0..<image.pixelsHigh {
            if let p=image.colorAt(x:Int(figure.x),y:y)?.usingColorSpace(.deviceRGB),p.alphaComponent>0.9,p.redComponent<0.35 {
                hatPixels+=1
            }
        }
    }
    check(hatPixels>=4,"the complete snowman is drawn with its hat on the desktop")
    if let template=world.latestSnowmanGift,
       let gift=try? FrostGift.make(.snowman,sender:"Builder",note:"For you",senderID:FrostGift.newID(),template:template),
       let data=try? gift.encoded(),let decoded=try? FrostGift.decode(data) {
        check(decoded.id != template.id && decoded.style==figure.style && decoded.facing==Double(figure.facing) &&
              abs(decoded.size-Double(figure.base))<0.0001 && abs(decoded.mid-Double(figure.middle))<0.0001 &&
              abs(decoded.head-Double(figure.head))<0.0001,"gift preserves the local snowman’s proportions, facing and scarf")
    } else {check(false,"local snowman gift roundtrip")}
    // Flick a new ball across the snowman's torso above the ledge. It must burst there.
    let torsoY=figure.foot-figure.base-0.78*(figure.base+figure.middle)
    guard let shot=roll(until:{_ in CGPoint(x:figure.x-100,y:torsoY+6)},time:7) else {return false}
    let from=CGPoint(x:shot.x,y:shot.y)
    _=world.down(from,at:8);world.up(CGPoint(x:from.x+40,y:from.y),at:8.05)
    check(shot.thrown,"flicking still throws a snowball with a completed snowman nearby")
    for _ in 0..<15 {world.step(1.0/60);if world.balls.isEmpty {break}}
    check(world.balls.isEmpty && world.snowmen.count==1 && world.particles.contains { $0.powder && abs($0.x-figure.x)<35 && $0.y<edge.y-8 },
          "a fast throw poofs on the snowman before hitting the ledge")
    let foot=figure.foot
    _=world.down(CGPoint(x:figure.x,y:foot-figure.base),at:9)
    world.up(CGPoint(x:400,y:230),at:9.5)
    for _ in 0..<90 {world.step(1.0/30)}
    check(abs(figure.x-400)<0.1 && figure.support==0 && abs(figure.foot-ground.surface(400))<0.1,
          "a finished snowman can be moved and settles on the new drift")
    world.clear()
    check(world.snowmen.isEmpty && world.latestSnowmanGift==nil && !world.hasMotion,"clear removes local snowmen and their gift template")
    return failures==0
}
