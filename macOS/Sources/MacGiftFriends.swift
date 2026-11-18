import AppKit

@MainActor final class MacGiftFriends: NSObject {
    private let mailbox: () throws -> GiftMailbox
    private let makeGift: () throws -> FrostGift
    private let displayName: () -> String
    private let received: () -> Void
    private var post: SharedGiftPost?
    private var connected: Bool?, polling = false, busy = false, forceAfterPoll = false
    private var nextCheck = Date.distantPast
    private var peers: [SharedGiftPost.Friend] = []
    private let status = NSTextField(wrappingLabelWithString: "")
    private let result = NSTextField(wrappingLabelWithString: "")
    private let recipient = NSPopUpButton()
    private var connectButton: NSButton?, disconnectButton: NSButton?, sendButton: NSButton?

    init(mailbox: @escaping () throws -> GiftMailbox, makeGift: @escaping () throws -> FrostGift,
         displayName: @escaping () -> String, received: @escaping () -> Void) {
        self.mailbox = mailbox; self.makeGift = makeGift
        self.displayName = displayName; self.received = received
        super.init()
    }

    private func service() throws -> SharedGiftPost {
        if let post = post { return post }
        let created = try SharedGiftPost(mailbox: mailbox())
        post = created
        return created
    }

    func controls() -> NSView {
        let connect = NSButton(title:"Connect Folder…", target:self, action:#selector(chooseFolder))
        let detach = NSButton(title:"Disconnect", target:self, action:#selector(disconnect))
        let send = NSButton(title:"Send to Friend", target:self, action:#selector(sendGift))
        connectButton = connect; disconnectButton = detach; sendButton = send
        recipient.setAccessibilityLabel("Friend")
        recipient.widthAnchor.constraint(equalToConstant: 190).isActive = true
        let links = NSStackView(views:[connect,detach])
        let recipients = NSStackView(views:[recipient,send])
        for label in [status,result] { label.font = NSFont.systemFont(ofSize:12); label.textColor = .secondaryLabelColor }
        let column = NSStackView(views:[NSTextField(labelWithString:"Shared-folder delivery"),status,links,recipients,result])
        column.orientation = .vertical; column.alignment = .leading; column.spacing = 5
        for label in [status,result] { label.widthAnchor.constraint(equalTo:column.widthAnchor).isActive = true }
        status.stringValue = "Choose the same shared or synced folder as your friend."
        updateButtons()
        return column
    }

    private func updateButtons() {
        connectButton?.isEnabled = !busy
        disconnectButton?.isEnabled = !busy && connected == true
        recipient.isEnabled = !busy && !peers.isEmpty
        sendButton?.isEnabled = !busy && connected == true && !peers.isEmpty
    }

    private func list(_ friends: [SharedGiftPost.Friend]) {
        guard peers != friends || recipient.numberOfItems == 0 else { return }
        let oldID = peers.indices.contains(recipient.indexOfSelectedItem) ? peers[recipient.indexOfSelectedItem].id : nil
        peers = friends
        recipient.removeAllItems()
        if friends.isEmpty { recipient.addItem(withTitle:"No friends connected") }
        else {
            recipient.addItems(withTitles:friends.map { $0.name + " · " + String($0.id.prefix(4)) })
            if let index = friends.firstIndex(where:{ $0.id == oldID }) { recipient.selectItem(at:index) }
        }
        updateButtons()
    }

    func poll(force: Bool = false) {
        if polling { forceAfterPoll = forceAfterPoll || force; return }
        guard !busy, force || (connected != false && Date() >= nextCheck) else { return }
        polling = true; nextCheck = Date().addingTimeInterval(2)
        Task {
            defer {
                polling = false; updateButtons()
                if forceAfterPoll { forceAfterPoll = false; poll(force:true) }
            }
            do {
                let post = try service()
                guard let current = await post.connection else {
                    connected = false; list([])
                    status.stringValue = "Choose the same shared or synced folder as your friend."
                    return
                }
                connected = true
                let gifts = try await post.incoming()
                if !gifts.isEmpty {
                    let mail = try mailbox()
                    for gift in gifts { _ = try mail.accept(gift) }
                    received()
                    try await post.confirm(gifts, at:current.folder)
                }
                if recipient.window?.isVisible == true {
                    list(try await post.friends())
                    status.stringValue = "Connected as " + current.name + " in " + current.folder.lastPathComponent + "."
                }
            } catch {
                list([]); status.stringValue = "Shared folder unavailable. " + error.localizedDescription
                nextCheck = Date().addingTimeInterval(8)
            }
        }
    }

    private func perform(_ action: @escaping (SharedGiftPost) async throws -> String) {
        guard !busy else { return }
        busy = true; updateButtons()
        Task {
            do { result.stringValue = try await action(service()) }
            catch { result.stringValue = error.localizedDescription }
            busy = false; connected = nil; nextCheck = .distantPast
            updateButtons(); poll(force:true)
        }
    }

    @objc private func chooseFolder() {
        let name = displayName()
        guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {
            result.stringValue = "Enter your display name in From first."
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "Connect"; panel.message = "Choose the folder you share with your friend."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        perform { post in try await post.connect(folder, as:name); return "Friend card saved." }
    }

    @objc private func disconnect() {
        perform { post in try await post.disconnect(); return "Disconnected." }
    }

    @objc private func sendGift() {
        guard peers.indices.contains(recipient.indexOfSelectedItem) else { return }
        let friend = peers[recipient.indexOfSelectedItem]
        do {
            let gift = try makeGift()
            perform { post in
                try await post.send(gift, to:friend)
                return "Gift sent to " + friend.name + "."
            }
        } catch { result.stringValue = error.localizedDescription }
    }
}
