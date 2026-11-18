import AppKit

@MainActor func runWorkshopChecks() -> Bool {
    var ok=true
    func check(_ condition:Bool,_ name:String) {
        print((condition ? "PASS: " : "FAIL: ")+name)
        if !condition {ok=false}
    }
    func close(_ a:CGPoint,_ b:CGPoint)->Bool {hypot(a.x-b.x,a.y-b.y)<0.05}
    let name="io.jakefrost.workshop-tests."+UUID().uuidString
    guard let storage=UserDefaults(suiteName:name) else{return false}
    defer {storage.removePersistentDomain(forName:name)}
    let world=SnowWorld()
    let area=CGSize(width:540,height:340)
    var ledge=SnowEdge(id:27,x:60,y:200,width:240,visible:[60...300])
    world.setDesktop(size:area,edges:[ledge])
    let workshop=MacWorkshop()
    workshop.configure(settings:storage,displayID:8);workshop.sync(world:world)
    let here=CGPoint(x:185,y:199)
    check(!workshop.captures(here),"decorations initially pass through desktop clicks")
    workshop.beginPlacement(.tree)
    check(workshop.captures(here) && workshop.down(here),"choosing a tree arms desktop placement")
    workshop.up(here)
    guard let first=workshop.pieces.first else{return false}
    let symbol=WorkshopSymbol.forKind(.tree)
    let bounds=symbol.rotatedBounds(scale:first.scale,angle:first.angle)
    check(abs(first.center.y+bounds.maxY-ledge.y)<0.05,"tree trunk settles on the exposed ledge")
    ledge.x+=32;ledge.y-=14;ledge.visible=[92...332]
    world.setDesktop(size:area,edges:[ledge]);workshop.sync(world:world)
    let moved=workshop.pieces[0]
    check(close(moved.center,CGPoint(x:first.center.x+32,y:first.center.y-14)),"mounted tree follows its window")
    let knob=CGPoint(x:moved.center.x+bounds.maxX+4,y:moved.center.y+bounds.minY-4)
    let turned=CGPoint(x:moved.center.x-(knob.y-moved.center.y),y:moved.center.y+knob.x-moved.center.x)
    _=workshop.down(knob);workshop.drag(turned);workshop.up(turned)
    let rotated=workshop.pieces[0]
    let extent=symbol.rotatedBounds(scale:rotated.scale,angle:rotated.angle)
    check(abs(rotated.angle - .pi/2)<0.04 && abs(rotated.center.y+extent.maxY-ledge.y)<0.05,
          "rotation keeps the visible outline touching the snow")
    let sizeHandle=CGPoint(x:rotated.center.x+extent.maxX+4,y:rotated.center.y+extent.maxY+4)
    let larger=CGPoint(x:rotated.center.x+1.3*(sizeHandle.x-rotated.center.x),y:rotated.center.y+1.3*(sizeHandle.y-rotated.center.y))
    _=workshop.down(sizeHandle);workshop.up(larger)
    check(workshop.pieces[0].scale>1.25,"resizing changes the tree itself")

    let a=CGPoint(x:30,y:45),b=CGPoint(x:170,y:75)
    workshop.beginPlacement(.lights);_=workshop.down(a);workshop.drag(b);workshop.up(b)
    guard var wire=workshop.pieces.last,wire.kind == .lights else{return false}
    check(close(wire.wirePoint(0),a) && close(wire.wirePoint(1),b),"dragging creates an angled strand between both anchors")
    let tilted=CGPoint(x:183,y:37)
    _=workshop.down(b);workshop.up(tilted);wire=workshop.pieces.last!
    check(close(wire.wirePoint(0),a) && close(wire.wirePoint(1),tilted),"moving one light endpoint preserves the opposite anchor")
    let middle=wire.wirePoint(0.5)
    _=workshop.down(middle);workshop.up(CGPoint(x:middle.x,y:middle.y+21));wire=workshop.pieces.last!
    check(abs(wire.sag-43)<0.05 && close(wire.wirePoint(1),tilted),"the middle handle changes sag independently of angle")
    workshop.finishEditing()
    check(!workshop.captures(wire.wirePoint(0.5)),"Done restores desktop clicks through the light strand")
    let drawing=NSImage(size:area,flipped:true) { _ in workshop.draw();return true }
    var green=0,lit=0
    if let tiff=drawing.tiffRepresentation,let pixels=NSBitmapImageRep(data:tiff) {
        for y in stride(from:0,to:pixels.pixelsHigh,by:2) {
            for x in stride(from:0,to:pixels.pixelsWide,by:2) {
                guard let c=pixels.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB),c.alphaComponent>0.65 else{continue}
                if c.greenComponent>c.redComponent+0.12 {green+=1}
                if c.redComponent>0.75 && c.redComponent>c.greenComponent+0.05 {lit+=1}
            }
        }
    }
    check(green>35 && lit>10,"cached art paints evergreen needles and colored bulbs into the overlay")
    let restored=MacWorkshop();restored.configure(settings:storage,displayID:8);restored.sync(world:world)
    check(restored.pieces.count==2 && restored.pieces.first?.id==first.id &&
          restored.pieces.last?.sag==wire.sag && restored.pieces.first?.angle==rotated.angle,"reopening the display restores its arrangement")
    let other=MacWorkshop();other.configure(settings:storage,displayID:9);other.sync(world:world)
    check(other.pieces.isEmpty,"each display keeps its own arrangement")
    restored.clear()
    let again=MacWorkshop();again.configure(settings:storage,displayID:8)
    check(again.pieces.isEmpty,"clearing the scene clears the saved decorations")
    guard let floor=world.banks.first else{return false}
    world.clear()
    let brush=CGPoint(x:400,y:326)
    let before=floor.height(brush.x)
    workshop.beginPiling();_=workshop.down(brush)
    let once=floor.height(brush.x)
    for _ in 0..<40 {workshop.step(1.0/60)}
    let held=floor.height(brush.x)
    workshop.drag(CGPoint(x:432,y:326));workshop.up(CGPoint(x:432,y:326));workshop.finishEditing()
    check(once>before && held>once+15 && floor.height(431)>0 && !workshop.captures(brush),
          "holding and dragging the snow brush builds a continuous hill and Done returns control")
    let track=MacSledField()
    let sled=track.add(at:CGPoint(x:414,y:floor.surface(414)),world:world)
    check(sled.support==0,"sled sits on the actual snow surface")
    let original=sled.x
    for _ in 0..<120 {track.step(1.0/60,world:world)}
    check(sled.x>original+12,"gravity carries the sled down the brush-built hill")
    for _ in 0..<1500 {track.step(1.0/60,world:world)}
    check(sled.support==0 && !track.hasMotion,"the sled settles to a stop on flat snow")
    let nose=CGPoint(x:sled.x+6,y:sled.y-8)
    check(track.down(nose,time:0),"sled can be grabbed directly on the desktop")
    track.up(nose,time:0.1,world:world)
    check(sled.vx<0,"a tap on the nose pushes the sled back")
    let start=CGPoint(x:sled.x,y:sled.y-6)
    _=track.down(start,time:1)
    track.drag(CGPoint(x:start.x-7,y:start.y-12),time:1.04)
    track.up(CGPoint(x:start.x-17,y:start.y-15),time:1.08,world:world)
    check(sled.support==nil && sled.vx < -30,"a dragged sled inherits the release velocity")
    track.clear();check(track.sleds.isEmpty && !track.hasMotion,"clear removes desktop sleds and their physics")
    return ok
}
