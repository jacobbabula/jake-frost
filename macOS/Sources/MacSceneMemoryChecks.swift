import AppKit

@MainActor func runMacSceneMemoryChecks() -> Bool {
    let suite = "io.jakefrost.scene-memory-tests." + UUID().uuidString
    guard let settings = UserDefaults(suiteName:suite) else { return false }
    defer { settings.removePersistentDomain(forName:suite) }
    var ok = true
    func check(_ result: Bool, _ name: String) {
        print((result ? "PASS: " : "FAIL: ") + name);if !result { ok = false }
    }
    let desktop = CGSize(width:500,height:340)
    var edge = SnowEdge(id:59,x:100,y:170,width:200,visible:[100...300])
    let world = SnowWorld()
    world.configureSnowmanStorage(settings:settings,displayID:6)
    world.setDesktop(size:desktop,edges:[edge]);world.paused=true
    let floor = world.banks[0], center: CGFloat = 200
    func roll(_ time: TimeInterval, onto position:(PackedBall)->CGPoint) -> PackedBall? {
        floor.add(at:35,amount:16,spread:3)
        let start=CGPoint(x:35,y:floor.surface(35)+1)
        guard world.down(start,at:time) else { return nil }
        world.drag(CGPoint(x:48,y:floor.surface(48)),at:time+0.08)
        guard let ball=world.balls.last else { return nil }
        let aim=position(ball)
        world.drag(aim,at:time+0.5);world.up(aim,at:time+0.8)
        return ball
    }
    guard let bottom=roll(1,onto:{CGPoint(x:center,y:edge.y-$0.radius+6)}),
          let middle=roll(3,onto:{_ in CGPoint(x:center,y:bottom.y)}),
          roll(5,onto:{_ in CGPoint(x:center,y:middle.y)}) != nil,
          let figure=world.snowmen.first, let built=settings.data(forKey:"snowmen.v1.6") else {
        check(false,"finishing a snowman automatically saves its display");return false
    }
    check(MacSceneMemory.remembers(settings),"existing installations remember decorations and completed snowmen by default")
    edge.x+=30;edge.y+=9;edge.visible=[130...330]
    world.setDesktop(size:desktop,edges:[edge]);world.step(1.0/30)
    check(figure.x == center+30 && settings.data(forKey:"snowmen.v1.6") == built,
          "window-following frames move the snowman without writing preferences")
    world.rememberSnowmenNow()
    let reopened = SnowWorld()
    reopened.configureSnowmanStorage(settings:settings,displayID:6)
    check(reopened.snowmen.isEmpty,"display restoration waits for its first real desktop layout")
    reopened.setDesktop(size:desktop,edges:[edge])
    guard let restored=reopened.snowmen.first else { check(false,"reopening restores the saved figure");return false }
    check(restored.support == edge.id && restored.x == figure.x && restored.foot == figure.foot &&
          restored.base == figure.base && restored.middle == figure.middle && restored.head == figure.head &&
          restored.facing == figure.facing && restored.style == figure.style,
          "a saved snowman returns to its ledge with its original proportions, scarf and facing")
    reopened.setDesktop(size:desktop,edges:[])
    for _ in 0..<120 { reopened.step(1.0/30) }
    check(reopened.snowmen.isEmpty && settings.object(forKey:"snowmen.v1.6")==nil && reopened.banks[0].depth.reduce(0,+)>0,
          "a snowman falling from a removed window breaks into the floor and stays removed on disk")
    reopened.dropVisitorSnowman(at:figure.x,scale:1)
    let resized=SnowWorld(), wide=CGSize(width:750,height:350)
    resized.configureSnowmanStorage(settings:settings,displayID:6);resized.setDesktop(size:wide,edges:[])
    check(resized.snowmen.count == 1 && resized.snowmen[0].support == 0 &&
          abs(resized.snowmen[0].x-figure.x*1.5)<0.05,"a newly arrived snowman retains its ground position across a resolution change")
    let unrelated=SnowWorld()
    unrelated.configureSnowmanStorage(settings:settings,displayID:7);unrelated.setDesktop(size:desktop,edges:[])
    check(unrelated.snowmen.isEmpty && settings.data(forKey:"snowmen.v1.6") != nil,"each display owns its own snowmen")
    let workshop=MacWorkshop()
    workshop.configure(settings:settings,displayID:6);workshop.sync(world:reopened)
    let tree=CGPoint(x:80,y:210)
    workshop.beginPlacement(.tree);_=workshop.down(tree);workshop.up(tree)
    settings.set(Data([7]),forKey:"workshop.v1.903")
    MacSceneMemory.setRemember(false,settings:settings)
    reopened.rememberSnowmenNow();workshop.rememberLayoutNow()
    check(reopened.snowmen.count==1 && workshop.pieces.count==1 && settings.object(forKey:"snowmen.v1.6")==nil &&
          settings.object(forKey:"workshop.v1.6")==nil && settings.object(forKey:"workshop.v1.903")==nil,
          "turning off remembering keeps the live scene and forgets stored scenes from all displays")
    MacSceneMemory.setRemember(true,settings:settings)
    reopened.rememberSnowmenNow();workshop.rememberLayoutNow()
    check(settings.data(forKey:"snowmen.v1.6") != nil && settings.data(forKey:"workshop.v1.6") != nil,
          "turning remembering back on saves the current decorations and snowmen")
    reopened.clear();workshop.clear()
    let empty=SnowWorld();empty.configureSnowmanStorage(settings:settings,displayID:6);empty.setDesktop(size:desktop,edges:[])
    check(empty.snowmen.isEmpty && settings.object(forKey:"snowmen.v1.6")==nil && settings.object(forKey:"workshop.v1.6")==nil,
          "Clear scene permanently clears remembered snowmen and decorations")
    return ok
}
