import AppKit

@MainActor func runMacSantaChecks() -> Bool {
    let suite = "JakeFrost-Santa-Checks-" + UUID().uuidString
    guard let settings = UserDefaults(suiteName:suite) else {return false}
    defer {settings.removePersistentDomain(forName:suite)}
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
