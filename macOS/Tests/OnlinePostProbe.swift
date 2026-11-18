import Foundation
import Security

@main enum OnlinePostProbe {
    static func check(_ ok: Bool, _ label: String) throws {
        guard ok else { throw GiftProblem.message("Failed: " + label) }
        print("PASS " + label)
    }

    static func rejects(_ operation: () async throws -> Void, _ label: String) async throws {
        var failed = false
        do { try await operation() } catch { failed = true }
        try check(failed,label)
    }

    static func interop(input: URL, output: URL) throws {
        let secret = String(repeating:"A",count:43), id = "0123456789abcdef0123456789abcdef"
        let fixture = try JSONDecoder().decode([String:String].self,from:Data(contentsOf:input))
        try check(try MacFriendEnvelope.id(secret) == fixture["address"] && MacFriendEnvelope.proof(secret) == fixture["proof"],
                  "Windows and Mac derive the same friendship address and claim proof")
        let name = try MacFriendEnvelope.open(fixture["name"] ?? "",secret:secret,label:"name/a")
        let payload = try MacFriendEnvelope.open(fixture["body"] ?? "",secret:secret,label:"gift/b/"+id)
        let gift = try FrostGift.decode(Data(payload.utf8))
        try check(name == "Windows friend" && gift.note == "Fresh snow from Windows" && gift.id == id,"read Windows authenticated name and snow gift")
        var tamper = Data(base64Encoded:fixture["body"]!)!
        tamper[16] ^= 1
        var refused = false
        do { _ = try MacFriendEnvelope.open(tamper.base64EncodedString(),secret:secret,label:"gift/b/"+id) } catch { refused = true }
        try check(refused, "reject modified ciphertext")
        var response = FrostGift(); response.id = id; response.note = "Fresh snow from Mac"
        let result = try ["name":MacFriendEnvelope.seal("Mac friend",secret:secret,label:"name/b"),
                          "body":MacFriendEnvelope.seal(String(decoding:response.encoded(),as:UTF8.self),secret:secret,label:"gift/a/"+id)]
        try JSONEncoder().encode(result).write(to:output)
    }

    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 4, let endpoint = URL(string:args[1]) else { throw GiftProblem.message("Expected relay URL and fixture paths.") }
        try interop(input:URL(fileURLWithPath:args[2]),output:URL(fileURLWithPath:args[3]))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            // Remove only the native Keychain entries belonging to these disposable profiles.
            for profile in ["owner","guest","third"] {
                let path = root.appendingPathComponent(profile).appendingPathComponent("online-friends-v1.dat").standardizedFileURL.path
                let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,
                    kSecAttrService as String:"app.jakefrost.online-post.v1", kSecAttrAccount as String:path]
                SecItemDelete(query as CFDictionary)
            }
            try? FileManager.default.removeItem(at:root)
        }
        let a = try GiftMailbox(root: root.appendingPathComponent("owner"))
        let b = try GiftMailbox(root: root.appendingPathComponent("guest"))
        let c = try GiftMailbox(root: root.appendingPathComponent("third"))
        let owner = try MacOnlinePost(mailbox:a,endpoint:endpoint), guest = try MacOnlinePost(mailbox:b,endpoint:endpoint)
        let third = try MacOnlinePost(mailbox:c,endpoint:endpoint)
        let invite = try await owner.invite(as:"Mac test A")
        guard let pending = try await owner.list().first else { throw GiftProblem.message("Invitation missing.") }
        try check(invite.hasPrefix("JF1-") && !pending.active,"new invitation awaits consent")
        try await rejects({ _ = try await owner.accept(invite,as:"Mac test A") }, "reject own invitation")
        try check(try await guest.accept(invite,as:"Mac test B") == "Mac test A","accept actual relay invitation")
        try await rejects({ _ = try await third.accept(invite,as:"Mac test C") },"a third device cannot reuse a claimed invitation")
        try await owner.poll()
        try check(try await owner.list().first?.name == "Mac test B","receive authenticated friend name")
        let reopened = try MacOnlinePost(mailbox:a,endpoint:endpoint)
        try check(try await reopened.list().first?.active == true,"reopen encrypted contacts using the Mac login Keychain")
        let saved = try Data(contentsOf:a.root.appendingPathComponent("online-friends-v1.dat"))
        try check(saved.range(of:Data(invite.dropFirst(4).utf8)) == nil && saved.range(of:Data("Mac test B".utf8)) == nil,
                  "local friendship file contains no plaintext invitation or name")
        var note = FrostGift(); note.note = "A freshly reopened snowman"; note.kind = .snowman; note.size = 44; note.mid = 76; note.head = 59
        let offline = try MacOnlinePost(mailbox:a,endpoint:URL(string:"http://127.0.0.1:1/api/post")!)
        try check(try await !offline.send(note,to:pending.id),"persist the encrypted gift while the sender is offline")
        try await reopened.poll(); try await guest.poll()
        let delivered = try b.next()
        try check(delivered?.id == note.id && delivered?.mid == 76 && delivered?.sender == "Mac test A","retry after restart and receive the correctly sized gift")
        if let first = delivered { try b.acknowledge(first) }
        _ = try await reopened.send(note,to:pending.id)
        try await guest.poll()
        try check(try b.next() == nil,"suppress duplicate online gifts after an acknowledged delivery")
        var reply = FrostGift(); reply.note = "Reply"; reply.kind = .tree
        let guestAgain = try MacOnlinePost(mailbox:b,endpoint:endpoint)
        _ = try await guestAgain.send(reply,to:pending.id); try await reopened.poll()
        let back = try a.next()
        try check(back?.id == reply.id && back?.kind == .tree && back?.sender == "Mac test B","deliver an encrypted gift in the opposite direction")
        try await guestAgain.remove(pending.id); try await reopened.poll()
        let cleanA = try await reopened.list(), cleanB = try await guestAgain.list()
        try check(cleanA.isEmpty && cleanB.isEmpty,"revoking the friendship removes it on both devices")
    }
}

