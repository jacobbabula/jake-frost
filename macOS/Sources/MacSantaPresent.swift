import AppKit

/// A sleigh can leave one parcel per display each day. Its fortune is redeemed
/// across displays and app launches using the same profile as the studio.
final class MacSantaPresent {
    var settings = UserDefaults.standard
    private(set) var foot: CGPoint?
    private(set) var note = ""
    private var noteAnchor = CGPoint.zero
    private var noteTime: TimeInterval = 0
    private var dropDay: String?
    private var velocity: CGFloat = 0
    private var falling = false
    var animating: Bool { falling || noteTime > 0 }

    private static let fortunes = [
        "A window ledge is a small mountain if you are a snowflake.",
        "Leave a little room on the hill for a friend.",
        "Even the longest sleigh ride starts with one soft crunch.",
        "A crooked snowman still catches the morning light.",
        "The quietest snow can carry the brightest footsteps.",
        "Every snowbank remembers a different wind.",
        "Cold fingers make wonderfully warm gifts."
    ]

    private static func day(_ date: Date) -> (key: String, number: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return ("\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)",
                calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
    }
    func drop(at point: CGPoint, date: Date = Date()) {
        let today = Self.day(date).key
        guard foot == nil, dropDay != today else { return }
        dropDay = today
        foot = point
        velocity = 0
        falling = true
    }
    func step(_ dt: TimeInterval, world: SnowWorld) {
        if noteTime > 0 {
            noteTime = max(0, noteTime - dt)
            if noteTime == 0 { note = "" }
        }
        guard var point = foot, let floor = world.banks.first else { return }
        point.x = max(0, min(world.size.width, point.x))
        let ground = floor.surface(point.x)
        velocity = min(150, velocity + CGFloat(dt) * 125)
        point.y = min(ground, point.y + velocity * CGFloat(dt))
        falling = point.y < ground
        if !falling { velocity = 0 }
        foot = point
    }
    func captures(_ point: CGPoint) -> Bool {
        guard let foot = foot else { return false }
        return abs(point.x - foot.x) <= 13 && point.y >= foot.y - 26 && point.y <= foot.y + 1
    }
    @discardableResult func open(at point: CGPoint, world: SnowWorld, date: Date = Date()) -> Bool {
        guard captures(point), let foot = foot else { return false }
        let today = Self.day(date), preference = "jakefrost.santa.last-opened-day"
        if settings.string(forKey: preference) == today.key {
            note = "Santa already left you a note today."
        } else {
            settings.set(today.key, forKey: preference)
            note = Self.fortunes[today.number % Self.fortunes.count]
        }
        noteAnchor = CGPoint(x: foot.x, y: foot.y - 32)
        noteTime = 9
        world.burst(CGPoint(x: foot.x, y: foot.y - 12), count: 17, strength: 0.7)
        self.foot = nil
        falling = false
        return true
    }
    func plow(_ blade: PlowSweep, world: SnowWorld) {
        guard var point = foot, let floor = world.banks.first else { return }
        let box = CGRect(x: point.x - 12, y: point.y - 22, width: 24, height: 22)
        guard blade.touches(box, includingSnow: abs(point.y - floor.surface(point.x)) < 6,
                            ink: { _ in true }) else { return }
        point.x = max(12, min(max(12, world.size.width - 12), point.x + blade.advance))
        point.y = min(point.y, floor.surface(point.x))
        foot = point
    }
    func clear() {
        if foot != nil { dropDay = nil }
        foot = nil
        falling = false
        note = ""
        noteTime = 0
    }

    func draw(in bounds: CGRect) {
        if let p = foot {
            func fill(_ rect: CGRect, _ color: NSColor, radius: CGFloat = 0) {
                color.setFill()
                NSBezierPath(roundedRect: rect.offsetBy(dx: p.x, dy: p.y), xRadius: radius, yRadius: radius).fill()
            }
            let ribbon = NSColor(srgbRed: 0.98, green: 0.8, blue: 0.39, alpha: 1)
            fill(CGRect(x:-12,y:-20,width:24,height:20), NSColor(srgbRed:0.62,green:0.19,blue:0.23,alpha:1), radius:2)
            fill(CGRect(x:-13,y:-22,width:26,height:5), NSColor(srgbRed:0.84,green:0.33,blue:0.32,alpha:1), radius:1.5)
            fill(CGRect(x:-2,y:-22,width:4,height:22), ribbon)
            fill(CGRect(x:-1.5,y:-21,width:0.8,height:20), NSColor(srgbRed:1,green:0.92,blue:0.72,alpha:1))
            let bow = NSBezierPath()
            for sign: CGFloat in [-1,1] {
                bow.move(to: CGPoint(x:p.x,y:p.y-22))
                bow.curve(to: CGPoint(x:p.x+sign*7,y:p.y-26),
                          controlPoint1: CGPoint(x:p.x+sign*2,y:p.y-27), controlPoint2: CGPoint(x:p.x+sign*8,y:p.y-29))
                bow.curve(to: CGPoint(x:p.x,y:p.y-22),
                          controlPoint1: CGPoint(x:p.x+sign*7,y:p.y-24), controlPoint2: CGPoint(x:p.x+sign*4,y:p.y-22))
            }
            ribbon.setStroke(); bow.lineWidth=1.6; bow.stroke()
        }
        guard noteTime > 0, bounds.width > 20 else { return }
        let alpha = CGFloat(min(1,noteTime*2))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key:Any] = [
            .font:NSFont.systemFont(ofSize:12,weight:.medium),
            .foregroundColor:NSColor.white.withAlphaComponent(alpha),
            .paragraphStyle:paragraph
        ]
        let text = note as NSString
        let width = max(1, min(250,bounds.width-28))
        let size = text.boundingRect(with: CGSize(width:width,height:300), options:[.usesLineFragmentOrigin,.usesFontLeading], attributes:attrs).integral.size
        let w = size.width+18, h=size.height+12
        let x = max(4,min(bounds.maxX-w-4,noteAnchor.x-w/2)), y=max(2,min(bounds.maxY-h-2,noteAnchor.y-h))
        let box=CGRect(x:x,y:y,width:w,height:h)
        NSColor(srgbRed:0.12,green:0.2,blue:0.29,alpha:0.9*alpha).setFill()
        NSBezierPath(roundedRect:box,xRadius:8,yRadius:8).fill()
        text.draw(with:box.insetBy(dx:9,dy:6),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attrs)
    }
}
