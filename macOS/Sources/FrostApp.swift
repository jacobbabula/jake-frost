import AppKit

@MainActor final class FrostApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let smoke=CommandLine.arguments.contains("--app-smoke-test")
    private static let testMailbox=ProcessInfo.processInfo.environment["JAKE_FROST_TEST_MAILBOX"].map { URL(fileURLWithPath:$0,isDirectory:true) }
    private let settings=FrostApp.smoke || FrostApp.testMailbox != nil ? UserDefaults(suiteName:"io.jakefrost.test."+UUID().uuidString)! : UserDefaults.standard
    private let gifts=MacGifts(mailboxRoot:FrostApp.testMailbox)
    private lazy var weatherControls = MacWeatherControls(settings:settings,onChange:{ [weak self] in self?.applyPreferences() })
    private lazy var visitorControls = MacVisitorControls(settings:settings,summon:{ [weak self] kind in
        guard let self = self, let canvas = self.currentScene?.view else { return }
        if kind == .train { canvas.giftTrain.visit() } else { canvas.visitors.summon(kind,in:canvas.world) }
        canvas.needsDisplay = true; self.startFrames()
    },onChange:{ [weak self] in self?.applyPreferences() })
    private var scenes=[UInt32:ScreenScene]()
    private var previousWindows: [WindowFrame]?
    private var previousScreens = [UInt32:CGRect]()
    private var fullscreenDisplays = Set<UInt32>()
    private var lowPower = false
    private var currentScene: ScreenScene? {
        let mouse = NSEvent.mouseLocation
        if let screen=NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
           let id=displayID(screen), let scene=scenes[id],scene.panel.isVisible { return scene }
        return scenes.values.first { $0.panel.isVisible }
    }
    private var status:NSStatusItem!
    private var timer:Timer?
    private var lastTick=ProcessInfo.processInfo.systemUptime
    private var nextEdges:TimeInterval=0
    private var welcome:AnchoredPanel?
    private var workshopActive = false
    private var receivedDocument=false
    private var awake=true
    private var volume:Int {
        if settings.object(forKey:"snowVolume") != nil {return min(400,max(0,settings.integer(forKey:"snowVolume")))}
        return [45,100,220][min(2,max(0,settings.integer(forKey:"snowfall")))]
    }
    private var windowSnow: Bool { settings.bool(forKey:"windowSnow") }
    private var snowPlay:Bool {settings.bool(forKey:"snowPlay")}
    private var paused:Bool {settings.bool(forKey:"pauseSnow")}

    func applicationDidFinishLaunching(_ note:Notification) {
        settings.register(defaults:["snowfall":1,"snowPlay":true,"pauseSnow":false,"snowDepth":55,"windowSnow":true,"clickPuff":true,"powerSaving":true])
        NSApp.setActivationPolicy(.accessory)
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        if let button=status.button {
            if let image=NSImage(systemSymbolName:"snowflake",accessibilityDescription:"Jake Frost") {
                image.isTemplate=true;button.image=image
            } else {button.title="❄"}
            button.toolTip="Jake Frost"
        }
        let menu=NSMenu(title:"Jake Frost");menu.delegate=self
        fill(menu);status.menu=menu
        synchronizeScreens()
        gifts.localTemplate = { [weak self] kind in
            guard let self=self else{return nil}
            switch kind {
            case .snowman: return self.currentScene?.view.world.latestSnowmanGift ??
                self.scenes.values.lazy.compactMap { $0.view.world.latestSnowmanGift }.first
            case .tree: return self.currentScene?.view.workshop.treeGiftTemplate() ??
                self.scenes.values.lazy.compactMap { $0.view.workshop.treeGiftTemplate() }.first
            case .note: return nil
            }
        }
        gifts.deliver={ [weak self] gift, receipt in
            guard let self=self,self.awake else{return false}
            guard let scene=self.currentScene else{return false}
            return scene.view.giftTrain.start(gift,onArrival:receipt)
        }
        if !FrostApp.smoke {gifts.start()}
        let center=NotificationCenter.default
        center.addObserver(self,selector:#selector(screenChanged),name:NSApplication.didChangeScreenParametersNotification,object:nil)
        let workspace=NSWorkspace.shared.notificationCenter
        for signal in [NSWorkspace.willSleepNotification,NSWorkspace.screensDidSleepNotification,NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(self,selector:#selector(suspend),name:signal,object:nil)
        }
        for signal in [NSWorkspace.didWakeNotification,NSWorkspace.screensDidWakeNotification,NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(self,selector:#selector(resume),name:signal,object:nil)
        }
        startFrames()
        if FrostApp.smoke {
            DispatchQueue.main.asyncAfter(deadline:.now()+1.2) {
                let ready = self.status.button != nil && self.scenes.values.contains {
                    $0.panel.isVisible && $0.panel.screen != nil && !$0.view.world.particles.isEmpty && !$0.view.world.banks.isEmpty
                }
                if ready {print("PASS: native status item, desktop overlay, snowfall and timer on an attached display")}
                else {print("FAIL: native application did not create its desktop overlay")}
                let controls=self.exerciseMenu()
                print((controls ? "PASS: " : "FAIL: ")+"menu actions change real weather, window ice, depth, display layer and pause")
                exit(ready && controls ? 0 : 1)
            }
        } else if !settings.bool(forKey:"welcomed") {
            DispatchQueue.main.asyncAfter(deadline:.now()+0.4) { [weak self] in
                guard let self=self,!self.receivedDocument else{return}
                self.showWelcome()
            }
        }
    }
    func application(_ sender:NSApplication,open urls:[URL]) {
        receivedDocument=true;welcome?.close();gifts.open(urls)
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {
        showWelcome();return true
    }
    func applicationWillTerminate(_ note:Notification) {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        for scene in scenes.values {scene.view.world.rememberSnowmenNow();scene.panel.orderOut(nil)}
    }
    private func startFrames() {
        guard awake else{return}
        let active = scenes.values.contains { $0.panel.isVisible && ($0.view.animating || $0.view.workshop.editing) }
        let interval:TimeInterval = active ? (lowPower ? 1/18 : 1/30) : 1/12
        if let timer=timer, timer.timeInterval==interval { return }
        timer?.invalidate()
        lastTick=ProcessInfo.processInfo.systemUptime
        let t=Timer(timeInterval:interval,target:self,selector:#selector(frame(_:)),userInfo:nil,repeats:true)
        t.tolerance = interval * 0.1
        RunLoop.main.add(t,forMode:.common);timer=t
    }
    @objc private func suspend() {
        awake=false;timer?.invalidate();timer=nil
        for scene in scenes.values {scene.view.workshop.cancelGesture();scene.view.releasePointer()}
    }
    @objc private func resume() {awake=true;synchronizeScreens();startFrames()}
    @objc private func screenChanged() {synchronizeScreens()}
    private func synchronizeScreens() {
        let screens=NSScreen.screens
        let current=Set(screens.compactMap { displayID($0) })
        var interrupted=false
        for id in Array(scenes.keys) where !current.contains(id) {
            if let scene=scenes.removeValue(forKey:id) {
                scene.view.world.rememberSnowmenNow()
                previousScreens.removeValue(forKey:id)
                if scene.view.giftTrain.cancel(){interrupted=true}
                scene.view.releasePointer();scene.panel.close()
            }
        }
        for screen in screens {
            guard let id=displayID(screen) else{continue}
            let frame=screen.visibleFrame
            if let existing=scenes[id] {existing.panel.setFrame(frame,display:true)}
            else {
                let scene=ScreenScene(frame:frame)
                scene.view.world.configureSnowmanStorage(settings:settings,displayID:id)
                let workshop=scene.view.workshop
                workshop.configure(settings:settings,displayID:id)
                workshop.onEditingChanged = { [weak self,weak workshop] in
                    self?.updateWorkshopPanels(toolSelected:workshop?.editing == true)
                }
                scenes[id]=scene
            }
        }
        applyPreferences();updateEdges()
        updateWorkshopPanels()
        if interrupted {gifts.retryUndelivered()}
    }
    private func displayID(_ screen:NSScreen)->UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
    private func updateWorkshopPanels(toolSelected:Bool = false) {
        let editing = scenes.values.contains { $0.view.workshop.editing }
        guard workshopActive != editing || toolSelected else { return }
        workshopActive = editing
        welcome?.setWorkshopEditing(editing)
        gifts.setWorkshopEditing(editing)
    }
    private func updateEdges(){
        guard let primary=NSScreen.screens.first else{return}
        lowPower=settings.bool(forKey:"powerSaving") && ProcessInfo.processInfo.isLowPowerModeEnabled
        let pauseFullscreen=settings.bool(forKey:"pauseFullscreen")
        let windows=windowSnow || pauseFullscreen ? DesktopEdges.windows() : []
        var covered=Set<UInt32>()
        if pauseFullscreen {
            for screen in NSScreen.screens {
                let f=screen.frame, bounds=CGRect(x:f.minX,y:primary.frame.maxY-f.maxY,width:f.width,height:f.height)
                if let id=displayID(screen),DesktopEdges.isFullscreen(windows,on:bounds) {covered.insert(id)}
            }
        }
        if covered != fullscreenDisplays {fullscreenDisplays=covered;updatePanelVisibility()}
        let windowsChanged = windows != previousWindows
        previousWindows = windows
        for (id,scene) in scenes where scene.panel.isVisible {
            let frame=scene.panel.frame
            let quartz=CGRect(x:frame.minX,y:primary.frame.maxY-frame.maxY,width:frame.width,height:frame.height)
            guard windowsChanged || previousScreens[id] != quartz else { continue }
            previousScreens[id] = quartz
            scene.view.world.setDesktop(size:frame.size,edges:windowSnow ? DesktopEdges.visible(windows,in:quartz) : [])
            scene.view.workshop.sync(world:scene.view.world)
            scene.view.needsDisplay=true
        }
    }
    @objc private func frame(_ timer:Timer) {
        let now=ProcessInfo.processInfo.systemUptime,dt=now-lastTick
        lastTick=now
        if now>=nextEdges {
            weatherControls.tick();updateEdges()
            visitorControls.scheduledVisits(allow:weatherControls.mode.isSnow && !paused && !workshopActive)
            nextEdges=now+0.45
        }
        let mouse=NSEvent.mouseLocation
        for scene in scenes.values where scene.panel.isVisible {scene.view.frameTick(dt,cursor:mouse)}
        startFrames()
    }
    private func updatePanelVisibility(){
        let chosen=settings.integer(forKey:"onlyDisplay")
        let restrict=chosen>0 && scenes.keys.contains { Int($0)==chosen }
        var interrupted=false
        for (id,s) in scenes {
            let visible = (!restrict || chosen==Int(id)) && !fullscreenDisplays.contains(id)
            if s.panel.isVisible != visible {
                if visible {s.panel.orderFrontRegardless();previousScreens.removeValue(forKey:id)}
                else {
                    if s.view.giftTrain.cancel(){interrupted=true}
                    s.view.workshop.finishEditing();s.view.releasePointer();s.panel.orderOut(nil)
                }
            }
        }
        if interrupted {gifts.retryUndelivered()}
    }
    private func applyPreferences(){
        updatePanelVisibility()
        let intensity=CGFloat(volume)/100
        for s in scenes.values {
            let level:NSWindow.Level = settings.bool(forKey:"behindWindows") ?
                NSWindow.Level(rawValue:Int(CGWindowLevelForKey(.desktopIconWindow))+1) : .floating
            if s.panel.level != level {s.panel.level=level}
            s.view.world.amount=intensity*(weatherControls.mode == .heavySnow ? 1.7 : 1)
            s.view.world.snowEnabled=weatherControls.mode.isSnow
            s.view.world.wind=weatherControls.wind
            s.view.world.setAccumulation(CGFloat(settings.integer(forKey:"snowDepth")))
            s.view.iceLevel=settings.integer(forKey:"windowIce")
            s.view.weatherEffects.configure(mode:weatherControls.mode,wind:weatherControls.wind,lightning:weatherControls.lightning,intensity:intensity)
            s.view.world.paused=paused;s.view.allowTouch=snowPlay
            s.view.puffFallingSnow=settings.bool(forKey:"clickPuff")
            s.view.visitors.configure(visitorControls);s.view.giftTrain.configure(visitorControls)
            if !snowPlay {s.view.releasePointer()}
            s.view.needsDisplay=true
        }
    }
    private func item(_ title:String,_ action:Selector,_ menu:NSMenu)->NSMenuItem {
        let i=NSMenuItem(title:title,action:action,keyEquivalent:"");i.target=self;menu.addItem(i);return i
    }
    private func fill(_ menu:NSMenu) {
        menu.removeAllItems()
        weatherControls.append(to:menu)
        let snow = NSMenu(title:"Snow and windows")
        menu.addItem(withTitle:snow.title,action:nil,keyEquivalent:"").submenu=snow
        func choices(_ title:String,_ key:String,_ values:[(Int,String)],_ current:Int) {
            let list=NSMenu(title:title)
            snow.addItem(withTitle:title,action:nil,keyEquivalent:"").submenu=list
            for (value,label) in values {
                let entry=item(label,#selector(setPreference(_:)),list)
                entry.tag=value;entry.representedObject=key;entry.state=value==current ? .on:.off
            }
        }
        choices("Weather volume","snowVolume",[0,25,45,75,100,150,220,300,400].map {($0,"\($0)%")},volume)
        choices("Accumulation depth","snowDepth",[24,40,55,80,110,140].map {($0,"\($0) pt")},settings.integer(forKey:"snowDepth"))
        choices("Window ice","windowIce",[(0,"Off"),(1,"Light frost"),(2,"Icicles"),(3,"Heavy ice")],settings.integer(forKey:"windowIce"))
        choices("Show effects on","onlyDisplay",[(0,"All displays")]+NSScreen.screens.compactMap { screen in
            guard let id=displayID(screen) else {return nil};return (Int(id),screen.localizedName)
        },settings.integer(forKey:"onlyDisplay"))
        let edges=item("Collect snow on window edges",#selector(toggleWindows),snow);edges.state=windowSnow ? .on:.off
        let layer=item("Show behind windows",#selector(toggleLayer),snow);layer.state=settings.bool(forKey:"behindWindows") ? .on:.off
        for (key,label) in [("pauseFullscreen","Pause over fullscreen apps"),("powerSaving","Reduce animation in Low Power Mode"),("clickPuff","Puff falling flakes on click")] {
            let entry=item(label,#selector(toggleOption(_:)),snow);entry.representedObject=key
            entry.state=settings.bool(forKey:key) ? .on:.off
        }
        let remember=item("Remember decorations and snowmen",#selector(toggleMemory),snow)
        remember.state=MacSceneMemory.remembers(settings) ? .on:.off
        _=item(paused ? "Resume weather" : "Pause weather",#selector(togglePause),menu)
        let play=item("Grab and throw snow",#selector(togglePlay),menu);play.state=snowPlay ? .on : .off
        _=item("Clear scene",#selector(clearScene),menu)
        menu.addItem(.separator())
        currentScene?.view.workshop.appendMenu(to:menu)
        visitorControls.append(to:menu)
        menu.addItem(.separator());gifts.appendCommands(to:menu)
        menu.addItem(.separator());_=item("How to play",#selector(showWelcome),menu)
        let quit=item("Quit Jake Frost",#selector(quitApp),menu);quit.keyEquivalent="q"
    }
    func menuNeedsUpdate(_ menu:NSMenu){fill(menu)}
    /// Exercise the shipping menu in the isolated --app-smoke-test settings suite.
    private func exerciseMenu() -> Bool {
        guard let scene=currentScene,let menu=status.menu else{return false}
        fill(menu)
        func choose(_ names:String...) -> Bool {
            var current:NSMenu?=menu,entry:NSMenuItem?
            for name in names {entry=current?.item(withTitle:name);current=entry?.submenu}
            guard let item=entry,let action=item.action else{return false}
            return NSApp.sendAction(action,to:item.target,from:item)
        }
        guard choose("Weather","Rain"),!scene.view.world.snowEnabled,scene.view.weatherEffects.mode == .rain,
              choose("Weather","Heavy snow"),scene.view.world.snowEnabled,scene.view.world.amount>1,
              choose("Snow and windows","Weather volume","300%"),scene.view.world.amount>5,
              choose("Snow and windows","Window ice","Heavy ice"),scene.view.iceLevel==3,
              choose("Snow and windows","Accumulation depth","110 pt"),scene.view.world.depthLimit==110,
              choose("Snow and windows","Show behind windows"),scene.panel.level.rawValue<NSWindow.Level.normal.rawValue,
              choose("Pause weather"),scene.view.world.paused else{return false}
        return true
    }
    @objc private func setPreference(_ item:NSMenuItem){
        guard let key=item.representedObject as? String else {return}
        settings.set(item.tag,forKey:key);applyPreferences()
        if key == "onlyDisplay" {updateEdges()}
    }
    @objc private func toggleWindows(){settings.set(!windowSnow,forKey:"windowSnow");previousWindows=nil;updateEdges()}
    @objc private func toggleLayer(){settings.set(!settings.bool(forKey:"behindWindows"),forKey:"behindWindows");applyPreferences()}
    @objc private func toggleOption(_ item:NSMenuItem){
        guard let key=item.representedObject as? String else {return}
        settings.set(!settings.bool(forKey:key),forKey:key);applyPreferences();updateEdges()
    }
    @objc private func toggleMemory(){
        MacSceneMemory.setRemember(!MacSceneMemory.remembers(settings),settings:settings)
        for s in scenes.values {s.view.world.rememberSnowmenNow();s.view.workshop.rememberLayoutNow()}
    }
    @objc private func togglePause(){settings.set(!paused,forKey:"pauseSnow");applyPreferences()}
    @objc private func togglePlay(){settings.set(!snowPlay,forKey:"snowPlay");applyPreferences()}
    @objc private func clearScene(){
        var interrupted=false
        for s in scenes.values {
            s.view.world.clear();s.view.weatherEffects.clear();s.view.workshop.clear();s.view.visitors.clear();s.view.releasePointer()
            if s.view.giftTrain.clear(){interrupted=true}
            s.view.needsDisplay = true
        }
        if interrupted {gifts.retryUndelivered()}
    }
    @objc private func quitApp(){NSApp.terminate(nil)}
    @objc private func showWelcome() {
        settings.set(true,forKey:"welcomed")
        if let panel=welcome {NSApp.activate(ignoringOtherApps:true);panel.expand();panel.makeKeyAndOrderFront(nil);return}
        let panel=AnchoredPanel(contentRect:CGRect(x:0,y:0,width:380,height:190),title:"Jake Frost")
        let header=NSTextField(labelWithString:"Play in the snow")
        header.font = .systemFont(ofSize:20,weight:.semibold)
        let body=NSTextField(wrappingLabelWithString:"Grab snow above the Dock or on a window edge. Drag to roll a ball, then flick to throw it. Gently stack three balls to build a snowman.\n\nOpen the menu bar snowflake to send a gift, change the weather or decorate your desktop.")
        body.preferredMaxLayoutWidth=335
        let done=NSButton(title:"Got it",target:self,action:#selector(closeWelcome))
        done.keyEquivalent="\r";done.bezelStyle = .rounded
        let stack=NSStackView(views:[header,body,done]);stack.orientation = .vertical;stack.alignment = .leading
        stack.spacing=10;stack.translatesAutoresizingMaskIntoConstraints=false
        if let content=panel.contentView {
            content.addSubview(stack)
            NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:20),stack.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-20),stack.centerYAnchor.constraint(equalTo:content.centerYAnchor)])
        }
        welcome=panel;panel.center();NSApp.activate(ignoringOtherApps:true);panel.makeKeyAndOrderFront(nil)
    }
    @objc private func closeWelcome(){welcome?.close()}
}

@main enum FrostEntry {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--scene-self-test") {exit(runSceneTests() ? 0 : 1)}
        let app=NSApplication.shared
        let delegate=FrostApp()
        app.delegate=delegate
        withExtendedLifetime(delegate){app.run()}
    }
}
