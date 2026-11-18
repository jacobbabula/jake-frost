import Foundation

enum MacSceneMemory {
    private static func isSceneKey(_ key: String) -> Bool {
        key.hasPrefix("workshop.v1.") || key.hasPrefix("snowmen.v1.") || key.hasPrefix("parcels.v1.")
    }
    static func remembers(_ settings: UserDefaults) -> Bool {
        settings.object(forKey: "rememberScene") == nil || settings.bool(forKey: "rememberScene")
    }
    static func setRemember(_ enabled: Bool, settings: UserDefaults) {
        settings.set(enabled, forKey: "rememberScene")
        if !enabled {
            // Also forget arrangements belonging to currently disconnected displays.
            for key in settings.dictionaryRepresentation().keys where isSceneKey(key) {
                settings.removeObject(forKey: key)
            }
        }
    }
    static func containsGift(_ id: String, in settings: UserDefaults, excluding displays: Set<UInt32>) -> Bool {
        guard remembers(settings), FrostGift.validID(id) else { return false }
        struct Origin: Decodable { let giftID: String? }
        struct Arrangement: Decodable { let pieces: [Origin] }
        let token = Data(id.utf8), decoder = JSONDecoder()
        for (key,value) in settings.dictionaryRepresentation() where isSceneKey(key) {
            guard let suffix=key.split(separator:".").last, let display=UInt32(suffix), !displays.contains(display),
                  let data=value as? Data, data.count <= (key.hasPrefix("parcels.") ? 1_400_000 : 120_000),
                  data.range(of:token) != nil else { continue }
            let records = key.hasPrefix("workshop.") ? (try? decoder.decode(Arrangement.self,from:data))?.pieces :
                (try? decoder.decode([Origin].self,from:data))
            if records?.contains(where:{ $0.giftID == id }) == true { return true }
        }
        return false
    }
}

struct SavedSnowman: Codable {
    let x, foot, base, middle, head, facing: CGFloat
    let style: Int
    let support: UInt32?
    let fraction: CGFloat
    let giftID: String?

    init(_ figure: BuiltSnowman, desktop: CGSize) {
        x = max(0, min(1, figure.x / desktop.width))
        foot = max(0, min(1, figure.foot / desktop.height))
        base = figure.base; middle = figure.middle; head = figure.head
        facing = figure.facing; style = figure.style
        support = figure.support
        giftID = figure.giftID
        fraction = max(0, min(1, figure.supportFraction))
    }
    var valid: Bool {
        (0...1).contains(x) && (0...1).contains(foot) && (0...1).contains(fraction)
            && (3...50).contains(base) && middle >= 1 && middle <= base && head >= 1 && head <= middle
            && (0...63).contains(style) && (-1...1).contains(facing)
    }
}

final class SnowmanStore {
    let settings: UserDefaults, key: String
    var loaded = false
    init(settings: UserDefaults, displayID: UInt32) {
        self.settings = settings; key = "snowmen.v1.\(displayID)"
    }
    func restore(in size: CGSize, banks: [Drift]) -> [BuiltSnowman] {
        guard !loaded, size.width > 1, size.height > 1, !banks.isEmpty else { return [] }
        loaded = true
        guard MacSceneMemory.remembers(settings), let data = settings.data(forKey: key), data.count <= 48_000,
              let saved = try? JSONDecoder().decode([SavedSnowman].self, from: data) else { return [] }
        return saved.prefix(55).filter { $0.valid }.map { record in
            let figure = BuiltSnowman(saved: record, desktop: size)
            guard let id = record.support else { return figure }
            let exact = banks.first { $0.edge.id == id && $0.edge.contains($0.edge.x+record.fraction*$0.edge.width) }
            // If macOS assigned a new window number after login, a ledge under the
            // saved foot can still support the snowman. A closed window lets it fall.
            let bank = exact ?? banks.filter { $0.edge.id != 0 && $0.edge.contains(figure.x) &&
                abs($0.surface(figure.x)-figure.foot) <= 18
            }.min { abs($0.surface(figure.x)-figure.foot) < abs($1.surface(figure.x)-figure.foot) }
            if let bank = bank {
                if exact != nil { figure.x = bank.edge.x + record.fraction * bank.edge.width }
                figure.support = bank.edge.id
                figure.supportFraction = (figure.x-bank.edge.x)/bank.edge.width
                figure.foot = bank.surface(figure.x)
            }
            return figure
        }
    }
    func save(_ figures: [BuiltSnowman], size: CGSize) {
        guard loaded, MacSceneMemory.remembers(settings), size.width > 1, size.height > 1 else { return }
        if figures.isEmpty { clear(); return }
        let records = figures.prefix(55).map { SavedSnowman($0, desktop: size) }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        if let data = try? encoder.encode(records), data != settings.data(forKey: key) {
            settings.set(data, forKey: key)
        }
    }
    func clear() {
        loaded = true
        if settings.object(forKey: key) != nil { settings.removeObject(forKey: key) }
    }
}
