import Foundation

@main enum SharedPostProbe {
    static func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw GiftProblem.message("Shared delivery failed: " + message) }
        print("PASS " + message)
    }

    static func main() async throws {
        let args = CommandLine.arguments, files = FileManager.default
        let temp = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory:true)
        let root = temp.appendingPathComponent("Mac profile", isDirectory:true)
        let share = temp.appendingPathComponent("Shared folder", isDirectory:true)
        defer { try? files.removeItem(at:temp) }
        try files.createDirectory(at:root,withIntermediateDirectories:true)
        let macID = String(repeating:"1",count:32), windowsID = String(repeating:"2",count:32)
        try macID.write(to:root.appendingPathComponent("identity"),atomically:true,encoding:.utf8)
        let inbox = share.appendingPathComponent("Frostpane Post/Mail/" + macID, isDirectory:true)
        if args.count > 1 {
            try files.copyItem(at:URL(fileURLWithPath:args[1]),to:share)
        } else {
            let cards = share.appendingPathComponent("Frostpane Post/Friends",isDirectory:true)
            try files.createDirectory(at:cards,withIntermediateDirectories:true)
            try files.createDirectory(at:inbox,withIntermediateDirectories:true)
            try Data("Windows friend".utf8).write(to:cards.appendingPathComponent(windowsID + ".friend"))
            var tree = try FrostGift.make(.tree,sender:"Windows friend",note:"Windows to Mac",senderID:windowsID,template:nil)
            tree.recipientID = macID
            try tree.encoded().write(to:inbox.appendingPathComponent(tree.id + ".fpgift"))
        }
        let mail = try GiftMailbox(root:root), first = try SharedGiftPost(mailbox:mail)
        try await first.connect(share,as:"Mac friend")
        let post = try SharedGiftPost(mailbox:GiftMailbox(root:root))
        try check(await post.connection?.name == "Mac friend", "shared-folder connection survives relaunch")
        let peers = try await post.friends()
        try check(peers.count == 1 && peers[0].name == "Windows friend" && peers[0].id == windowsID, "discover Windows friend and omit own card")
        let gifts = try await post.incoming()
        guard let tree = gifts.first else { throw GiftProblem.message("Missing Windows envelope") }
        try check(gifts.count == 1 && tree.kind == .tree && tree.senderID == windowsID && tree.recipientID == macID && tree.note == "Windows to Mac", "read addressed Windows tree")
        var wrong = tree; wrong.id = FrostGift.newID(); wrong.recipientID = windowsID
        let wrongURL = inbox.appendingPathComponent(wrong.id + ".fpgift")
        try wrong.encoded().write(to:wrongURL)
        let mismatch = inbox.appendingPathComponent(FrostGift.newID() + ".fpgift")
        try tree.encoded().write(to:mismatch)
        try check(try await post.incoming().count == 1, "ignore envelopes with another recipient or mismatched filenames")
        try check(try mail.accept(tree).0 == .added && (try mail.accept(tree)).0 == .pending, "repeated polls stage only one delivery")
        try await post.confirm([tree], at:share)
        try check(try await post.incoming().isEmpty && (try mail.next())?.id == tree.id, "remove remote envelope only after durable local staging")
        try mail.acknowledge(tree)
        let original = inbox.appendingPathComponent(tree.id + ".fpgift")
        try tree.encoded().write(to:original)
        try check(try mail.accept(tree).0 == .delivered, "a cloud-sync duplicate cannot replay a delivered gift")
        try await post.confirm([tree],at:share)
        try files.removeItem(at:wrongURL); try files.removeItem(at:mismatch)
        let draft = try FrostGift.make(.snowman,sender:"Mac friend",note:"Mac to Windows",senderID:macID,template:nil)
        try await post.send(draft,to:peers[0]); try await post.send(draft,to:peers[0])
        let windowsBox = share.appendingPathComponent("Frostpane Post/Mail/" + windowsID)
        let sent = try files.contentsOfDirectory(at:windowsBox,includingPropertiesForKeys:nil).filter { $0.pathExtension == "fpgift" }
        try check(sent.count == 1, "send one addressed Mac gift across retries")
        let response = try FrostGift.read(sent[0])
        try check(response.sender == "Mac friend" && response.senderID == macID && response.recipientID == windowsID && response.note == "Mac to Windows" && response.kind == .snowman, "emit Windows-compatible addressed snowman")
        var collision = draft
        collision.note = "Different gift with a reused ID"
        var refused = false
        do { try await post.send(collision,to:peers[0]) } catch { refused = true }
        try check(refused && (try FrostGift.read(sent[0])).note == "Mac to Windows", "never overwrite a different gift already waiting under the same ID")
        if args.count > 2 { try files.copyItem(at:share,to:URL(fileURLWithPath:args[2])) }
        try await post.disconnect()
        let disconnected = try SharedGiftPost(mailbox:mail)
        try check(await disconnected.connection == nil && !files.fileExists(atPath:share.appendingPathComponent("Frostpane Post/Friends/" + macID + ".friend").path), "disconnect removes own card and persists across restart")
    }
}
