import Foundation

/// The same friend cards and addressed mailboxes used by Windows GiftPost.
/// All shared-volume I/O runs on this actor, away from the desktop's animation loop.
actor SharedGiftPost {
    struct Connection: Codable, Equatable {
        let folder: URL
        let name: String
    }
    struct Friend: Equatable {
        let id: String
        let name: String
    }
    private let files = FileManager.default
    private let mailbox: GiftMailbox
    private let identity: String, settings: URL
    private(set) var connection: Connection?

    init(mailbox: GiftMailbox) throws {
        self.mailbox = mailbox
        identity = mailbox.senderID
        settings = mailbox.root.appendingPathComponent("shared-folder.json")
        if FileManager.default.fileExists(atPath: settings.path) {
            let saved = try JSONDecoder().decode(Connection.self, from: Data(contentsOf: settings))
            guard saved.folder.isFileURL else { throw GiftProblem.message("The saved shared folder is invalid.") }
            connection = saved
        }
    }

    private func friendsFolder(_ root: URL) -> URL { root.appendingPathComponent("Frostpane Post/Friends", isDirectory: true) }
    private func card(_ root: URL, id: String) -> URL { friendsFolder(root).appendingPathComponent(id + ".friend") }

    // The user chooses the root. The protocol's directories underneath it must be real folders.
    private func checkedFolder(_ root: URL, _ parts: [String], create: Bool = false) throws -> URL {
        var folder = root
        for part in parts {
            folder = folder.appendingPathComponent(part, isDirectory:true)
            if create && !files.fileExists(atPath:folder.path) {
                do { try files.createDirectory(at:folder, withIntermediateDirectories:false) }
                catch { if !files.fileExists(atPath:folder.path) { throw error } }
            }
            let info = try folder.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            guard info.isDirectory == true, info.isSymbolicLink != true else {
                throw GiftProblem.message("The shared mailbox contains an invalid folder.")
            }
        }
        return folder
    }

    private func friendName(_ value: String) throws -> String {
        let name = FrostGift.sanitized(value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, value.utf16.count <= 32 else { throw GiftProblem.message("Enter a display name of up to 32 characters.") }
        return name
    }

    func connect(_ root: URL, as displayName: String) throws {
        let name = try friendName(displayName), folder = root.standardizedFileURL
        guard folder.isFileURL, try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw GiftProblem.message("Choose an existing folder that both friends can access.")
        }
        if let old = connection, old.folder != folder {
            throw GiftProblem.message("Disconnect your current folder before choosing another.")
        }
        _ = try checkedFolder(folder, ["Frostpane Post","Friends"], create:true)
        _ = try checkedFolder(folder, ["Frostpane Post","Mail",identity], create:true)
        try Data(name.utf8).write(to: card(folder, id: identity), options: .atomic)
        let config = Connection(folder: folder, name: name)
        do { try JSONEncoder().encode(config).write(to: settings, options: .atomic) }
        catch {
            // Undo the published registration if the durable local connection could not be saved.
            if let previous = connection { try? Data(previous.name.utf8).write(to:card(folder,id:identity), options:.atomic) }
            else { try? files.removeItem(at:card(folder,id:identity)) }
            throw error
        }
        connection = config
    }

    func disconnect() throws {
        guard let current = connection else { return }
        _ = try checkedFolder(current.folder, ["Frostpane Post","Friends"])
        let mine = card(current.folder, id: identity)
        if files.fileExists(atPath: mine.path) { try files.removeItem(at: mine) }
        try files.removeItem(at: settings)
        connection = nil
    }

    func friends() throws -> [Friend] {
        guard let current = connection else { return [] }
        let folder = try checkedFolder(current.folder, ["Frostpane Post","Friends"])
        let cards = try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey,.isSymbolicLinkKey], options: .skipsHiddenFiles)
        var result: [Friend] = []
        for url in cards where url.pathExtension == "friend" {
            let id = url.deletingPathExtension().lastPathComponent
            guard FrostGift.validID(id), id.lowercased() != identity,
                  let info = try? url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey]),
                  info.isRegularFile == true, info.isSymbolicLink != true,
                  let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            guard let bytes = try? handle.read(upToCount: 151), bytes.count <= 150,
                  let raw = String(data: bytes, encoding: .utf8), let name = try? friendName(raw) else { continue }
            result.append(Friend(id: id, name: name))
            if result.count >= 128 { break }
        }
        return result.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    func send(_ draft: FrostGift, to friend: Friend) throws {
        guard let current = connection, FrostGift.validID(friend.id), friend.id.lowercased() != identity,
              files.fileExists(atPath: card(current.folder, id: friend.id).path) else {
            throw GiftProblem.message("Choose a friend connected to this folder.")
        }
        var gift = draft
        gift.senderID = identity; gift.sender = current.name; gift.recipientID = friend.id
        let data = try gift.encoded()
        let box = try checkedFolder(current.folder, ["Frostpane Post","Mail",friend.id], create:true)
        // A sync client or another copy of Jake Frost can watch this directory during the write.
        let partial = box.appendingPathComponent(UUID().uuidString + ".part")
        let target = box.appendingPathComponent(gift.id + ".fpgift")
        defer { try? files.removeItem(at: partial) }
        try data.write(to: partial)
        do { try files.moveItem(at: partial, to: target) }
        catch {
            guard let existing = try? FrostGift.read(target), (try? existing.encoded()) == data else { throw error }
        }
    }

    func incoming() throws -> [FrostGift] {
        guard let current = connection else { return [] }
        let folder = try checkedFolder(current.folder, ["Frostpane Post","Mail",identity])
        let urls = try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey,.isSymbolicLinkKey], options: .skipsHiddenFiles)
        var gifts: [FrostGift] = []
        for url in urls where url.pathExtension == "fpgift" {
            let id = url.deletingPathExtension().lastPathComponent
            guard FrostGift.validID(id), (try? url.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) != true,
                  let gift = try? FrostGift.read(url),
                  gift.id == id, gift.recipientID == identity else { continue }
            gifts.append(gift)
            if gifts.count >= 16 { break }
        }
        return gifts
    }

    func stageIncoming() throws -> [FrostGift] {
        var stored: [FrostGift] = []
        for gift in try incoming() {
            do { _ = try mailbox.accept(gift); stored.append(gift) }
            catch {
                if stored.isEmpty { throw error }
                break // Dispatch the entries already saved. The next poll retries the rest.
            }
        }
        return stored
    }

    /// Remove only envelopes that are safely stored in the local pending or received folder.
    func confirm(_ stored: [FrostGift], at folder: URL) throws {
        guard folder == connection?.folder else { return }
        let box = try checkedFolder(folder, ["Frostpane Post","Mail",identity])
        for gift in stored where FrostGift.validID(gift.id) && gift.recipientID == identity {
            let target = box.appendingPathComponent(gift.id + ".fpgift")
            guard files.fileExists(atPath:target.path),
                  let onDisk = try? FrostGift.read(target), try onDisk.encoded() == gift.encoded() else { continue }
            try files.removeItem(at: target)
        }
    }
}
