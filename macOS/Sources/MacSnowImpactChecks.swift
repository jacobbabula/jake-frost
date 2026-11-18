import AppKit

@MainActor func runMacSnowImpactChecks()->Bool {
    var passed=true
    func check(_ ok:Bool,_ label:String) {print((ok ? "PASS: ":"FAIL: ")+label);passed=passed && ok}
    let size=CGSize(width:760,height:450)
    func scene(_ edges:[SnowEdge]=[])->SnowWorld {
        let w=SnowWorld();w.setDesktop(size:size,edges:edges);w.clear();w.wind=0;w.amount=0
        w.setAccumulation(160);return w
    }
    func advance(_ w:SnowWorld,_ frames:Int) {for _ in 0..<frames {w.step(1.0/60)}}
    let shelf=SnowEdge(id:91,x:55,y:245,width:615,visible:[55...670])
    let impact=scene([shelf])
    let from=CGPoint(x:340,y:100),release=CGPoint(x:340,y:148)
    _=impact.throwDown(from,at:0);impact.up(release,at:0.06)
    advance(impact,14)
    check(impact.balls.isEmpty && !impact.fragments.isEmpty && impact.particles.contains{$0.wisp},
          "a fast mouse throw shatters against a window and emits both clumps and a powder cloud")
    advance(impact,240)
    let shelfMass=impact.banks[1].depth.reduce(0,+)
    check(shelfMass>5 && impact.banks[0].depth.reduce(0,+)<0.01 && impact.fragments.isEmpty,
          "fragments come to rest on the window they landed on")

    let ledge=SnowEdge(id:92,x:90,y:150,width:150,visible:[90...240])
    let roll=scene([ledge]),bank=roll.banks[1]
    let a=CGPoint(x:180,y:bank.surface(180)-9),b=CGPoint(x:217,y:bank.surface(217)-9)
    _=roll.rollDown(a,at:0);roll.up(b,at:0.10)
    check(roll.balls.first?.support==92 && (roll.balls.first?.vx ?? 0)>100,
          "a horizontal mouse flick rolls a ball along its window")
    advance(roll,300)
    check(roll.balls.isEmpty && roll.banks[0].depth.reduce(0,+)>4,
          "a rolling ball that goes over the ledge crumbles into the floor drift")

    let fall=scene(),x:CGFloat=180
    fall.dropVisitorSnowman(at:x,scale:1)
    guard let man=fall.snowmen.first else{return false}
    man.support=nil;man.foot-=6;advance(fall,40)
    check(fall.snowmen.count==1 && man.support==0,"a short drop leaves the assembled snowman intact")
    man.support=nil;man.foot-=130;advance(fall,230)
    check(fall.snowmen.isEmpty && fall.banks[0].depth.reduce(0,+)>65,
          "a long fall fractures each of the snowman's original three sections into snow")
    let throwMan=scene([shelf]);throwMan.dropVisitorSnowman(at:330,scale:1.5)
    guard let thrown=throwMan.snowmen.first else{return false}
    let grip=CGPoint(x:thrown.x,y:thrown.foot-thrown.base),raised=CGPoint(x:345,y:115)
    _=throwMan.down(grip,at:0);throwMan.drag(raised,at:0.9)
    throwMan.up(CGPoint(x:360,y:154),at:0.95)
    check(thrown.thrown,"releasing a lifted snowman quickly supplies throw velocity")
    advance(throwMan,275)
    check(throwMan.snowmen.isEmpty && throwMan.banks[1].depth.reduce(0,+)>shelfMass*4,
          "a thrown full-size snowman builds a deeper drift on impact than a single ball")
    let fight=scene();fight.dropVisitorSnowman(at:300,scale:1)
    let awake=fight.wakeSnowmen()
    check(awake && fight.battle.players.count>=4 && fight.snowmen.filter{!$0.guest}.count==1,
          "waking a single figure brings two teams to the desktop")
    advance(fight,1350)
    check(fight.battle.hits>=3 && fight.battle.knockouts>=1 && fight.banks[0].depth.reduce(0,+)>10,
          "team shots hit, knock out figures and deposit snow")
    fight.clear()
    check(!fight.battle.active && fight.fragments.isEmpty && fight.snowmen.isEmpty,"clearing ends the match and removes all transient players")

    let view=SnowCanvas(frame:CGRect(origin:.zero,size:size)),visitors=view.visitors
    view.world.setDesktop(size:size,edges:[]);view.world.clear();view.workshop.sync(world:view.world)
    let point=CGPoint(x:149,y:view.world.banks[0].surface(149))
    view.workshop.beginPlacement(.tree);_=view.workshop.down(point);view.workshop.up(point);view.workshop.finishEditing()
    visitors.summonWild(in:view.world,direction:-1)
    for _ in 0..<200 {visitors.step(1.0/30,world:view.world)}
    check(visitors.wildCount==1 && view.workshop.trees.count==1,"a blizzard runner crosses the scene without chopping a tree")
    visitors.clearWild();visitors.summon(.yeti,in:view.world)
    var carried=false
    for _ in 0..<390 {
        visitors.step(1.0/30,world:view.world);view.workshop.step(1.0/30)
        carried=carried || visitors.yetis.contains{$0.carrying}
    }
    check(carried && view.workshop.trees.isEmpty,"a visiting Yeti reaches a ground tree, chops it and carries the log away")
    visitors.clear();visitors.summon(.snowmen,in:view.world)
    for _ in 0..<410 {visitors.step(1.0/30,world:view.world)}
    check(view.world.snowmen.contains{!$0.guest && $0.support==0},"visiting snowmen leave a playable figure in the scene")
    visitors.clear();visitors.summon(.yeti,in:view.world)
    var waved=false
    for _ in 0..<620 {
        visitors.step(1.0/30,world:view.world)
        waved=waved || visitors.yetis.contains{$0.greeted}
    }
    check(waved && view.world.snowmen.count==1,"a Yeti coming the other way stops to greet an existing snowman")
    return runMacSnowGalleryIfRequested() && passed
}
