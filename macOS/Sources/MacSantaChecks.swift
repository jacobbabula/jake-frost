import AppKit

@MainActor func runMacSantaChecks() -> Bool {
    func failed(_ stage:String)->Bool {print("FAIL: Santa's daily present " + stage);return false}
    let suite = "JakeFrost-Santa-Checks-" + UUID().uuidString
    guard let settings = UserDefaults(suiteName:suite) else {return false}
    defer {settings.removePersistentDomain(forName:suite)}
    let canvas = SnowCanvas(frame:CGRect(x:0,y:0,width:280,height:160))
    canvas.santaPresent.settings=settings
    canvas.world.amount=0
    canvas.world.setDesktop(size:canvas.bounds.size,edges:[])
    guard let snow=canvas.world.banks.first else {return failed("had no landing surface")}
    canvas.visitors.summon(.santa,in:canvas.world)
    for _ in 0..<600 {
        canvas.frameTick(1.0/30,cursor:.zero)
        if let foot=canvas.santaPresent.foot, abs(foot.y-snow.surface(foot.x))<0.01 {break}
    }
    guard let drop=canvas.santaPresent.foot,drop.x>90,abs(drop.y-snow.surface(drop.x))<0.01 else {return failed("did not land after the sleigh passed")}
    let artwork=NSImage(size:canvas.bounds.size,flipped:true) { _ in
        canvas.santaPresent.draw(in:canvas.bounds);return true
    }
    guard let data=artwork.tiffRepresentation,let bmp=NSBitmapImageRep(data:data) else {return failed("could not render its parcel")}
    var ribbonPixels=0, paperPixels=0
    let density=CGFloat(bmp.pixelsWide)/canvas.bounds.width
    let left=max(0,Int((drop.x-13)*density)),right=min(bmp.pixelsWide,Int((drop.x+14)*density))
    for y in 0..<bmp.pixelsHigh {
        for x in left..<right {
            guard let color=bmp.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB),color.alphaComponent>0.7 else {continue}
            if color.redComponent>0.7 && color.greenComponent>0.55 && color.blueComponent<0.6 {ribbonPixels+=1}
            if color.redComponent>0.45 && color.greenComponent<0.45 && color.blueComponent<0.45 {paperPixels+=1}
        }
    }
    guard ribbonPixels>14,paperPixels>80 else {return failed("drew \(paperPixels) wrapping and \(ribbonPixels) ribbon pixels")}
    let world = SnowWorld()
    world.setDesktop(size:CGSize(width:280,height:160),edges:[])
    world.clear()
    let first = MacSantaPresent()
    first.settings = settings
    let date = Date(timeIntervalSince1970:1_798_000_000)
    first.drop(at:CGPoint(x:120,y:29),date:date)
    guard let start=first.foot else {return failed("did not leave the sleigh")}
    first.drop(at:.zero,date:date)
    guard first.foot==start && first.animating else {return failed("was dropped twice on one display")}
    for _ in 0..<180 {first.step(1.0/60,world:world)}
    guard let ground=first.foot, ground.y==160, !first.animating else {return failed("did not settle on the ground")}
    let blade=PlowSweep(from:CGPoint(x:78,y:160),angle:0,to:CGPoint(x:93,y:160),angle:0,scale:1,speed:50)
    first.plow(blade,world:world)
    guard let moved=first.foot, moved.x>ground.x else {return failed("was missed by the blade")}
    let hit=CGPoint(x:moved.x,y:moved.y-14)
    guard !first.captures(CGPoint(x:hit.x+20,y:hit.y)), first.captures(hit),
          first.open(at:hit,world:world,date:date), first.foot==nil, !first.note.isEmpty,
          first.animating, world.particles.contains(where:{$0.powder}),
          !first.open(at:hit,world:world,date:date) else {return failed("could not be opened once with powder")}
    let fortune=first.note
    first.step(10,world:world)
    first.drop(at:hit,date:date)
    guard first.note.isEmpty, !first.animating, first.foot==nil else {return failed("reappeared after it was claimed")}
    let other=MacSantaPresent()
    other.settings=UserDefaults(suiteName:suite)!
    other.drop(at:moved,date:date)
    guard other.open(at:hit,world:world,date:date), other.note != fortune,
          other.note.contains("already") else {return failed("was redeemable twice from the same profile")}
    let tomorrow=date.addingTimeInterval(24*3600)
    other.drop(at:moved,date:tomorrow)
    other.clear()
    other.drop(at:moved,date:tomorrow)
    guard other.open(at:hit,world:world,date:tomorrow), !other.note.contains("already") else {return failed("did not reset for the next day")}
    print("PASS: Santa's daily present falls, meets the blade, opens with powder, and remembers its fortune across displays and launches")
    return true
}
