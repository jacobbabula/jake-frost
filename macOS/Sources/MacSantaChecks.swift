import AppKit

@MainActor func runMacSantaChecks() -> Bool {
    let suite = "JakeFrost-Santa-Checks-" + UUID().uuidString
    guard let settings = UserDefaults(suiteName:suite) else {return false}
    defer {settings.removePersistentDomain(forName:suite)}
    let canvas = SnowCanvas(frame:CGRect(x:0,y:0,width:280,height:160))
    canvas.santaPresent.settings=settings
    canvas.world.setDesktop(size:canvas.bounds.size,edges:[])
    canvas.world.amount=0
    canvas.visitors.summon(.santa,in:canvas.world)
    for _ in 0..<600 {
        canvas.frameTick(1.0/30,cursor:.zero)
        if let foot=canvas.santaPresent.foot,foot.y>=159 {break}
    }
    guard let drop=canvas.santaPresent.foot,drop.x>90,drop.y>=159 else {return false}
    let artwork=NSImage(size:canvas.bounds.size,flipped:true) { _ in
        canvas.santaPresent.draw(in:canvas.bounds);return true
    }
    guard let data=artwork.tiffRepresentation,let bmp=NSBitmapImageRep(data:data) else {return false}
    var ribbonPixels=0, paperPixels=0
    for y in 0..<bmp.pixelsHigh {
        for x in max(0,Int(drop.x)-13)..<min(bmp.pixelsWide,Int(drop.x)+14) {
            guard let color=bmp.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB),color.alphaComponent>0.7 else {continue}
            if color.redComponent>0.7 && color.greenComponent>0.55 && color.blueComponent<0.6 {ribbonPixels+=1}
            if color.redComponent>0.45 && color.greenComponent<0.45 && color.blueComponent<0.45 {paperPixels+=1}
        }
    }
    guard ribbonPixels>14,paperPixels>80 else {return false}
    let world = SnowWorld()
    world.setDesktop(size:CGSize(width:280,height:160),edges:[])
    world.clear()
    let first = MacSantaPresent()
    first.settings = settings
    let date = Date(timeIntervalSince1970:1_798_000_000)
    first.drop(at:CGPoint(x:120,y:29),date:date)
    guard let start=first.foot else {return false}
    first.drop(at:.zero,date:date)
    guard first.foot==start && first.animating else {return false}
    for _ in 0..<180 {first.step(1.0/60,world:world)}
    guard let ground=first.foot, ground.y==160, !first.animating else {return false}
    let blade=PlowSweep(from:CGPoint(x:78,y:160),angle:0,to:CGPoint(x:93,y:160),angle:0,scale:1,speed:50)
    first.plow(blade,world:world)
    guard let moved=first.foot, moved.x>ground.x else {return false}
    let hit=CGPoint(x:moved.x,y:moved.y-14)
    guard !first.captures(CGPoint(x:hit.x+20,y:hit.y)), first.captures(hit),
          first.open(at:hit,world:world,date:date), first.foot==nil, !first.note.isEmpty,
          first.animating, world.particles.contains(where:{$0.powder}),
          !first.open(at:hit,world:world,date:date) else {return false}
    let fortune=first.note
    first.step(10,world:world)
    first.drop(at:hit,date:date)
    guard first.note.isEmpty, !first.animating, first.foot==nil else {return false}
    let other=MacSantaPresent()
    other.settings=UserDefaults(suiteName:suite)!
    other.drop(at:moved,date:date)
    guard other.open(at:hit,world:world,date:date), other.note != fortune,
          other.note.contains("already") else {return false}
    let tomorrow=date.addingTimeInterval(24*3600)
    other.drop(at:moved,date:tomorrow)
    other.clear()
    other.drop(at:moved,date:tomorrow)
    guard other.open(at:hit,world:world,date:tomorrow), !other.note.contains("already") else {return false}
    print("PASS: Santa's daily present falls, meets the blade, opens with powder, and remembers its fortune across displays and launches")
    return true
}
