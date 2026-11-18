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
    let rendered=NSImage(size:screen.size,flipped:true) { _ in view.draw(view.bounds);return true }
    var painted=false
    if let tiff=rendered.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff) {
        for y in stride(from:0,to:rep.pixelsHigh,by:2) {
            if (rep.colorAt(x:70,y:y)?.alphaComponent ?? 0)>0.85 {painted=true;break}
        }
    }
    check(painted,"AppKit raster contains visible snow")
    s.clear();check(s.balls.isEmpty && s.particles.isEmpty && floor.depth.allSatisfy{$0==0},"clear empties the desktop")
    return failures==0
}
