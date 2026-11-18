import AppKit

@MainActor func runMacTreeDressingChecks() -> Bool {
    var ok = true
    func check(_ condition: Bool, _ name: String) {
        print((condition ? "PASS: " : "FAIL: ") + name)
        if !condition { ok = false }
    }
    func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a-b) < 0.02 }
    func offset(_ p: CGPoint, _ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x:p.x+x, y:p.y+y) }
    let name = "io.jakefrost.tree-dress-tests." + UUID().uuidString
    guard let settings = UserDefaults(suiteName:name) else { return false }
    defer { settings.removePersistentDomain(forName:name) }
    let world = SnowWorld(), desktop = CGSize(width:560,height:380)
    var ledge = SnowEdge(id:13,x:120,y:250,width:230,visible:[120...350])
    world.setDesktop(size:desktop,edges:[ledge])
    let workshop = MacWorkshop()
    workshop.configure(settings:settings,displayID:38);workshop.sync(world:world)
    func place(_ kind: WorkshopKind, _ p: CGPoint) {
        workshop.beginPlacement(kind);_=workshop.down(p);workshop.up(p)
    }
    func command(_ title: String, in w: MacWorkshop) -> Bool {
        let menu = NSMenu(); w.appendMenu(to:menu)
        guard let item = menu.item(withTitle:"Decorate")?.submenu?.item(withTitle:title), item.isEnabled,
              let action = item.action else { return false }
        return NSApplication.shared.sendAction(action,to:item.target,from:item)
    }
    check(workshop.treeGiftTemplate() == nil, "an empty scene offers no local tree gift")
    place(.tree, CGPoint(x:220,y:250))
    let tree = workshop.pieces[0]
    let anchorPoint = offset(tree.center,9,-2)
    place(.goldBauble, anchorPoint)
    guard let initial = workshop.pieces.last, let attachment = initial.attachment else {
        check(false, "placing an ornament on a branch attaches it"); return false
    }
    check(attachment.tree == tree.id && close(initial.center.x,anchorPoint.x) &&
          close(initial.center.y,anchorPoint.y) && initial.scale < 0.5, "branch ornaments fit the tree under the pointer")
    let wasResized = command("Make larger",in:workshop)
    check(wasResized && close(workshop.pieces[1].attachment?.magnification ?? 0,1.2),
          "ornaments have independent size controls while attached")
    ledge.x += 26; ledge.y -= 11; ledge.visible = [146...376]
    world.setDesktop(size:desktop,edges:[ledge]);workshop.sync(world:world)
    check(close(workshop.pieces[1].center.x,initial.center.x+26) && close(workshop.pieces[1].center.y,initial.center.y-11),
          "the moving window carries both its tree and ornaments")
    workshop.arrange()
    let trunk = offset(workshop.pieces[0].center,0,35)
    _=workshop.down(trunk);workshop.up(offset(trunk,70,-40))
    let moved = workshop.pieces[0], branch = workshop.pieces[1]
    check(close(branch.center.x-initial.center.x,96) && close(branch.center.y-initial.center.y,-51),
          "dragging a tree carries its decorations")
    let didResize = command("Make larger",in:workshop)
    let large = workshop.pieces[0], largerBranch = workshop.pieces[1]
    check(didResize && close(large.scale,1.2) && close(largerBranch.scale,branch.scale*1.2) &&
          close(largerBranch.center.x-large.center.x,(branch.center.x-moved.center.x)*1.2),
          "resizing a dressed tree scales its ornaments and branch offsets")
    let bounds = WorkshopSymbol.forKind(.tree).rotatedBounds(scale:large.scale,angle:large.angle)
    let handle = offset(large.center,bounds.maxX+4,bounds.minY-4)
    let end = offset(large.center,-(handle.y-large.center.y),handle.x-large.center.x)
    _=workshop.down(handle);workshop.up(end)
    let turned = workshop.pieces[1], rotated = workshop.pieces[0]
    check(close(rotated.angle,.pi/2) && close(turned.angle,.pi/2) &&
          close(turned.center.x-rotated.center.x,-(largerBranch.center.y-large.center.y)) &&
          close(turned.center.y-rotated.center.y,largerBranch.center.x-large.center.x),
          "turning the tree rotates its ornaments around the trunk")
    let restored = MacWorkshop()
    restored.configure(settings:settings,displayID:38);restored.sync(world:world)
    guard restored.pieces.count == 2, let copy = restored.treeGiftTemplate(),
          let wire = try? copy.encoded(), let decoded = try? FrostGift.decode(wire) else {
        check(false,"restored tree encodes a portable gift"); return false
    }
    check(restored.pieces[1].attachment?.tree == tree.id && close(restored.pieces[1].center.x,turned.center.x),
          "reopening preserves parentage and world position")
    check(decoded.dress.hasPrefix("4,") && decoded.dress.contains("scale,0,1.2000") &&
          decoded.dress.contains("angles,90.0000,0.0000") && close(CGFloat(decoded.size),WorkshopSymbol.forKind(.tree).bounds.height*1.2),
          "gift files preserve the gold bauble, relative position, size and angles")
    check((2...16).allSatisfy { WorkshopKind(giftOrnamentID:$0)?.giftOrnamentID == $0 } &&
          WorkshopKind(giftOrnamentID:1) == nil && WorkshopKind.mitten.giftOrnamentID == nil,
          "all fifteen Windows ornament IDs round-trip")
    restored.arrange();_=restored.down(turned.center);restored.up(turned.center)
    check(command("Detach from tree",in:restored) && restored.pieces[1].attachment == nil &&
          close(restored.pieces[1].scale,1.2) && restored.treeGiftTemplate()?.dress.hasPrefix("angles,") == true,
          "detaching restores standalone size and removes the ornament from outgoing gifts")
    workshop.arrange();_=workshop.down(turned.center);workshop.up(offset(turned.center,100,0))
    check(workshop.pieces[1].attachment == nil && workshop.treeGiftTemplate()?.dress.hasPrefix("angles,") == true,
          "dragging an ornament off its branches removes it from the tree")

    // Compare the delivered parcels after their trains have left the screen.
    // This exercises gift decoding, native art and the actual rendering transform together.
    func deliveredPixels(_ dress: String) -> NSBitmapImageRep? {
        let train = GiftTrain(), area = CGRect(origin:.zero,size:CGSize(width:460,height:260))
        var g = FrostGift(); g.kind = .tree;g.size = 105;g.dress = dress
        var arrived = false
        guard train.start(g,onArrival:{ arrived=true }) else { return nil }
        for _ in 0..<950 { train.step(1.0/30,bounds:area) }
        guard arrived, !train.isMoving else { return nil }
        let canvas = NSImage(size:area.size,flipped:true) { _ in train.draw(in:area);return true }
        return canvas.tiffRepresentation.flatMap { NSBitmapImageRep(data:$0) }
    }
    if let bare=deliveredPixels(""),let decorated=deliveredPixels("4,0,-0.5;scale,0,1.3;angles,0,25"),
       bare.pixelsWide == decorated.pixelsWide, bare.pixelsHigh == decorated.pixelsHigh {
        var different=0
        let displayScale = CGFloat(bare.pixelsWide)/460
        let x=Int((460*0.46-83)*displayScale)
        for py in 0..<bare.pixelsHigh {
            for px in max(0,x-25)..<min(bare.pixelsWide,x+25) {
                guard let c=decorated.colorAt(x:px,y:py)?.usingColorSpace(.deviceRGB),
                      let b=bare.colorAt(x:px,y:py)?.usingColorSpace(.deviceRGB) else { continue }
                if c.redComponent > b.redComponent+0.17 && c.greenComponent > c.blueComponent+0.15 { different += 1 }
            }
        }
        check(different>12,"unpacking a tree paints its golden bauble at the delivery stop")
    } else { check(false,"delivered dressed tree renders to a native bitmap") }
    return ok
}
