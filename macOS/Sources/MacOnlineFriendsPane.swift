import AppKit

@MainActor final class MacOnlineFriendsPane: NSObject {
    private let mailbox: () throws -> GiftMailbox
    private let makeGift: () throws -> FrostGift
    private let displayName: () -> String
    private let received: () -> Void
    private var service: MacOnlinePost?, contacts: [MacOnlinePost.Friend] = []
    private var nextCheck = Date.distantPast, failures = 0, checking = false, busy = false
    private let recipient = NSPopUpButton(), code = NSTextField()
    private let message = NSTextField(wrappingLabelWithString:"Share one private invitation with the person you want to add.")
    private lazy var send = NSButton(title:"Send to Friend",target:self,action:#selector(sendGift))
    private lazy var remove = NSButton(title:"Remove",target:self,action:#selector(removeFriend))
    private lazy var copy = NSButton(title:"Copy Invitation",target:self,action:#selector(copyInvite))
    private lazy var accept = NSButton(title:"Accept Invitation",target:self,action:#selector(acceptInvite))
    private lazy var check = NSButton(title:"Check Deliveries",target:self,action:#selector(refresh))
    private var selected: MacOnlinePost.Friend? {
        contacts.indices.contains(recipient.indexOfSelectedItem) ? contacts[recipient.indexOfSelectedItem] : nil
    }

    init(mailbox: @escaping () throws -> GiftMailbox, makeGift: @escaping () throws -> FrostGift,
         displayName: @escaping () -> String, received: @escaping () -> Void) {
        self.mailbox = mailbox; self.makeGift = makeGift; self.displayName = displayName; self.received = received
    }
    private func post() throws -> MacOnlinePost {
        if let service = service { return service }
        let post = try MacOnlinePost(mailbox:mailbox()); service = post; return post
    }

    func controls() -> NSView {
        recipient.target = self; recipient.action = #selector(updateButtons)
        recipient.setAccessibilityLabel("Online friend"); recipient.widthAnchor.constraint(equalToConstant:180).isActive = true
        code.placeholderString = "JF1 invitation code"; code.setAccessibilityLabel("Private invitation code")
        code.widthAnchor.constraint(equalToConstant:220).isActive = true
        message.font = NSFont.systemFont(ofSize:12); message.textColor = .secondaryLabelColor
        let rows = NSStackView(views:[NSStackView(views:[recipient,send,remove]),NSStackView(views:[copy,check]),
                                      NSStackView(views:[code,accept]),message])
        rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 8
        message.widthAnchor.constraint(equalTo:rows.widthAnchor).isActive = true
        show(contacts); return rows
    }
    @objc private func updateButtons() {
        copy.isEnabled = !busy; accept.isEnabled = !busy; code.isEnabled = !busy
        send.isEnabled = !busy && selected?.active == true
        recipient.isEnabled = !busy && !contacts.isEmpty
        remove.isEnabled = !busy && selected != nil; check.isEnabled = !busy && !checking
    }
    private func show(_ rows: [MacOnlinePost.Friend]) {
        let selectedID = selected?.id
        contacts = rows
        recipient.removeAllItems()
        if rows.isEmpty { recipient.addItem(withTitle:"No online friends") }
        else {
            recipient.addItems(withTitles:rows.map { $0.name + " · " + $0.id.prefix(4) })
            if let previous = rows.firstIndex(where:{ $0.id == selectedID }) { recipient.selectItem(at:previous) }
        }
        updateButtons()
    }
    func poll(force: Bool = false, acknowledge: Bool = false) {
        guard !busy, !checking, force || Date() >= nextCheck else { return }
        checking = true
        Task {
            defer { checking = false; updateButtons() }
            do {
                let service = try post()
                try await service.poll()
                let rows = try await service.list()
                if rows != contacts || recipient.numberOfItems == 0 { show(rows) }
                if acknowledge { message.stringValue = rows.isEmpty ? "Copy or accept an invitation to add your first friend." : "Deliveries checked." }
                failures = 0; nextCheck = Date().addingTimeInterval(90)
                if !rows.isEmpty { received() }
            } catch {
                // A letter may already have reached the local inbox before a network acknowledgement failed.
                received(); message.stringValue = error.localizedDescription
                failures = min(failures+1,5)
                nextCheck = Date().addingTimeInterval(min(600,60*pow(2,Double(failures-1))))
            }
        }
    }
    @objc private func refresh() { poll(force:true,acknowledge:true) }

    private func work(_ action: @escaping @MainActor (MacOnlinePost) async throws -> String) {
        guard !busy else { return }
        busy = true; updateButtons()
        Task {
            do {
                let service = try post()
                message.stringValue = try await action(service)
                show(try await service.list())
            } catch { message.stringValue = error.localizedDescription }
            busy = false; nextCheck = .distantPast; updateButtons(); poll(force:true)
        }
    }
    @objc private func copyInvite() {
        let name = displayName()
        work { service in
            let invite = try await service.invite(as:name)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(invite,forType:.string)
            return "Invitation copied. Send it privately to one friend."
        }
    }
    @objc private func acceptInvite() {
        let invitation = code.stringValue, name = displayName()
        work { service in
            let friend = try await service.accept(invitation,as:name)
            self.code.stringValue = ""
            return "Connected to " + friend + "."
        }
    }
    @objc private func sendGift() {
        guard let friend = selected, friend.active else { return }
        do {
            let gift = try makeGift()
            work { service in
                try await service.send(gift,to:friend.id) ? "Sent to " + friend.name + "." : "Gift saved in your outbox. Jake Frost will retry automatically."
            }
        } catch { message.stringValue = error.localizedDescription }
    }
    @objc private func removeFriend() {
        guard let friend = selected else { return }
        let alert = NSAlert()
        alert.messageText = friend.active ? "Remove " + friend.name + "?" : "Cancel this invitation?"
        alert.informativeText = "This closes the connection and clears gifts awaiting delivery."
        alert.addButton(withTitle:"Cancel"); alert.addButton(withTitle:"Remove")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        work { service in try await service.remove(friend.id); return "Connection removed." }
    }
}

