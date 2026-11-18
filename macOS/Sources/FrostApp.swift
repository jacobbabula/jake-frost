import AppKit

@MainActor final class FrostApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let smoke=CommandLine.arguments.contains("--app-smoke-test")
    private static let testMailbox=ProcessInfo.processInfo.environment["JAKE_FROST_TEST_MAILBOX"].map { URL(fileURLWithPath:$0,isDirectory:true) }
    private let settings=FrostApp.smoke || FrostApp.testMailbox != nil ? UserDefaults(suiteName:"io.jakefrost.test."+UUID().uuidString)! : UserDefaults.standard
    private let gifts=MacGifts(mailboxRoot:FrostApp.testMailbox)
    private lazy var visitorControls = MacVisitorControls(settings:settings,summon:{ [weak self] kind in
        guard let self = self, let canvas = self.currentScene?.view else { return }
        if kind == .train { canvas.giftTrain.visit() } else { canvas.visitors.summon(kind,in:canvas.world) }
        canvas.needsDisplay = true; self.startFrames()
    },onChange:{ [weak self] in self?.applyPreferences() })
    private var scenes=[UInt32:ScreenScene]()
    private var previousWindows: [WindowFrame]?
    private var previousScreens = [UInt32:CGRect]()
    private var currentScene: ScreenScene? {
        let mouse = NSEvent.mouseLocation
        if let screen=NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
           let id=displayID(screen), let scene=scenes[id] { return scene }
        return scenes.values.first
    }
    private var status:NSStatusItem!
    private var timer:Timer?
    private var lastTick=ProcessInfo.processInfo.systemUptime
    private var nextEdges:TimeInterval=0
    private var welcome:AnchoredPanel?
    private var workshopActive = false
    private var receivedDocument=false
    private var awake=true
    private var snowfall:Int {settings.integer(forKey:"snowfall")}
    private var snowPlay:Bool {settings.bool(forKey:"snowPlay")}
    private var paused:Bool {settings.bool(forKey:"pauseSnow")}

    func applicationDidFinishLaunching(_ note:Notification) {
        settings.register(defaults:["snowfall":1,"snowPlay":true,"pauseSnow":false])
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
        gifts.deliver={ [weak self] gift, receipt in
            guard let self=self,self.awake else{return false}
            let mouse=NSEvent.mouseLocation
            guard let scene=self.scenes.values.first(where: { $0.panel.frame.contains(mouse) }) ?? self.scenes.values.first else{return false}
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
                exit(ready ? 0 : 1)
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
        for scene in scenes.values {scene.panel.orderOut(nil)}
    }
    private func startFrames() {
        guard awake else{return}
        let interval: TimeInterval = scenes.values.contains { $0.view.animating || $0.view.workshop.editing } ? 1/30 : 1/12
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
        let windows=DesktopEdges.windows()
        let windowsChanged = windows != previousWindows
        previousWindows = windows
        for (id,scene) in scenes {
            let frame=scene.panel.frame
            let quartz=CGRect(x:frame.minX,y:primary.frame.maxY-frame.maxY,width:frame.width,height:frame.height)
            guard windowsChanged || previousScreens[id] != quartz else { continue }
            previousScreens[id] = quartz
            scene.view.world.setDesktop(size:frame.size,edges:DesktopEdges.visible(windows,in:quartz))
            scene.view.workshop.sync(world:scene.view.world)
            scene.view.needsDisplay=true
        }
    }
    @objc private func frame(_ timer:Timer) {
        let now=ProcessInfo.processInfo.systemUptime,dt=now-lastTick
        lastTick=now;if now>=nextEdges {updateEdges();nextEdges=now+0.45}
        let mouse=NSEvent.mouseLocation
        for scene in scenes.values {scene.view.frameTick(dt,cursor:mouse)}
        startFrames()
    }
    private func applyPreferences(){
        let amounts:[CGFloat]=[0.45,1,2.2]
        for s in scenes.values {
            s.view.world.amount=amounts[min(2,max(0,snowfall))]
            s.view.world.paused=paused;s.view.allowTouch=snowPlay
            s.view.visitors.configure(visitorControls);s.view.giftTrain.configure(visitorControls)
            if !snowPlay {s.view.releasePointer()}
        }
    }
    private func item(_ title:String,_ action:Selector,_ menu:NSMenu)->NSMenuItem {
        let i=NSMenuItem(title:title,action:action,keyEquivalent:"");i.target=self;menu.addItem(i);return i
    }
    private func fill(_ menu:NSMenu) {
        menu.removeAllItems()
        let weather=NSMenuItem(title:"Snowfall",action:nil,keyEquivalent:"")
        let amounts=NSMenu(title:"Snowfall")
        for (i,name) in ["Light","Steady","Heavy"].enumerated(){
            let option=item(name,#selector(setSnow(_:)),amounts);option.tag=i;option.state=i==snowfall ? .on : .off
        }
        weather.submenu=amounts;menu.addItem(weather)
        _=item(paused ? "Resume snowfall" : "Pause snowfall",#selector(togglePause),menu)
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
    @objc private func setSnow(_ item:NSMenuItem){settings.set(item.tag,forKey:"snowfall");applyPreferences()}
    @objc private func togglePause(){settings.set(!paused,forKey:"pauseSnow");applyPreferences()}
    @objc private func togglePlay(){settings.set(!snowPlay,forKey:"snowPlay");applyPreferences()}
    @objc private func clearScene(){
        var interrupted=false
        for s in scenes.values {
            s.view.world.clear();s.view.workshop.clear();s.view.visitors.clear();s.view.releasePointer()
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
        let header=NSTextField(labelWithString:"Snow is falling on your Mac.")
        header.font = .systemFont(ofSize:20,weight:.semibold)
        let body=NSTextField(wrappingLabelWithString:"Grab a drift above the Dock or on a window edge. Drag to roll a snowball. Flick and release to throw it.\n\nUse the snowflake in the menu bar to send a gift, change the snowfall, or quit.")
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
