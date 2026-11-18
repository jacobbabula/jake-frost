import AppKit

@MainActor final class MacGifts: NSObject {
    var deliver: ((FrostGift, @escaping () -> Void) -> Bool)?
    private var mailbox: GiftMailbox?
    private var timer: Timer?, composer: NSPanel?, sharing: NSSharingServicePicker?
    private var senderField = NSTextField(), noteField = NSTextField(), kindField = NSPopUpButton()
    private var shareButton = NSButton(), feedback = NSTextField(wrappingLabelWithString: "")
    private var activeID: String?, pendingReceipt: FrostGift?, replayGift: FrostGift?
    private var needsDrain = true, lastFailure: String?

    private func box() throws -> GiftMailbox {
        if let mailbox = mailbox { return mailbox }
        let appData = try FileManager.default.url(for:.applicationSupportDirectory, in:.userDomainMask, appropriateFor:nil, create:true)
        let mailbox = try GiftMailbox(root:appData.appendingPathComponent("Jake Frost/Gifts",isDirectory:true))
        self.mailbox = mailbox
        return mailbox
    }

    func start() {
        if timer == nil {
            let timer = Timer(timeInterval:1,target:self,selector:#selector(timerFired(_:)),userInfo:nil,repeats:true)
            RunLoop.main.add(timer, forMode:.common)
            self.timer = timer
        }
        needsDrain = true
        drain()
    }
    @objc private func timerFired(_ timer: Timer) { drain() }
    func retryUndelivered() { activeID = nil; needsDrain = true }

    private func drain() {
        guard activeID == nil, let deliver = deliver, needsDrain || pendingReceipt != nil || replayGift != nil else { return }
        do {
            let mail = try box()
            if let gift = pendingReceipt {
                try mail.acknowledge(gift)
                pendingReceipt = nil
            }
            if let gift = try mail.next() {
                activeID = gift.id
                let accepted = deliver(gift) { [weak self] in
                    guard let self = self, self.activeID == gift.id else { return }
                    self.activeID = nil; self.pendingReceipt = gift; self.needsDrain = true
                    // Commit at arrival so a normal quit after delivery does not replay the train.
                    do {
                        try mail.acknowledge(gift)
                        self.pendingReceipt = nil
                    } catch { /* The timer retries the receipt. */ }
                }
                if !accepted { activeID = nil }
            } else if let replay = replayGift {
                if deliver(replay, {}) { replayGift = nil }
            } else { needsDrain = false }
            lastFailure = nil
        } catch {
            if error.localizedDescription != lastFailure {
                lastFailure = error.localizedDescription
                NSLog("Jake Frost gift inbox: %@",error.localizedDescription)
            }
        }
    }

    func appendCommands(to menu: NSMenu) {
        for (title, action) in [("Send a Gift…",#selector(compose)),("Open a Gift…",#selector(openPanel)),("Replay Last Gift",#selector(replay))] {
            let item = NSMenuItem(title:title, action:action, keyEquivalent:"")
            item.target = self; menu.addItem(item)
        }
    }

    func open(_ urls: [URL]) {
        for url in urls {
            do {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let (state,gift) = try box().accept(url)
                if state == .delivered {
                    let alert = NSAlert()
                    alert.messageText = "You’ve opened this gift"
                    alert.informativeText = "Play the delivery from " + (gift.sender.isEmpty ? "a friend" : gift.sender) + " again?"
                    alert.addButton(withTitle:"Replay"); alert.addButton(withTitle:"Close")
                    NSApp.activate(ignoringOtherApps:true)
                    if alert.runModal() == .alertFirstButtonReturn { replayGift = gift }
                }
                needsDrain = true
            } catch { notice("Couldn’t open the gift",error.localizedDescription) }
        }
        drain()
    }

    private func notice(_ title:String,_ body:String) {
        NSApp.activate(ignoringOtherApps:true)
        let alert=NSAlert();alert.messageText=title;alert.informativeText=body;alert.addButton(withTitle:"OK");alert.runModal()
    }

    @objc private func openPanel() {
        NSApp.activate(ignoringOtherApps:true)
        let panel=NSOpenPanel()
        panel.allowedFileTypes=["fpgift"]; panel.allowsMultipleSelection=true
        panel.canChooseFiles=true;panel.canChooseDirectories=false;panel.prompt="Open Gift"
        if panel.runModal() == .OK { open(panel.urls) }
    }

    @objc private func replay() {
        do {
            guard let latest = try box().latest() else { notice("Your gift inbox is empty","Open a .fpgift file from a friend to receive your first delivery.");return }
            replayGift = latest;drain()
        } catch { notice("Couldn’t replay the gift",error.localizedDescription) }
    }

    @objc private func compose() {
        if composer == nil {
            let panel=NSPanel(contentRect:NSRect(x:0,y:0,width:415,height:250),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            panel.title="Send a Gift";panel.isReleasedWhenClosed=false
            let column=NSStackView()
            column.orientation = .vertical;column.alignment = .leading;column.spacing=13
            column.translatesAutoresizingMaskIntoConstraints=false
            let grid=NSGridView()
            grid.rowSpacing=9;grid.columnSpacing=12
            senderField.placeholderString="A friend";senderField.stringValue=UserDefaults.standard.string(forKey:"giftSender") ?? ""
            noteField.placeholderString="A note for your friend"
            kindField.addItems(withTitles:FrostGift.Kind.allCases.map(\.rawValue))
            for (label,control) in [("From",senderField as NSControl),("Gift",kindField as NSControl),("Message",noteField as NSControl)] {
                control.setAccessibilityLabel(label)
                grid.addRow(with:[NSTextField(labelWithString:label),control])
            }
            grid.column(at:0).xPlacement = .trailing
            column.addArrangedSubview(grid);grid.widthAnchor.constraint(equalTo:column.widthAnchor).isActive=true
            feedback.font=NSFont.systemFont(ofSize:12);feedback.textColor = .secondaryLabelColor
            feedback.stringValue="Your friend can open the gift in Jake Frost on Windows or Mac."
            column.addArrangedSubview(feedback);feedback.widthAnchor.constraint(equalTo:column.widthAnchor).isActive=true
            shareButton=NSButton(title:"Share…",target:self,action:#selector(share));shareButton.keyEquivalent="\r"
            let save=NSButton(title:"Save Gift File…",target:self,action:#selector(saveFile))
            let buttons=NSStackView(views:[shareButton,save]);buttons.spacing=8
            column.addArrangedSubview(buttons)
            if let content=panel.contentView {
                content.addSubview(column)
                NSLayoutConstraint.activate([column.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:22),
                                              column.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-22),
                                              column.topAnchor.constraint(equalTo:content.topAnchor,constant:22)])
            }
            panel.center();composer=panel
        }
        NSApp.activate(ignoringOtherApps:true);composer?.makeKeyAndOrderFront(nil);composer?.makeFirstResponder(noteField)
    }

    private func composeGift() throws -> FrostGift {
        let mailbox=try box()
        let kind=FrostGift.Kind(rawValue:kindField.titleOfSelectedItem ?? "") ?? .note
        let template=kind == .note ? nil : try mailbox.latest(kind:kind)
        let gift=try FrostGift.make(kind,sender:senderField.stringValue,note:noteField.stringValue,senderID:mailbox.senderID,template:template)
        UserDefaults.standard.set(senderField.stringValue,forKey:"giftSender")
        return gift
    }
    @objc private func saveFile() {
        do {
            let gift=try composeGift()
            let panel=NSSavePanel();panel.allowedFileTypes=["fpgift"];panel.nameFieldStringValue="Winter \(gift.kind.rawValue.lowercased()).fpgift"
            panel.prompt="Save Gift";panel.isExtensionHidden=false
            guard panel.runModal() == .OK, let url=panel.url else { return }
            try gift.encoded().write(to:url,options:.atomic)
            feedback.stringValue="Gift saved. Send the file as an attachment to your friend."
        } catch { feedback.stringValue=error.localizedDescription }
    }
    @objc private func share() {
        do {
            let gift=try composeGift()
            let folder=FileManager.default.temporaryDirectory.appendingPathComponent("JakeFrost-Gifts",isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let path=folder.appendingPathComponent("Winter \(gift.kind.rawValue.lowercased())-\(gift.id.prefix(8)).fpgift")
            try gift.encoded().write(to:path,options:.atomic)
            let picker=NSSharingServicePicker(items:[path])
            sharing=picker;picker.show(relativeTo:shareButton.bounds,of:shareButton,preferredEdge:.minY)
            feedback.stringValue="Choose a sharing app to send the gift file."
        } catch { feedback.stringValue=error.localizedDescription }
    }
}
