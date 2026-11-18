import AppKit

@MainActor func runMacPlayChecks() -> Bool {
    let area=CGSize(width:580,height:360)
    let canvas=SnowCanvas(frame:CGRect(origin:.zero,size:area))
    let world=canvas.world, workshop=canvas.workshop
    world.setDesktop(size:area,edges:[]);workshop.sync(world:world)
    var ok=true
    func check(_ condition:Bool,_ label:String) {
        print((condition ? "PASS: " : "FAIL: ")+label);if !condition {ok=false}
    }
    guard let flake=world.particles.first(where:{ $0.y<area.height-20 }), let floor=world.banks.first else {return false}
    let cursor=CGPoint(x:flake.x,y:flake.y)
    func sample(_ down:Bool,through:Bool=true,controls:Bool=false) {
        canvas.sampleFlakeClick(at:cursor,down:down,passThrough:through) {controls}
    }
    canvas.puffFallingSnow=false;sample(true);sample(false)
    canvas.puffFallingSnow=true;sample(true,through:false);sample(false)
    sample(true,controls:true);sample(false)
    check(!world.particles.contains(where:{$0.powder}),"disabled flake puffs and clicks on tools or app controls produce no powder")
    check(!world.hit(cursor) && !workshop.captures(cursor),"a falling flake leaves the underlying application clickable")
    sample(true)
    let powder=world.particles.filter{$0.powder}.count
    sample(true);sample(false)
    check(powder>1 && world.particles.filter{$0.powder}.count==powder,"one pass-through button press puffs the flake exactly once")
    world.clear()
    for x in stride(from:CGFloat(100),through:200,by:8) {floor.add(at:x,amount:12,spread:3)}
    let source=CGPoint(x:108,y:floor.surface(108)),end=CGPoint(x:182,y:floor.surface(182))
    let before=floor.height(source.x),far=floor.height(end.x)
    let menu=NSMenu()
    workshop.appendMenu(to:menu)
    guard let command=menu.item(withTitle:"Play on the snow")?.submenu?.item(withTitle:"Puff snow"),
          let action=command.action,command.target === workshop else {return false}
    _=workshop.perform(action)
    check(workshop.captures(source) && workshop.down(source),"Puff snow starts a desktop brush from the play menu")
    workshop.drag(end);workshop.up(end);workshop.finishEditing()
    check(floor.height(source.x)<before && floor.height(end.x)<far && world.particles.contains(where:{$0.powder}) &&
          !workshop.captures(end),"sweeping both ends of a drift scatters powder and finishing restores normal input")
    let at=CGPoint(x:320,y:floor.surface(320))
    workshop.beginPlacement(.tree);_=workshop.down(at);workshop.up(at)
    guard let tree=workshop.pieces.first else {return false}
    check(workshop.scroll(at:tree.center,delta:1,precise:false,rotating:false) && workshop.pieces[0].scale>tree.scale,
          "scrolling a decoration in Arrange resizes it")
    let bigger=workshop.pieces[0]
    _=workshop.scroll(at:bigger.center,delta:12,precise:true,rotating:true)
    check(workshop.pieces[0].angle==bigger.angle,"small trackpad deltas accumulate without writing a new angle")
    _=workshop.scroll(at:bigger.center,delta:12,precise:true,rotating:true)
    let rotated=workshop.pieces[0]
    let bounds=WorkshopSymbol.forKind(.tree).rotatedBounds(scale:rotated.scale,angle:rotated.angle)
    check(abs(rotated.angle-bigger.angle-CGFloat.pi/12)<0.001 && abs(rotated.center.y+bounds.maxY-floor.surface(rotated.center.x))<0.2,
          "Shift-scroll rotates the mounted tree by 15 degrees and keeps its trunk on the surface")
    workshop.finishEditing()
    check(!workshop.scroll(at:rotated.center,delta:1,precise:false,rotating:false) && !workshop.captures(rotated.center),
          "scroll adjustments and decoration capture stop outside Arrange")
    return ok
}
