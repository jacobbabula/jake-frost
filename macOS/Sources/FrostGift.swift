import Foundation

enum GiftProblem: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

struct FrostGift {
    enum Kind: String, CaseIterable { case note = "Note", snowman = "Snowman", tree = "Tree" }
    static let limit = 20_000
    static func newID() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }
    static func validID(_ value: String) -> Bool {
        value.utf8.count == 32 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }

    var id = FrostGift.newID(), senderID = "", recipientID = "", sender = "A friend", note = "", dress = ""
    var kind = Kind.note
    var style = 0
    var size = 18.0, mid = 13.0, head = 9.0, facing = 1.0

    static func sanitized(_ s: String) -> String {
        var result = ""
        for c in s.unicodeScalars {
            switch c.value {
            case 9, 10, 13: result.append(" ")
            case 0...31, 127...159: continue
            default: result.unicodeScalars.append(c)
            }
        }
        return result
    }

    func encoded() throws -> Data {
        func base64(_ text: String) -> String { Data(text.utf8).base64EncodedString() }
        let lines = ["FROSTPANE-GIFT-1", id, senderID, recipientID, base64(sender), kind.rawValue,
                     base64(note), String(style), String(size), String(mid), String(head), String(facing), base64(dress), "END"]
        let bytes = Data(lines.joined(separator: "\n").utf8)
        _ = try Self.decode(bytes)
        return bytes
    }

    static func decode(_ bytes: Data) throws -> Self {
        let invalid = GiftProblem.message("This file is not a valid Jake Frost gift.")
        guard bytes.count <= limit, let contents = String(data: bytes, encoding: .utf8) else { throw invalid }
        let lines = contents.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
        guard lines.count == 14, lines[0] == "FROSTPANE-GIFT-1", lines[13] == "END",
              validID(lines[1]), lines[2].isEmpty || validID(lines[2]), lines[3].isEmpty || validID(lines[3]),
              let kind = Kind(rawValue: lines[5]), let style = Int(lines[7]), (0...63).contains(style) else { throw invalid }
        func text(_ line: Int, max: Int) throws -> String {
            guard lines[line].utf8.count <= max * 6 + 8, let d = Data(base64Encoded: lines[line]),
                  let s = String(data: d, encoding: .utf8), s.utf16.count <= max else { throw invalid }
            return s
        }
        func number(_ line: Int, _ range: ClosedRange<Double>) throws -> Double {
            guard lines[line].count <= 32, let d = Double(lines[line]), d.isFinite, range.contains(d) else { throw invalid }
            return d
        }
        var gift = Self()
        gift.id = lines[1].lowercased(); gift.senderID = lines[2].lowercased(); gift.recipientID = lines[3].lowercased()
        gift.kind = kind; gift.style = style
        gift.sender = sanitized(try text(4, max: 32)).trimmingCharacters(in: .whitespacesAndNewlines)
        gift.note = sanitized(try text(6, max: 280)); gift.dress = try text(12, max: 8192)
        gift.size = try number(8, 3...160); gift.mid = try number(9, 1...64)
        gift.head = try number(10, 1...64); gift.facing = try number(11, -1...1)
        if kind == .snowman && (gift.size > 50 || gift.mid > gift.size || gift.head > gift.mid) { throw invalid }
        return gift
    }

    static func read(_ url: URL) throws -> Self {
        guard url.isFileURL, url.pathExtension.lowercased() == "fpgift",
              try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw GiftProblem.message("Choose a .fpgift file saved by Jake Frost.")
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        return try decode(file.read(upToCount: limit + 1) ?? Data())
    }

    static func make(_ kind: Kind, sender: String, note: String, senderID: String, template: Self?) throws -> Self {
        guard sender.utf16.count <= 32 else { throw GiftProblem.message("Use a name of up to 32 characters.") }
        guard note.utf16.count <= 280 else { throw GiftProblem.message("Keep your message to 280 characters.") }
        let message = sanitized(note).trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == .note && message.isEmpty { throw GiftProblem.message("Write a note for your friend.") }
        var gift = Self()
        if let copy = template, copy.kind == kind { gift = copy }
        if template?.kind != kind && kind == .tree {
            gift.size = 83; gift.style = 2
            gift.dress = "3,-0.13,-0.61;4,0.15,-0.47;3,-0.2,-0.32;4,0.08,-0.25;5,0,-0.97"
        }
        gift.kind = kind; gift.id = newID(); gift.senderID = senderID; gift.recipientID = ""
        let name = sanitized(sender).trimmingCharacters(in: .whitespacesAndNewlines)
        gift.sender = name.isEmpty ? "A friend" : name; gift.note = message
        _ = try gift.encoded()
        return gift
    }
}

/// Pending mail stays on disk until the train reaches its stop.
final class GiftMailbox {
    enum ImportResult { case added, pending, delivered }
    let senderID: String
    let root: URL
    private let pending: URL, received: URL
    private let files = FileManager.default

    init(root: URL) throws {
        self.root = root
        pending = root.appendingPathComponent("Pending", isDirectory: true)
        received = root.appendingPathComponent("Received", isDirectory: true)
        for folder in [pending, received] {
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let identity = root.appendingPathComponent("identity")
        if files.fileExists(atPath: identity.path) {
            let saved = try String(contentsOf: identity, encoding: .utf8)
            guard FrostGift.validID(saved) else { throw GiftProblem.message("The local gift identity could not be read.") }
            senderID = saved.lowercased()
        } else {
            senderID = FrostGift.newID()
            try senderID.write(to: identity, atomically: true, encoding: .utf8)
        }
    }

    private func url(_ id: String, in folder: URL) -> URL { folder.appendingPathComponent(id + ".fpgift") }

    func accept(_ source: URL) throws -> (ImportResult, FrostGift) {
        try accept(FrostGift.read(source))
    }

    func accept(_ gift: FrostGift) throws -> (ImportResult, FrostGift) {
        guard FrostGift.validID(gift.id) else { throw GiftProblem.message("Invalid gift identity.") }
        guard gift.recipientID.isEmpty || gift.recipientID == senderID else {
            throw GiftProblem.message("This gift is addressed to someone else. Ask the sender to save a gift file for sharing.")
        }
        if files.fileExists(atPath: url(gift.id, in: received).path) { return (.delivered, gift) }
        let target = url(gift.id, in: pending)
        if files.fileExists(atPath: target.path) { return (.pending, gift) }
        try gift.encoded().write(to: target, options: .atomic)
        return (.added, gift)
    }

    private func gifts(in folder: URL, newest: Bool) throws -> [URL] {
        let entries = try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        let dated = entries.filter { $0.pathExtension == "fpgift" }.map {
            ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast)
        }
        return dated.sorted { newest ? $0.1 > $1.1 : $0.1 < $1.1 }.map { $0.0 }
    }

    func next() throws -> FrostGift? {
        guard let first = try gifts(in: pending, newest: false).first else { return nil }
        return try FrostGift.read(first)
    }

    func latest(kind: FrostGift.Kind? = nil) throws -> FrostGift? {
        for item in try gifts(in: received, newest: true) {
            let gift = try FrostGift.read(item)
            if kind == nil || gift.kind == kind { return gift }
        }
        return nil
    }

    func acknowledge(_ gift: FrostGift) throws {
        let source = url(gift.id, in: pending), target = url(gift.id, in: received)
        if !files.fileExists(atPath: source.path) { return }
        if files.fileExists(atPath: target.path) { try files.removeItem(at: source) }
        else { try files.moveItem(at: source, to: target) }
        try? files.setAttributes([.modificationDate: Date()], ofItemAtPath: target.path)
    }
}
