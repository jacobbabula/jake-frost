import AppKit

/// Exercise the same compositor, saved settings and weather simulation as the menu bar app.
@MainActor func runMacAtmosphereChecks() -> Bool {
    _=NSApplication.shared
    var passed=true
    func check(_ result:Bool,_ message:String) { print((result ? "PASS: ":"FAIL: ")+message);passed = passed && result }
    let world=SnowWorld(), sky=MacSky()
    let size=CGSize(width:720,height:400)
    world.setDesktop(size:size,edges:[SnowEdge(id:61,x:100,y:160,width:460,visible:[100...560])])
    let floorBefore=world.banks[0].depth.reduce(0,+)
    var visits=[CGFloat](), ends=0
    func step(){sky.step(1.0/30,world:world,clouds:true,wind:0,sendYeti:{visits.append($0)},ended:{ends+=1})}
    func paint()->Data? {
        guard let c=CGContext(data:nil,width:720,height:400,bitsPerComponent:8,bytesPerRow:720*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return nil}
        sky.draw(in:c,size:size,intensity:1);sky.drawForeground(in:c)
        guard let image=c.makeImage() else{return nil}
        return NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])
    }
    let cloud=paint()
    for _ in 0..<90 {step()}
    check(cloud != nil && paint() != cloud,"clouds drift between frames")
    sky.startStorm();world.paused=true
    for _ in 0..<40 {step()}
    check(sky.inBlizzard && sky.snowCount==0 && visits.isEmpty,"a paused blizzard waits for play to resume")
    world.paused=false
    for _ in 0..<150 {step()}
    check(sky.strength>0.5 && sky.snowCount>=80 && paint() != cloud,"blizzard fills the foreground and background with blowing powder")
    for _ in 0..<530 {step()}
    check(!sky.inBlizzard && sky.snowCount==0 && ends==1 && Set(visits)==Set([CGFloat(-1),CGFloat(1)]),
          "the 22-second storm sends running Yetis from both directions and ends")
    check(world.banks[0].depth.reduce(0,+)>floorBefore && world.banks[1].depth.reduce(0,+)>0,
          "storm snow remains on the desktop and window ledges")

    let screens=NSScreen.screens
    guard let screen=screens.first,let id=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else{return false}
    let original=NSWorkspace.shared.desktopImageURL(for:screen)
    let suite="io.jakefrost.test.wallpapers."+UUID().uuidString
    guard let settings=UserDefaults(suiteName:suite) else{return false}
    defer {settings.removePersistentDomain(forName:suite)}
    let wallpaper=MacWallpapers(settings:settings,onChange:{})
    defer {wallpaper.sync([],enabled:[])}
    let menu=NSMenu();wallpaper.append(to:menu)
    let choices=menu.item(withTitle:"Desktop wallpaper")?.submenu
    func select(_ item:NSMenuItem?) {
        if let item=item,let action=item.action {_=NSApp.sendAction(action,to:item.target,from:item)}
        wallpaper.sync(screens,enabled:[id])
    }
    func image(_ filename:String)->Data? {
        guard let rep=wallpaper.snapshot(),let data=rep.representation(using:.png,properties:[:]) else{return nil}
        var colors=Set<Int>()
        for y in stride(from:0,to:rep.pixelsHigh,by:23) {for x in stride(from:0,to:rep.pixelsWide,by:23) {
            if let c=rep.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB),c.alphaComponent>0.8 {
                colors.insert(Int(c.redComponent*31)*1024+Int(c.greenComponent*31)*32+Int(c.blueComponent*31))
            }
        }}
        guard colors.count>24 else{return nil}
        if let directory=ProcessInfo.processInfo.environment["JAKEFROST_MAC_GALLERY"] {
            let url=URL(fileURLWithPath:directory,isDirectory:true)
            do {try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);try data.write(to:url.appendingPathComponent(filename))}
            catch {check(false,"could not export "+filename)}
        }
        return data
    }
    var previous:Data?
    for scene in [MacLandscape.switchback,.lantern] {
        select(choices?.item(withTitle:scene.rawValue))
        select(choices?.item(withTitle:"Lighting")?.submenu?.item(withTitle:"Midday"))
        let day=image(scene.resource+"-day.png")
        select(choices?.item(withTitle:"Lighting")?.submenu?.item(withTitle:"Night"))
        let night=image(scene.resource+"-night.png")
        check(wallpaper.activeScreens==1 && wallpaper.hasDesktopLayer && day != nil && night != nil && day != night && previous != day,
              scene.rawValue+" paints distinct day and night artwork below Mac desktop icons")
        previous=day
    }
    let snapshot1=wallpaper.snapshot()?.representation(using:.png,properties:[:])
    for _ in 0..<40 {wallpaper.tick(0.1,paused:false,lowPower:false)}
    let snapshot2=wallpaper.snapshot()?.representation(using:.png,properties:[:])
    check(snapshot1 != snapshot2,"the lighthouse, water and stars animate on the wallpaper")
    select(choices?.item(withTitle:"Animate wallpaper"))
    let frozen=wallpaper.snapshot()?.representation(using:.png,properties:[:])
    for _ in 0..<40 {wallpaper.tick(0.1,paused:false,lowPower:false)}
    let saved=MacWallpapers(settings:settings,onChange:{})
    check(frozen != nil && frozen==wallpaper.snapshot()?.representation(using:.png,properties:[:]) && !saved.motionEnabled &&
          saved.lighting == .night && saved.scene == .lantern,"turning motion off freezes the painting and preserves the selection")
    select(choices?.item(withTitle:"System wallpaper"))
    check(wallpaper.activeScreens==0 && NSWorkspace.shared.desktopImageURL(for:screen)==original,
          "system wallpaper selection closes the native desktop surface and preserves the user's desktop picture")
    return passed
}
