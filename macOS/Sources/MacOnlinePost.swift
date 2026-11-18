import Foundation
import CryptoKit
import Security

private final class FriendPostSession: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private struct FriendPostError: LocalizedError {
    let status: Int, message: String
    var errorDescription: String? { message }
    var retryable: Bool { status == 0 || status == 409 || status == 429 || status >= 500 }
}

/// Local contacts are authenticated and encrypted with a per-profile key in the login Keychain.
private struct FriendVault {
    let file: URL
    var cachedKey: SymmetricKey?

    private mutating func key(create: Bool) throws -> SymmetricKey {
        if let key = cachedKey { return key }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.jakefrost.online-post.v1",
            kSecAttrAccount as String: file.standardizedFileURL.path
        ]
        var lookup = query, item: CFTypeRef?
        lookup[kSecReturnData as String] = true
        let rc = SecItemCopyMatching(lookup as CFDictionary,&item)
        let bytes: Data
        if rc == errSecItemNotFound && create {
            bytes = try MacFriendEnvelope.random(32)
            var entry = query
            entry[kSecValueData as String] = bytes
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            entry[kSecAttrLabel as String] = "Jake Frost online friends"
            let status = SecItemAdd(entry as CFDictionary,nil)
            if status == errSecDuplicateItem { return try key(create:false) }
            guard status == errSecSuccess else { throw GiftProblem.message("Couldn’t save the friendship key to your login Keychain.") }
        } else if rc == errSecSuccess, let found = item as? Data, found.count == 32 { bytes = found }
        else { throw GiftProblem.message("Unlock your login Keychain to access your online friends.") }
        let result = SymmetricKey(data:bytes)
        cachedKey = result
        return result
    }

    mutating func load() throws -> [MacOnlinePost.Contact] {
        guard FileManager.default.fileExists(atPath:file.path) else { return [] }
        let bytes = try Data(contentsOf:file)
        guard bytes.count <= 64_000 else { throw GiftProblem.message("The saved friend list could not be read.") }
        let clear = try AES.GCM.open(AES.GCM.SealedBox(combined:bytes),using:key(create:false))
        let contacts = try JSONDecoder().decode([MacOnlinePost.Contact].self,from:clear)
        guard contacts.count <= 16, Set(contacts.map(\.id)).count == contacts.count else {
            throw GiftProblem.message("The saved friend list could not be read.")
        }
        for c in contacts {
            guard c.id == (try MacFriendEnvelope.id(c.secret)) else { throw GiftProblem.message("Invalid saved friendship.") }
            _ = try MacFriendEnvelope.key(c.token)
        }
        return contacts
    }

    mutating func save(_ contacts: [MacOnlinePost.Contact]) throws {
        let data = try JSONEncoder().encode(contacts)
        let key = try key(create:!FileManager.default.fileExists(atPath:file.path))
        let box = try AES.GCM.seal(data,using:key)
        guard let sealed = box.combined else { throw GiftProblem.message("Couldn’t save encrypted friendships.") }
        try sealed.write(to:file,options:.atomic)
    }
}

actor MacOnlinePost {
    struct Contact: Codable {
        enum State: String, Codable { case creating, joining, pending, active }
        let id, secret, token, ownName: String
        let owner: Bool
        var name: String, state: State
    }
    struct Friend: Equatable {
        let id, name: String
        let active: Bool
    }
    private struct Letter: Decodable { let id, body: String }
    private struct Pair: Decodable { let id, status: String; let name: String?; let messages: [Letter]? }
    private struct Reply: Decodable { let name, error: String?; let contacts: [Pair]? }

    static let relay = URL(string:"https://jake-frost-mail.netlify.app/api/post")!
    let mailbox: GiftMailbox
    private let endpoint: URL, session: URLSession
    private var vault: FriendVault
    private var contacts: [Contact]?
    private var busy = false, waiters = [CheckedContinuation<Void,Never>]()

    init(mailbox: GiftMailbox, endpoint: URL = MacOnlinePost.relay) throws {
        guard endpoint.scheme == "https" || (endpoint.scheme == "http" && ["127.0.0.1","localhost","::1"].contains(endpoint.host ?? "")) else {
            throw GiftProblem.message("The online gift service requires HTTPS.")
        }
        self.mailbox = mailbox; self.endpoint = endpoint
        vault = FriendVault(file:mailbox.root.appendingPathComponent("online-friends-v1.dat"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10; configuration.timeoutIntervalForResource = 15
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration:configuration,delegate:FriendPostSession(),delegateQueue:nil)
    }
    deinit { session.invalidateAndCancel() }

    // Keep actions atomic across URLSession suspension. UI and timer can request a check together.
    private func start() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func finish() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }
    private func saved() throws -> [Contact] {
        if let rows = contacts { return rows }
        let rows = try vault.load(); contacts = rows; return rows
    }
    private func store(_ c: Contact) throws {
        var rows = try saved()
        if let i = rows.firstIndex(where:{ $0.id == c.id }) { rows[i] = c }
        else {
            guard rows.count < 16 else { throw GiftProblem.message("Remove a friend or invitation to make room.") }
            rows.append(c)
        }
        try vault.save(rows); contacts = rows
    }

    private func request(_ body: [String: Any]) async throws -> Reply {
        var req = URLRequest(url:endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json",forHTTPHeaderField:"Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject:body)
        let bytes: URLSession.AsyncBytes, response: URLResponse
        do { (bytes,response) = try await session.bytes(for:req) }
        catch { throw FriendPostError(status:0,message:"Couldn’t reach the gift service. Check your connection.") }
        guard let http = response as? HTTPURLResponse else { throw GiftProblem.message("Invalid gift service response.") }
        guard response.expectedContentLength <= 256_000 else { throw GiftProblem.message("The gift service response was too large.") }
        var data = Data()
        do {
            for try await byte in bytes {
                guard data.count < 256_000 else { throw GiftProblem.message("The gift service response was too large.") }
                data.append(byte)
            }
        } catch let e as GiftProblem { throw e }
        catch { throw FriendPostError(status:0,message:"The connection was interrupted. Please retry.") }
        let reply = try? JSONDecoder().decode(Reply.self,from:data)
        guard (200..<300).contains(http.statusCode) else {
            throw FriendPostError(status:http.statusCode,message:reply?.error ?? "The gift service could not complete this request.")
        }
        guard let result = reply else { throw GiftProblem.message("Invalid gift service response.") }
        return result
    }
    private func name(_ input: String) throws -> String {
        let value = FrostGift.sanitized(input).trimmingCharacters(in:.whitespacesAndNewlines)
        guard !value.isEmpty, value.utf16.count <= 32 else { throw GiftProblem.message("Enter a display name of 1–32 characters in From.") }
        return value
    }
    func list() throws -> [Friend] {
        try saved().map { c in
            Friend(id:c.id,name:c.state == .active ? c.name : (c.owner ? "Invitation · waiting" : "Invitation · joining"),active:c.state == .active)
        }
    }
    private func establish(_ c: Contact) async throws -> Contact {
        let label = c.owner ? "name/a" : "name/b"
        let reply = try await request(["action":c.owner ? "invite" : "accept","id":c.id,"token":c.token,
                                      "proof":MacFriendEnvelope.proof(c.secret),"name":MacFriendEnvelope.seal(c.ownName,secret:c.secret,label:label)])
        var changed = c
        if !c.owner { changed.name = try name(MacFriendEnvelope.open(reply.name ?? "",secret:c.secret,label:"name/a")) }
        changed.state = c.owner ? .pending : .active
        try store(changed)
        return changed
    }
    func invite(as display: String) async throws -> String {
        await start(); defer { finish() }
        let own = try name(display)
        let c: Contact
        if let previous = try saved().first(where:{ $0.owner && [.creating,.pending].contains($0.state) }) { c = previous }
        else {
            let secret = try MacFriendEnvelope.token()
            c = try Contact(id:MacFriendEnvelope.id(secret),secret:secret,token:MacFriendEnvelope.token(),ownName:own,owner:true,name:"",state:.creating)
            try store(c)
        }
        if c.state == .creating { _ = try await establish(c) }
        return "JF1-" + c.secret
    }
    func accept(_ invitation: String, as display: String) async throws -> String {
        await start(); defer { finish() }
        let code = invitation.trimmingCharacters(in:.whitespacesAndNewlines)
        guard code.hasPrefix("JF1-") else { throw GiftProblem.message("Paste the complete JF1 invitation code.") }
        let secret = String(code.dropFirst(4)), id = try MacFriendEnvelope.id(secret), own = try name(display)
        let c: Contact
        if let previous = try saved().first(where:{ $0.id == id }) {
            guard !previous.owner else { throw GiftProblem.message("Share your invitation with someone else.") }
            if previous.state == .active { return previous.name }
            c = previous
        } else {
            c = try Contact(id:id,secret:secret,token:MacFriendEnvelope.token(),ownName:own,owner:false,name:"",state:.joining)
            try store(c)
        }
        do { return try await establish(c).name }
        catch let error as FriendPostError {
            if [400,403,404,409,410].contains(error.status) { try forget(c) }
            throw error
        }
    }
    private func find(_ id: String) throws -> Contact {
        guard let c = try saved().first(where:{ $0.id == id }) else { throw GiftProblem.message("Choose an online friend.") }
        return c
    }
    private func outbox(_ c: Contact) -> URL {
        mailbox.root.appendingPathComponent("OnlineOutbox",isDirectory:true).appendingPathComponent(c.id,isDirectory:true)
    }
    private func queued(_ c: Contact) throws -> [URL] {
        let folder = outbox(c)
        guard FileManager.default.fileExists(atPath:folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).filter {
            $0.pathExtension == "letter" && FrostGift.validID($0.deletingPathExtension().lastPathComponent)
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    private func forget(_ c: Contact) throws {
        for file in try queued(c) { try FileManager.default.removeItem(at:file) }
        let rows = try saved().filter { $0.id != c.id }
        try vault.save(rows); contacts = rows
    }
    func remove(_ id: String) async throws {
        await start(); defer { finish() }
        let c = try find(id)
        _ = try await request(["action":"remove","id":c.id,"token":c.token])
        try forget(c)
    }

    private func deliver(_ file: URL, _ c: Contact) async throws {
        let id = file.deletingPathExtension().lastPathComponent
        let body = try String(contentsOf:file,encoding:.utf8)
        guard body.utf8.count <= 28_000 else { throw GiftProblem.message("Invalid queued gift.") }
        _ = try await request(["action":"send","id":c.id,"token":c.token,"giftId":id,"body":body])
        try FileManager.default.removeItem(at:file)
    }
    func send(_ draft: FrostGift, to id: String) async throws -> Bool {
        await start(); defer { finish() }
        let c = try find(id)
        guard c.state == .active else { throw GiftProblem.message("Your friend must accept the invitation first.") }
        var gift = draft
        gift.sender = c.ownName; gift.senderID = ""; gift.recipientID = ""
        let bytes = try gift.encoded()
        let folder = outbox(c)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let path = folder.appendingPathComponent(gift.id + ".letter")
        if !FileManager.default.fileExists(atPath:path.path) {
            guard try queued(c).count < 24 else { throw GiftProblem.message("Your outbox is full. Check deliveries after reconnecting.") }
            let side = c.owner ? "b" : "a"
            let body = try MacFriendEnvelope.seal(String(decoding:bytes,as:UTF8.self),secret:c.secret,label:"gift/"+side+"/"+gift.id)
            try Data(body.utf8).write(to:path,options:.atomic)
        }
        do { try await deliver(path,c); return true }
        catch let error as FriendPostError {
            if error.retryable { return false }
            if error.status == 403 { try forget(c) } else { try FileManager.default.removeItem(at:path) }
            throw error
        }
    }

    func poll() async throws {
        await start(); defer { finish() }
        let ready = try saved().filter { [.active,.pending].contains($0.state) }
        guard !ready.isEmpty else { return }
        let reply = try await request(["action":"poll","contacts":ready.map { ["id":$0.id,"token":$0.token] }])
        guard let rows = reply.contacts, rows.count == ready.count, Set(rows.map(\.id)) == Set(ready.map(\.id)) else {
            throw GiftProblem.message("Incomplete friend service response.")
        }
        for row in rows {
            var c = try find(row.id)
            if row.status == "gone" { try forget(c); continue }
            guard row.status == "active" else { continue }
            let other = c.owner ? "b" : "a", side = c.owner ? "a" : "b"
            let peer = try name(MacFriendEnvelope.open(row.name ?? "",secret:c.secret,label:"name/"+other))
            if c.state != .active || c.name != peer { c.state = .active; c.name = peer; try store(c) }
            for letter in row.messages ?? [] {
                guard FrostGift.validID(letter.id) else { throw GiftProblem.message("Invalid delivery identifier.") }
                if let clear = try? MacFriendEnvelope.open(letter.body,secret:c.secret,label:"gift/"+side+"/"+letter.id),
                   var gift = try? FrostGift.decode(Data(clear.utf8)), gift.id == letter.id, gift.senderID.isEmpty, gift.recipientID.isEmpty {
                    gift.sender = c.name
                    _ = try mailbox.accept(gift)
                }
                // Only acknowledge authentic gifts after they have a durable local inbox entry.
                _ = try await request(["action":"ack","id":c.id,"token":c.token,"giftId":letter.id])
            }
            for file in try queued(c).prefix(3) {
                do { try await deliver(file,c) }
                catch let error as FriendPostError where error.status == 409 { break }
            }
        }
    }
}

