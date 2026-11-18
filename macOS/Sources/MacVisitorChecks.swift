import AppKit

@MainActor func runMacVisitorChecks() -> Bool {
    let suite = "io.jakefrost.test.visitors." + UUID().uuidString
    guard let prefs = UserDefaults(suiteName:suite) else { return false }
    defer { prefs.removePersistentDomain(forName:suite) }
    var passed = true
    func check(_ truth:Bool,_ message:String) {
        if !truth { passed = false }
        print((truth ? "PASS: " : "FAIL: ") + message)
    }
    var summons = [MacVisitorKind](), changeCount = 0
    let controls = MacVisitorControls(settings:prefs, summon:{ summons.append($0) }, onChange:{ changeCount += 1 })
    let menu = NSMenu(); controls.append(to:menu)
    let visitorMenu = menu.item(withTitle:"Visitors")?.submenu
    func press(_ item:NSMenuItem?) -> Bool {
        guard let item = item, let action = item.action else { return false }
        return NSApplication.shared.sendAction(action,to:item.target,from:item)
    }
    for kind in MacVisitorKind.allCases {
        _ = press(visitorMenu?.item(withTitle:"Send " + kind.rawValue))
    }
    check(summons == MacVisitorKind.allCases,"every visitor can be sent from the menu")
    let testSize = CGSize(width:360,height:160)
    func makeWorld() -> SnowWorld {
        let world = SnowWorld(); world.setDesktop(size:testSize,edges:[]); world.clear()
        return world
    }
    func raster(_ visitors:MacVisitors) -> (count:Int,center:CGFloat) {
        let w=Int(testSize.width), h=Int(testSize.height)
        guard let c = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
            space:CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
            let data = c.data else { return (0,0) }
        c.translateBy(x:0,y:CGFloat(h)); c.scaleBy(x:1,y:-1)
        visitors.draw(in:c)
        let pixels = data.assumingMemoryBound(to:UInt8.self)
        var count=0, sum=0
        for y in 0..<h {
            for x in 0..<w where pixels[4*(y*w+x)+3]>140 { count += 1; sum += x }
        }
        return (count, CGFloat(sum)/CGFloat(max(count,1)))
    }
    func sample(_ kind:MacVisitorKind) -> (count:Int,center:CGFloat) {
        let world=makeWorld(), visitors=MacVisitors()
        visitors.configure(controls); visitors.summon(kind,in:world)
        for _ in 0..<120 { visitors.step(1.0/30,world:world) }
        return raster(visitors)
    }
    for kind in MacVisitorKind.allCases where kind != .train {
        check(sample(kind).count > 180,"\(kind.rawValue) paints a visible desktop sprite")
    }
    let before = sample(.yeti)
    let sizes=visitorMenu?.item(withTitle:"Visitor sizes")?.submenu
    let speeds=visitorMenu?.item(withTitle:"Visitor speeds")?.submenu
    _ = press(sizes?.item(withTitle:"Yeti")?.submenu?.item(withTitle:"200%"))
    let after = sample(.yeti)
    _ = press(speeds?.item(withTitle:"Yeti")?.submenu?.item(withTitle:"Brisk"))
    let fast = sample(.yeti)
    check(changeCount == 2 && after.count > 3*before.count && fast.center > after.center+70,
          "independent size and pace controls change the visitor drawn on screen")
    let restored = MacVisitorControls(settings:prefs,summon:{_ in},onChange:{})
    check(restored.scale(for:.yeti) == 2 && restored.pace(for:.yeti)>1.9 && restored.scale(for:.santa) == 1,
          "visitor preferences survive reopening and preserve other visitors")

    let world=makeWorld(), visitors=MacVisitors()
    guard let floor = world.banks.first else { return false }
    for x in stride(from:CGFloat(0),to:world.size.width,by:10) { floor.add(at:x,amount:14,spread:0) }
    let depth = floor.height(65)
    visitors.summon(.snowplow,in:world)
    for _ in 0..<136 { visitors.step(1.0/30,world:world) }
    check(floor.height(65) < depth*0.4 && world.particles.contains(where:{ $0.powder }),
          "snowplow cuts a trail through the drift and throws powder")
    for _ in 0..<280 { visitors.step(1.0/30,world:world) }
    check(!visitors.isActive,"a departed snowplow releases its animation state")
    visitors.summon(.santa,in:world); visitors.clear()
    check(!visitors.isActive,"clear removes active visitors")

    let train=GiftTrain(), area=CGRect(origin:.zero,size:testSize)
    train.configure(controls); train.visit()
    check(train.isMoving && !train.cancel(),"an elf visit can be interrupted without a gift receipt")
    train.visit()
    for _ in 0..<300 { train.step(1.0/30,bounds:area) }
    check(!train.hasActivity && !train.isMoving,"a local elf visit leaves the desktop without a parcel")
    return passed
}
