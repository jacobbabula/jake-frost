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
    let visitorsOK=runMacVisitorChecks()
    let workshopOK=runWorkshopChecks()
    let panelsOK=runAnchoredPanelChecks()
    return failures==0 && visitorsOK && workshopOK && panelsOK
}
