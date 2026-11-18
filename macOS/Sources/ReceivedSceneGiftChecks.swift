import AppKit

@MainActor func runReceivedSceneGiftChecks() -> Bool {
    let suite="io.jakefrost.gift-unload-tests."+UUID().uuidString
    guard let settings=UserDefaults(suiteName:suite) else { return false }
    defer { settings.removePersistentDomain(forName:suite) }
    let area=CGRect(x:0,y:0,width:580,height:370)
    var ok=true
    func check(_ result:Bool,_ name:String) {
        print((result ? "PASS: " : "FAIL: ")+name);if !result { ok=false }
    }
    func canvas(_ display:UInt32) -> SnowCanvas {
        let c=SnowCanvas(frame:area)
        c.world.configureSnowmanStorage(settings:settings,displayID:display)
        c.giftTrain.configureParcelStorage(settings:settings,displayID:display)
        c.workshop.configure(settings:settings,displayID:display)
        c.world.setDesktop(size:area.size,edges:[]);c.workshop.sync(world:c.world)
        return c
    }
    func deliver(_ gift:FrostGift,to c:SnowCanvas) -> Bool {
        var arrived=false
        guard c.giftTrain.start(gift,onArrival:{ arrived=true }) else { return false }
        for _ in 0..<220 {
            c.giftTrain.step(0.05,bounds:area)
            if arrived { break }
        }
        _=c.giftTrain.cancel()
        return arrived
    }
    let scene=canvas(4)
    var tree=FrostGift();tree.kind = .tree;tree.size=98;tree.style=13
    tree.dress="3,-0.12,-0.4;12,0.1,-0.66;scale,1,4;angles,25,0,-35"
    check(deliver(tree,to:scene) && scene.workshop.pieces.count==3 && !scene.giftTrain.containsParcel(tree.id),
          "the train unloads a dressed tree into editable decorations")
    guard let trunk=scene.workshop.pieces.first,let branch=scene.workshop.pieces.last,
          let template=scene.workshop.treeGiftTemplate() else { return false }
    let foot=trunk.center.y+WorkshopSymbol.forKind(.tree).rotatedBounds(scale:trunk.scale,angle:trunk.angle).maxY
    check(abs(foot-scene.world.banks[0].surface(trunk.center.x))<0.05 &&
          abs(trunk.center.x-(area.width*0.46-83))<0.05 && branch.kind == .holly &&
          branch.attachment?.tree == trunk.id && template.style==13 && abs(template.size-98)<0.05 &&
          template.dress.contains("scale,1,4.0000") && template.dress.contains("angles,25.0000,0.0000,-35.0000"),
          "unloading retains the gift's branch positions, ornament scale, tilt and original style at the station")
    scene.workshop.arrange()
    let berry=CGPoint(x:branch.center.x-12*branch.scale*sin(branch.angle),y:branch.center.y+12*branch.scale*cos(branch.angle))
    _=scene.workshop.down(berry)
    let target=CGPoint(x:berry.x+140,y:berry.y-30)
    scene.workshop.up(target)
    check(scene.workshop.pieces.last?.attachment==nil && scene.workshop.treeGiftTemplate()?.dress.contains("12,") == false,
          "a received ornament can be dragged off its tree")
    check(deliver(tree,to:scene) && scene.workshop.pieces.count==3 && scene.workshop.pieces.last?.attachment==nil,
          "replaying a gift preserves edits and creates no second tree")

    var snowman=FrostGift();snowman.kind = .snowman;snowman.size=23;snowman.mid=15;snowman.head=8
    snowman.style=7;snowman.facing = -1
    check(deliver(snowman,to:scene) && !scene.giftTrain.containsParcel(snowman.id) && scene.world.snowmen.count==1,
          "a delivered snowman becomes part of the playable scene")
    guard let figure=scene.world.snowmen.first else { return false }
    let grab=CGPoint(x:figure.x,y:figure.foot-figure.base), destination=CGPoint(x:350,y:220)
    _=scene.world.down(grab,at:1);scene.world.up(destination,at:2)
    for _ in 0..<95 { scene.world.step(1.0/30) }
    check(abs(figure.x-destination.x)<0.05 && figure.support==0 && figure.style==7 && figure.head==8,
          "a received snowman can be moved to another drift")
    let reopened=canvas(4)
    check(reopened.containsReceivedGift(tree.id) && reopened.containsReceivedGift(snowman.id) &&
          deliver(snowman,to:reopened) && reopened.world.snowmen.count==1 && reopened.workshop.pieces.count==3,
          "reopening and replaying restores one copy of each delivered present")
    let second=canvas(5)
    second.giftExistsElsewhere = { MacSceneMemory.containsGift($0,in:settings,excluding:[5]) }
    check(deliver(snowman,to:second) && second.world.snowmen.isEmpty && deliver(tree,to:second) && second.workshop.pieces.isEmpty,
          "a replay on another display leaves its saved original in place")
    let full=canvas(9)
    var tooLarge=FrostGift();tooLarge.kind = .tree;tooLarge.size=100
    tooLarge.dress=Array(repeating:"4,0,-0.5",count:100).joined(separator:";")
    check(deliver(tooLarge,to:full) && full.workshop.pieces.isEmpty && full.giftTrain.containsParcel(tooLarge.id) &&
          deliver(tooLarge,to:full) && full.giftTrain.containsParcel(tooLarge.id),
          "a gift exceeding editor capacity stays visible as one train parcel and leaves the workshop intact")
    let reopenedFull=canvas(9)
    check(reopenedFull.giftTrain.containsParcel(tooLarge.id) && MacSceneMemory.containsGift(tooLarge.id,in:settings,excluding:[4,5]),
          "overflow presents survive reopening and are discoverable on disconnected displays")
    MacSceneMemory.setRemember(false,settings:settings)
    let fresh=canvas(4)
    check(!fresh.containsReceivedGift(tree.id) && !fresh.containsReceivedGift(snowman.id) && !canvas(9).containsReceivedGift(tooLarge.id),
          "turning off scene memory also forgets delivered scene objects")
    return ok
}
