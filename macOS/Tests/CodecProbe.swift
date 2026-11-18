import Foundation

@main enum CodecProbe {
    static func check(_ ok: Bool, _ label: String) throws {
        guard ok else { throw GiftProblem.message("Failed: " + label) }
        print("PASS " + label)
    }

    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 3 else { throw GiftProblem.message("Usage: CodecProbe windows-tree.fpgift mac-tree.fpgift") }
        let fixture = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let inbox = try GiftMailbox(root: root)
        let result = try inbox.accept(fixture)
        let gift = result.1
        try check(result.0 == .added && gift.kind == .tree && gift.sender == "Winter maker" && gift.note == "Snow day!", "read Windows 3.1 gift")
        try check(abs(gift.size - 77.297186264906628) < 0.000001 && gift.style == 11 && gift.dress == "3,0.05,-0.42;scale,0,1.5;angles,32,-17", "retain dressed tree angles and ornament scale")
        try check(try inbox.accept(fixture).0 == .pending, "deduplicate during transit")
        let reopened = try GiftMailbox(root:root)
        try check(reopened.senderID == inbox.senderID && (try reopened.next())?.id == gift.id, "cold restart retains recipient and pending gift")
        try reopened.acknowledge(gift)
        try check(try reopened.next() == nil, "docking removes pending record")
        try check(try reopened.accept(fixture).0 == .delivered, "deduplicate a delivered attachment")
        try check(try reopened.latest(kind:.tree)?.id == gift.id, "delivered gift remains available for replay")
        var addressed = gift
        addressed.id = FrostGift.newID(); addressed.recipientID = FrostGift.newID()
        let wrong = root.appendingPathComponent("wrong.fpgift")
        try addressed.encoded().write(to:wrong)
        var refused = false
        do { _ = try reopened.accept(wrong) } catch is GiftProblem { refused = true }
        try check(refused, "reject another recipient's addressed envelope")
        addressed.recipientID = reopened.senderID
        try addressed.encoded().write(to:wrong)
        try check(try reopened.accept(wrong).0 == .added, "accept a matching addressed envelope")
        let mac = try FrostGift.make(.tree, sender:"Mac test sender", note:"A winter hello from Mac ☃", senderID:inbox.senderID, template:nil)
        try mac.encoded().write(to:output,options:.atomic)
        let roundtrip = try FrostGift.read(output)
        try check(roundtrip.dress == mac.dress && roundtrip.size == 83 && roundtrip.sender == mac.sender && roundtrip.recipientID.isEmpty && roundtrip.note == mac.note, "write portable Mac tree with Unicode note for Windows")
        let forwarded = try FrostGift.make(.tree,sender:"Second sender",note:"For you",senderID:inbox.senderID,template:gift)
        try check(forwarded.id != gift.id && forwarded.size == gift.size && forwarded.style == gift.style && forwarded.dress == gift.dress && forwarded.recipientID.isEmpty, "forward a copy with the original appearance and a fresh ID")
        let man = try FrostGift.make(.snowman,sender:"A friend",note:"",senderID:inbox.senderID,template:nil)
        try check(try FrostGift.decode(man.encoded()).kind == .snowman, "portable snowman")
        let note = try FrostGift.make(.note,sender:"A friend",note:"Hello",senderID:inbox.senderID,template:nil)
        try check(try FrostGift.decode(note.encoded()).note == "Hello", "portable note")
        var rejected = false
        do { _ = try FrostGift.decode(Data(repeating:32,count:FrostGift.limit+1)) } catch is GiftProblem { rejected=true }
        try check(rejected, "reject oversized payload")
    }
}
