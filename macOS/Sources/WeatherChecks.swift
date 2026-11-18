import AppKit

@MainActor func runMacWeatherChecks() -> Bool {
    let suite="io.jakefrost.test.weather."+UUID().uuidString
    guard let settings=UserDefaults(suiteName:suite) else{return false}
    defer {settings.removePersistentDomain(forName:suite)}
    var passed=true, notifications=0
    func check(_ result:Bool,_ message:String) {
        print((result ? "PASS: ":"FAIL: ")+message);if !result {passed=false}
    }
    let controls=MacWeatherControls(settings:settings) {notifications+=1}
    let menu=NSMenu();controls.append(to:menu)
    let choices=menu.item(withTitle:"Weather")?.submenu
    func press(_ item:NSMenuItem?) {
        if let item=item,let action=item.action {_=NSApplication.shared.sendAction(action,to:item.target,from:item)}
    }
    for effect in MacWeatherMode.allCases {
        press(choices?.item(withTitle:effect.rawValue))
        check(controls.mode==effect,"the desktop weather menu selects "+effect.rawValue)
    }
    press(choices?.item(withTitle:"Wind")?.submenu?.items.first(where:{$0.tag == -80}))
    press(choices?.item(withTitle:"Lightning in rain"))
    let copy=MacWeatherControls(settings:settings,onChange:{})
    check(controls.wind == -80 && copy.wind == -80 && copy.lightning && copy.mode == .off,
          "wind, opt-in lightning and weather survive reopening the app")
    let scheduling=choices?.item(withTitle:"Weather schedule")?.submenu
    press(scheduling?.item(withTitle:"Random"))
    let first=controls.mode
    controls.tick(now:Date().addingTimeInterval(16*60))
    check(first != .off && controls.mode != first && controls.mode != .off,"random schedule chooses another effect after fifteen minutes")
    press(scheduling?.item(withTitle:"Match the season"))
    check(controls.schedule == .season && MacWeatherControls.seasonal(month:1,southern:true) == .fireflies &&
          MacWeatherControls.seasonal(month:1,southern:false) == .snow,"seasonal weather follows the selected hemisphere")
    controls.choose(.heavySnow)
    check(controls.schedule == .manual && controls.mode == .heavySnow && notifications>0,"choosing an effect cancels the schedule")
    let point=LocalWeather.coordinates("41.88, -87.63")
    check(point?.0==41.88 && point?.1 == -87.63 && LocalWeather.coordinates("Chicago, IL")==nil &&
          LocalWeather.coordinates("91, 0")==nil,"local weather accepts coordinates and distinguishes city searches")
    check(LocalWeather.effect(code:86)?.0 == .heavySnow && LocalWeather.effect(code:73)?.0 == .snow &&
          LocalWeather.effect(code:95)?.0 == .rain && LocalWeather.effect(code:3)?.0 == .off &&
          LocalWeather.effect(code:123)==nil,"Open-Meteo weather codes map to supported effects")

    let world=SnowWorld()
    world.setDesktop(size:CGSize(width:640,height:300),edges:[
        SnowEdge(id:31,x:0,y:105,width:640,visible:[0...640])])
    let effects=MacWeatherEffects(seed:72022)
    func bitmap()->UInt64 {
        let w=640,h=300
        guard let ctx=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue),
            let data=ctx.data else{return 0}
        ctx.translateBy(x:0,y:CGFloat(h));ctx.scaleBy(x:1,y:-1)
        effects.draw(in:ctx)
        var hash:UInt64=1469598103934665603, painted=false
        let bytes=data.assumingMemoryBound(to:UInt8.self)
        for i in stride(from:0,to:w*h*4,by:4) where bytes[i+3]>4 {
            hash=(hash ^ UInt64(bytes[i]) ^ UInt64(i)) &* 1099511628211
            hash=(hash ^ UInt64(bytes[i+1]) ^ UInt64(bytes[i+2])) &* 1099511628211;painted=true
        }
        return painted ? hash:0
    }
    var outputs=Set<UInt64>()
    for mode in [MacWeatherMode.rain,.sakura,.leaves,.fireflies,.starfall] {
        effects.configure(mode:mode,wind:12,lightning:true,intensity:2)
        for _ in 0..<9 {effects.step(1.0/30,world:world,pointer:nil,paused:false)}
        let rendered=bitmap()
        check(rendered != 0 && outputs.insert(rendered).inserted,mode.rawValue+" draws a distinct visible effect")
        effects.step(1.0/30,world:world,pointer:nil,paused:true)
        check(bitmap()==rendered,mode.rawValue+" freezes on pause")
        var landed=false,storm=false
        for _ in 0..<1200 {
            effects.step(1.0/30,world:world,pointer:nil,paused:false)
            if effects.particles.contains(where:{ $0.splash || $0.rest == 31 }) {landed=true}
            if effects.hasLightning {storm=true}
        }
        if mode != .fireflies {check(landed,mode.rawValue+" lands or breaks on the desktop scene")}
        if mode == .rain {
            check(storm,"opt-in rain draws occasional lightning")
            effects.configure(mode:.rain,wind:0,lightning:false,intensity:0)
            effects.step(1.0/30,world:world,pointer:nil,paused:false)
            check(!effects.hasLightning && !effects.isActive && bitmap()==0,"zero intensity stops emission and disabling lightning clears a strike")
        }
    }
    effects.configure(mode:.off,wind:0,lightning:true,intensity:2)
    effects.step(1.0/30,world:world,pointer:nil,paused:false)
    check(!effects.isActive && effects.particles.isEmpty && bitmap()==0,"Off removes the previous effect")
    return passed
}
