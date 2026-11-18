import AppKit

/// Commands resolve against the shipping menu each time. A changed display, selected
/// decoration or newly received gift therefore uses the same target as the menu bar.
@MainActor final class MacStudio: NSObject {
    private let menu: () -> NSMenu
    let panel = AnchoredPanel(contentRect:NSRect(x:0,y:0,width:440,height:416),title:"Jake Frost")
    private let tabs = NSSegmentedControl(labels:["Scene","Play","Decorate","Friends"],trackingMode:.selectOne,target:nil,action:nil)
    private let body = NSStackView()
    private let status = NSTextField(labelWithString:"")
    private let snowBlue = NSColor(calibratedRed:0.13,green:0.39,blue:0.56,alpha:1)

    init(menu: @escaping () -> NSMenu) {
        self.menu = menu
        super.init()
        panel.appearance = NSAppearance(named:.aqua)
        panel.backgroundColor = .white
        panel.hidesOnDeactivate = false
        guard let root=panel.contentView else{return}
        let mark=NSImageView()
        mark.image = NSImage(systemSymbolName:"snowflake",accessibilityDescription:nil)
        mark.symbolConfiguration = NSImage.SymbolConfiguration(pointSize:30,weight:.regular)
        mark.contentTintColor=snowBlue
        let title = NSTextField(labelWithString:"Jake Frost")
        title.font = .systemFont(ofSize:25,weight:.semibold)
        title.textColor = NSColor(calibratedRed:0.09,green:0.20,blue:0.28,alpha:1)
        status.font = .systemFont(ofSize:11,weight:.medium);status.textColor = snowBlue
        let identity=NSStackView(views:[title,status])
        identity.orientation = .vertical;identity.alignment = .leading;identity.spacing=1
        let header=NSStackView(views:[mark,identity]);header.orientation = .horizontal;header.spacing=11
        for view in [header,tabs,body] { view.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(view) }
        tabs.selectedSegment=0;tabs.target=self;tabs.action=#selector(refresh);tabs.segmentStyle = .rounded
        tabs.segmentDistribution = .fillEqually
        body.orientation = .vertical;body.alignment = .leading;body.spacing=10
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant:39),
            header.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:20),
            header.topAnchor.constraint(equalTo:root.topAnchor,constant:16),
            tabs.topAnchor.constraint(equalTo:header.bottomAnchor,constant:15),
            tabs.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:18),
            tabs.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-18),
            body.topAnchor.constraint(equalTo:tabs.bottomAnchor,constant:16),
            body.leadingAnchor.constraint(equalTo:tabs.leadingAnchor),
            body.trailingAnchor.constraint(equalTo:tabs.trailingAnchor)
        ])
        panel.center()
        let help=Command();help.title="How to play";help.path=["How to play"];help.bezelStyle = .inline
        help.target=self;help.action=#selector(activate(_:));help.contentTintColor=snowBlue
        help.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(help)
        NSLayoutConstraint.activate([help.trailingAnchor.constraint(equalTo:tabs.trailingAnchor),
                                     help.centerYAnchor.constraint(equalTo:header.centerYAnchor)])
        NotificationCenter.default.addObserver(self,selector:#selector(focused(_:)),name:NSWindow.didBecomeKeyNotification,object:panel)
    }
    @objc private func focused(_ notice:Notification){refresh()}
    func show() {
        panel.expand();refresh()
        NSApp.activate(ignoringOtherApps:true);panel.makeKeyAndOrderFront(nil)
    }
    func close(){panel.close()}
    func setWorkshopEditing(_ editing: Bool){panel.setWorkshopEditing(editing)}
    func captureGalleryIfRequested() -> Bool {
        guard let output=ProcessInfo.processInfo.environment["JAKEFROST_MAC_GALLERY"] else{return true}
        guard let view=panel.contentView,!panel.isCollapsed else{return false}
        let directory=URL(fileURLWithPath:output,isDirectory:true),previous=tabs.selectedSegment
        defer {tabs.selectedSegment=previous;refresh()}
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            for (i,name) in ["scene","play","decorate","friends"].enumerated() {
                tabs.selectedSegment=i;refresh();view.layoutSubtreeIfNeeded();panel.displayIfNeeded()
                guard let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{return false}
                view.cacheDisplay(in:view.bounds,to:rep)
                guard let png=rep.representation(using:.png,properties:[:]) else{return false}
                try png.write(to:directory.appendingPathComponent("studio-"+name+".png"))
            }
        } catch {print("FAIL: studio capture \(error)");return false}
        return true
    }

    private final class Command: NSButton {
        var path: [String] = []
    }
    private func item(_ path:[String],in root:NSMenu)->NSMenuItem? {
        var current:NSMenu?=root,result:NSMenuItem?
        for key in path { result=current?.item(withTitle:key);current=result?.submenu }
        return result
    }
    private func selected(_ options:NSMenu?) -> String? {
        options?.items.first(where:{$0.state == .on && !$0.isSeparatorItem})?.title
    }
    private func label(_ name:String) {
        let heading=NSTextField(labelWithString:name)
        heading.font = .systemFont(ofSize:13,weight:.semibold)
        heading.textColor = NSColor(calibratedRed:0.14,green:0.24,blue:0.31,alpha:1)
        body.addArrangedSubview(heading)
    }
    // Two equally sized controls per row keep every tab usable at the same panel size.
    private func row(_ buttons:Command...) {
        let stack=NSStackView(views:buttons)
        stack.spacing=8;stack.orientation = .horizontal;stack.distribution = .fillEqually
        body.addArrangedSubview(stack);stack.widthAnchor.constraint(equalTo:body.widthAnchor).isActive=true
    }
    private func button(_ title:String,_ icon:String,_ path:[String],in root:NSMenu)->Command {
        let control=Command()
        let entry=item(path,in:root)
        control.path=path;control.title=title
        control.target=self;control.action=#selector(activate(_:))
        control.bezelStyle = .rounded;control.controlSize = .large
        control.image=NSImage(systemSymbolName:icon,accessibilityDescription:nil)
        control.imagePosition = .imageLeading;control.imageScaling = .scaleProportionallyDown
        control.font = .systemFont(ofSize:12,weight:.medium);control.contentTintColor=snowBlue
        control.isEnabled=entry?.isEnabled == true
        control.toolTip=selected(entry?.submenu) ?? entry?.title
        control.setAccessibilityLabel(title)
        control.heightAnchor.constraint(equalToConstant:32).isActive=true
        return control
    }
    @objc private func refresh() {
        guard !panel.isCollapsed else{return}
        let root=menu()
        let weather=selected(root.item(withTitle:"Weather")?.submenu) ?? "Weather"
        let paused=root.item(withTitle:"Resume weather") != nil
        status.stringValue=paused ? weather+" · Paused" : weather
        for view in body.arrangedSubviews {body.removeArrangedSubview(view);view.removeFromSuperview()}
        func b(_ title:String,_ symbol:String,_ path:String...)->Command {button(title,symbol,path,in:root)}
        switch tabs.selectedSegment {
        case 1:
            label("Snow tools")
            row(b("Roll a snowball","circle","Play on the snow","Roll snowball"),b("Throw a snowball","paperplane","Play on the snow","Throw snowball"))
            row(b("Pile snow","mountain.2","Play on the snow","Pile snow"),b("Puff snow","wind","Play on the snow","Puff snow"))
            row(b("Place a sled","arrow.down.right","Play on the snow","Place a sled"),b("Push a sled","arrow.right","Play on the snow","Push existing sleds"))
            label("Visitors and events")
            row(b("Send a visitor…","figure.walk","Visitors"),b("Wake the snowmen","sparkles","Play on the snow","Wake the snowmen"))
            row(b("Blizzard","wind.snow","Play on the snow","Blizzard"),b("Done playing","checkmark","Play on the snow","Done playing"))
            let grab=item(["Grab and throw snow"],in:root)?.state == .on
            row(b(grab ? "Grab and throw on" : "Grab and throw off","hand.draw","Grab and throw snow"))
        case 2:
            label("Trees and lights")
            row(b("Decorate a tree…","leaf","Decorate a tree…"),b("Plant a tree","plus","Decorate",WorkshopKind.tree.rawValue))
            row(b("Hang string lights","lightbulb","Decorate",WorkshopKind.lights.rawValue),b("Bulb size…","circle.grid.2x2","Decorate","New string bulb size"))
            label("On your desktop")
            row(b("All decorations…","square.grid.2x2","Decorate"),b("Arrange decorations","arrow.up.and.down.and.arrow.left.and.right","Decorate","Arrange decorations"))
            let twinkle=item(["Decorate","Twinkle string and tree lights"],in:root)?.state == .on
            row(b(twinkle ? "Twinkle on" : "Twinkle off","sparkles","Decorate","Twinkle string and tree lights"),b("Done arranging","checkmark","Decorate","Done arranging"))
        case 3:
            label("Gift train")
            row(b("Send a gift…","gift","Send a Gift…"),b("Open a gift file…","envelope.open","Open a Gift…"))
            row(b("Replay last gift","arrow.counterclockwise","Replay Last Gift"))
            let hint=NSTextField(wrappingLabelWithString:"Open Send a gift to exchange friend codes, choose a present, and send the train.")
            hint.textColor = .secondaryLabelColor;hint.font = .systemFont(ofSize:12)
            body.addArrangedSubview(hint);hint.widthAnchor.constraint(equalTo:body.widthAnchor).isActive=true
        default:
            label("Weather")
            row(b(weather+"…","cloud.snow","Weather"),b("Wind…","wind","Weather","Wind"))
            row(b("Weather volume…","slider.horizontal.3","Snow and windows","Weather volume"),b("Drift depth…","snowflake","Snow and windows","Accumulation depth"))
            label("Desktop")
            row(b("Wallpaper…","photo","Desktop wallpaper"),b("Snow and windows…","macwindow","Snow and windows"))
            let pause=paused ? "Resume weather":"Pause weather"
            row(b(pause,paused ? "play":"pause",pause),b("Clear scene","trash","Clear scene"))
        }
    }
    @objc private func activate(_ sender:Command) {
        // Keep the menu alive while dispatching so actions that update sibling rows work.
        let root=menu()
        guard let entry=item(sender.path,in:root),entry.isEnabled else {refresh();return}
        if let list=entry.submenu {
            list.popUp(positioning:nil,at:NSPoint(x:0,y:sender.bounds.minY-3),in:sender)
        } else if let action=entry.action {
            _=NSApp.sendAction(action,to:entry.target,from:entry)
        }
        refresh()
    }
}
