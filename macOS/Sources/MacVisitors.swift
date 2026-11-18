import AppKit

enum MacVisitorKind: String, CaseIterable {
    case snowplow = "Snowplow", yeti = "Yeti", santa = "Santa and reindeer", snowmen = "Snowmen", train = "Elf train"

    fileprivate var spriteBounds: CGRect {
        switch self {
        case .snowplow: return CGRect(x:-36, y:-42, width:83, height:45)
        case .yeti: return CGRect(x:-29, y:-65, width:61, height:68)
        case .santa: return CGRect(x:-63, y:-57, width:151, height:64)
        case .snowmen: return CGRect(x:-29, y:-54, width:61, height:57)
        case .train: return .zero
        }
    }

    fileprivate var pointsPerSecond: CGFloat {
        switch self {
        case .snowplow: return 41
        case .yeti: return 31
        case .santa: return 58
        case .snowmen: return 34
        case .train: return 64
        }
    }
}

@MainActor final class MacVisitorControls: NSObject {
    private struct Choice { let kind: MacVisitorKind; let setting: String; let value: Int }
    private static let sizes = [50,75,100,125,150,200,250]
    private static let speeds = ["Leisurely","Steady","Brisk"]
    private let settings: UserDefaults
    private let summon: (MacVisitorKind) -> Void
    private let onChange: () -> Void
    private var visitorItem: NSMenuItem?
    private var nextPlow = Date().addingTimeInterval(15*60)
    private var nextSanta = Date().addingTimeInterval(2*60*60)
    func scheduledVisits(now:Date = Date(),allow:Bool) {
        guard allow,settings.bool(forKey:"automaticVisits") else {return}
        if now >= nextPlow {nextPlow=now.addingTimeInterval(20*60);summon(.snowplow)}
        if now >= nextSanta {nextSanta=now.addingTimeInterval(3*60*60);summon(.santa)}
    }
    @objc private func toggleVisits(_ sender:NSMenuItem) {
        let enabled = !settings.bool(forKey:"automaticVisits")
        settings.set(enabled,forKey:"automaticVisits");sender.state=enabled ? .on:.off
        nextPlow=Date().addingTimeInterval(15*60);nextSanta=Date().addingTimeInterval(2*60*60)
    }

    init(settings: UserDefaults, summon: @escaping (MacVisitorKind) -> Void, onChange: @escaping () -> Void) {
        self.settings = settings; self.summon = summon; self.onChange = onChange
    }
    private func value(_ kind: MacVisitorKind, _ setting: String) -> Int {
        let key = "visitors.\(kind.rawValue).\(setting)"
        if let stored = settings.object(forKey:key) as? NSNumber {
            let options = setting == "size" ? Self.sizes : [0,1,2]
            if options.contains(stored.intValue) { return stored.intValue }
        }
        return setting == "size" ? 100 : 0
    }
    func scale(for kind: MacVisitorKind) -> CGFloat { CGFloat(value(kind, "size")) / 100 }
    func pace(for kind: MacVisitorKind) -> CGFloat { [1,1.45,1.95][value(kind,"speed")] }

    private func submenu(_ title:String, in parent:NSMenu) -> NSMenu {
        let child = NSMenu(title:title)
        let item = NSMenuItem(title:title, action:nil, keyEquivalent:"")
        item.submenu = child; parent.addItem(item)
        return child
    }
    func append(to menu:NSMenu) {
        if let item = visitorItem {
            if item.menu !== menu {
                item.menu?.removeItem(item)
                menu.addItem(item)
            }
            return
        }
        let visitors = submenu("Visitors", in:menu)
        visitorItem = menu.items.last
        for kind in MacVisitorKind.allCases {
            let item = NSMenuItem(title:"Send " + kind.rawValue, action:#selector(send(_:)), keyEquivalent:"")
            item.target = self; item.representedObject = kind; visitors.addItem(item)
        }
        visitors.addItem(.separator())
        let automatic=NSMenuItem(title:"Occasional snowplow and Santa visits",action:#selector(toggleVisits(_:)),keyEquivalent:"")
        automatic.target=self;automatic.state=settings.bool(forKey:"automaticVisits") ? .on:.off
        visitors.addItem(automatic)
        for setting in ["size","speed"] {
            let section = submenu(setting == "size" ? "Visitor sizes" : "Visitor speeds", in:visitors)
            for kind in MacVisitorKind.allCases {
                let options = submenu(kind.rawValue, in:section)
                let selected = value(kind,setting)
                for index in (setting == "size" ? Self.sizes : [0,1,2]) {
                    let title = setting == "size" ? "\(index)%" : Self.speeds[index]
                    let entry = NSMenuItem(title:title, action:#selector(selectOption(_:)), keyEquivalent:"")
                    entry.target = self
                    entry.representedObject = Choice(kind:kind,setting:setting,value:index)
                    entry.state = selected == index ? .on : .off
                    options.addItem(entry)
                }
            }
        }
    }
    @objc private func send(_ item:NSMenuItem) {
        if let kind = item.representedObject as? MacVisitorKind { summon(kind) }
    }
    @objc private func selectOption(_ item:NSMenuItem) {
        guard let choice = item.representedObject as? Choice else { return }
        settings.set(choice.value,forKey:"visitors.\(choice.kind.rawValue).\(choice.setting)")
        if let siblings = item.menu?.items {
            for sibling in siblings { sibling.state = sibling === item ? .on : .off }
        }
        onChange()
    }
}

@MainActor final class MacVisitors {
    private final class Visit {
        let kind: MacVisitorKind
        var x: CGFloat, y: CGFloat = 0, distance: CGFloat = 0, angle: CGFloat = 0
        var powderBudget: CGFloat = 0
        let direction:CGFloat,load=MacPlowLoad()
        var yeti:MacYeti?,dropped=false
        init(_ kind: MacVisitorKind, x: CGFloat,direction:CGFloat) { self.kind = kind; self.x = x;self.direction=direction }
    }
    private var active = [Visit]()
    private var scales = [MacVisitorKind:CGFloat]()
    private var speeds = [MacVisitorKind:CGFloat]()
    private var nextPlow:CGFloat=1,nextYeti:CGFloat=1
    weak var workshop:MacWorkshop?
    var onSantaDrop:((CGPoint)->Void)?
    var onPlow:((PlowSweep)->Void)?
    var wildCount:Int {active.filter{$0.yeti?.wild==true}.count}
    var yetis:[MacYeti] {active.compactMap(\.yeti)}
    var pushWorkshop: ((PlowSweep) -> Void)?
    var finishPlowing: (() -> Void)?
    private var pushedFigure = false
    private(set) var plowPose: (x:CGFloat,y:CGFloat,angle:CGFloat)?
    var isActive: Bool { !active.isEmpty }

    func configure(_ controls: MacVisitorControls) {
        for kind in MacVisitorKind.allCases { scales[kind] = controls.scale(for:kind); speeds[kind] = controls.pace(for:kind) }
    }
    func clear() { active.removeAll(keepingCapacity:true);plowPose=nil;finishPlowing?();pushedFigure=false }
    func summon(_ kind: MacVisitorKind, in world: SnowWorld) {
        let direction:CGFloat
        switch kind {
        case .snowplow: direction=nextPlow;nextPlow *= -1
        case .yeti: direction=nextYeti;nextYeti *= -1
        default: direction=1
        }
        enter(kind,world:world,direction:direction,wild:false)
    }
    func summonWild(in world:SnowWorld,direction:CGFloat) {
        if wildCount<3 {enter(.yeti,world:world,direction:direction<0 ? -1:1,wild:true)}
    }
    func clearWild() {active.removeAll{$0.yeti?.wild==true}}
    private func enter(_ kind:MacVisitorKind,world:SnowWorld,direction:CGFloat,wild:Bool) {
        guard kind != .train, world.size.width > 1, active.count < 8 else { return }
        let scale = scales[kind] ?? 1
        let offset=kind.spriteBounds.maxX*scale-2
        var x=direction>0 ? -offset:world.size.width+offset
        // Leave cars room to enter even if the same menu command is used repeatedly.
        if let last = active.last(where:{ $0.kind == kind && $0.direction==direction }) {
            let margin=kind.spriteBounds.width*scale+8
            x=direction>0 ? min(x,last.x-margin):max(x,last.x+margin)
        }
        let visit = Visit(kind,x:x,direction:direction)
        if kind == .yeti {visit.yeti=MacYeti(x:x,facing:direction,wild:wild)}
        position(visit,world:world,scale:scale)
        active.append(visit)
    }
    private func position(_ v: Visit, world: SnowWorld, scale: CGFloat) {
        if v.kind == .santa {
            let clearance = -v.kind.spriteBounds.minY * scale
            let band = min(world.size.height - 2, max(clearance,world.size.height * 0.29))
            v.y = band + 5 * sin(v.distance / 65)
            v.angle = 0.027 * cos(v.distance / 65)
        } else if let ground = world.banks.first {
            if v.kind == .snowplow {
                // Heavy tires run in the shallow lane shaved by the steel lip.
                // Narrow untouched peaks outside that lane cannot lever the chassis up.
                func tire(_ at:CGFloat) -> CGFloat {
                    let shoulder=3.5*scale
                    let packed=(ground.height(at-shoulder)+2*ground.height(at)+ground.height(at+shoulder))/4
                    return ground.edge.y-min(1.1,max(0,packed))
                }
                let left=tire(v.x-19*scale), right=tire(v.x+16*scale)
                v.angle=atan((right-left)/(35*scale))
                v.y=(left*16+right*19)/35
                plowPose=(v.x,v.y,v.angle)
                return
            }
            let span: CGFloat = 6 * scale
            let left = ground.surface(v.x-span), right = ground.surface(v.x+span)
            v.angle = atan(max(-0.3,min(0.3,(right-left)/(span*2))))
            v.y = min(left + sin(v.angle)*span, right - sin(v.angle)*span)
        }
    }
    func step(_ seconds: TimeInterval, world: SnowWorld) {
        world.battlePace=speeds[.snowmen] ?? 1
        guard !active.isEmpty else { return }
        let dt = CGFloat(max(0,min(0.1,seconds)))
        for v in active {
            let scale = scales[v.kind] ?? 1
            let displacement = v.kind.pointsPerSecond * (speeds[v.kind] ?? 1) * dt
            let old = CGPoint(x:v.x,y:v.y), oldAngle = v.angle
            if let yeti=v.yeti {
                yeti.step(dt,scale:scale,pace:speeds[.yeti] ?? 1,world:world,workshop:workshop)
                v.x=yeti.x;v.y=yeti.y;continue
            }
            v.x += displacement*v.direction; v.distance += displacement
            if v.kind == .snowplow, let ground = world.banks.first {
                position(v,world:world,scale:scale)
                var blade=PlowSweep(from:old,angle:oldAngle,to:CGPoint(x:v.x,y:v.y),angle:v.angle,
                                    scale:scale,speed:v.kind.pointsPerSecond*(speeds[v.kind] ?? 1),direction:v.direction)
                let bladeX=v.direction>0 ? blade.bounds.maxX:blade.bounds.minX,rear=old.x-v.direction*27*scale
                if max(bladeX,rear)>=0 && min(bladeX,rear)<=world.size.width {
                    let contact=ground.surface(bladeX)
                    let removed=ground.plowLane(rear:rear,lip:bladeX,scale:scale,load:v.load)
                    blade.carryingSnow(on:ground,scale:scale)
                    if removed > 0 {
                        v.powderBudget = min(12,v.powderBudget+removed*0.38)
                        let flakes = Int(v.powderBudget)
                        if flakes >= 2 {
                            world.burst(CGPoint(x:bladeX,y:max(v.y-20*scale,contact-1)),count:flakes,strength:0.65)
                            v.powderBudget -= CGFloat(flakes)
                        }
                    }
                    if world.plowObjects(blade) {pushedFigure=true}
                    pushWorkshop?(blade)
                    onPlow?(blade)
                }
            }
            if v.kind != .snowplow {position(v,world:world,scale:scale)}
            if !v.dropped && v.x>=world.size.width*0.48 {
                v.dropped=true
                if v.kind == .santa {onSantaDrop?(CGPoint(x:v.x,y:v.y))}
                if v.kind == .snowmen {world.dropVisitorSnowman(at:v.x,scale:scale)}
            }
        }
        let hadPlow=plowPose != nil
        active.removeAll { visit in
            let margin = -visit.kind.spriteBounds.minX*(scales[visit.kind] ?? 1)
            return visit.direction>0 ? visit.x-margin>world.size.width:visit.x+margin<0
        }
        if hadPlow && !active.contains(where:{$0.kind == .snowplow}) {
            plowPose=nil
            if pushedFigure {world.rememberSnowmenNow();pushedFigure=false}
            finishPlowing?()
        }
    }
    func draw(in c: CGContext) {
        for visitor in active {
            let scale = scales[visitor.kind] ?? 1
            if let yeti=visitor.yeti {yeti.draw(in:c,scale:scale);continue}
            // One complete gait per stride. Treads and boots keep pace as their size changes.
            let stride: CGFloat = visitor.kind == .snowplow ? 42 : visitor.kind == .santa ? 47 : 27
            let frame = Int(visitor.distance * 8 / (stride * scale)) % 8
            c.saveGState(); c.translateBy(x:visitor.x,y:visitor.y)
            c.rotate(by:visitor.angle); c.scaleBy(x:scale*visitor.direction,y:scale)
            VisitorArt.draw(visitor.kind,frame:frame,in:c)
            c.restoreGState()
        }
    }
}

/// Eight transparent poses per character, shared across displays. Shape construction occurs
/// only when a pose is first used. Terrain, gait, contact and screen position stay independent.
@MainActor private struct VisitorArt {
    private static let frameKeys = Dictionary(uniqueKeysWithValues: MacVisitorKind.allCases.map { kind in
        (kind, (0..<8).map { "\(kind.rawValue)/\($0)" as NSString })
    })
    private static let atlas: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString,CGImage>()
        cache.totalCostLimit = 28 * 1024 * 1024
        return cache
    }()
    let c: CGContext
    static func draw(_ kind: MacVisitorKind, frame: Int, in c: CGContext) {
        guard let keys = frameKeys[kind] else { return }
        let box = kind.spriteBounds, key = keys[frame]
        var sprite = atlas.object(forKey:key)
        if sprite == nil {
            let density = 3, w = Int(box.width)*density, h = Int(box.height)*density
            guard let bitmap = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
                    space:CGColorSpaceCreateDeviceRGB(), bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            bitmap.translateBy(x:0,y:CGFloat(h)); bitmap.scaleBy(x:CGFloat(density),y:-CGFloat(density))
            bitmap.translateBy(x:-box.minX,y:-box.minY); bitmap.setLineCap(.round); bitmap.setLineJoin(.round)
            let art = VisitorArt(c:bitmap), phase = CGFloat(frame)*(.pi/4)
            switch kind {
            case .snowplow: art.plow(phase)
            case .yeti: return // The planted feet and upper body render independently.
            case .santa: art.sleigh(phase)
            case .snowmen: art.snowmen(phase)
            case .train: return
            }
            sprite = bitmap.makeImage()
            if let image = sprite { atlas.setObject(image,forKey:key,cost:image.bytesPerRow*image.height) }
        }
        if let image = sprite {
            c.saveGState(); c.translateBy(x:box.minX,y:box.maxY); c.scaleBy(x:1,y:-1)
            c.interpolationQuality = .high
            c.draw(image,in:CGRect(origin:.zero,size:box.size)); c.restoreGState()
        }
    }
    private func ink(_ rgb: Int, stroke: Bool = false) {
        let r=CGFloat(rgb>>16 & 255)/255, g=CGFloat(rgb>>8 & 255)/255, b=CGFloat(rgb & 255)/255
        if stroke { c.setStrokeColor(red:r,green:g,blue:b,alpha:1) }
        else { c.setFillColor(red:r,green:g,blue:b,alpha:1) }
    }
    private func oval(_ color:Int,_ x:CGFloat,_ y:CGFloat,_ rx:CGFloat,_ ry:CGFloat) {
        ink(color); c.fillEllipse(in:CGRect(x:x-rx,y:y-ry,width:2*rx,height:2*ry))
    }
    private func rect(_ color:Int,_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat,_ radius:CGFloat) {
        ink(color); c.addPath(CGPath(roundedRect:CGRect(x:x,y:y,width:w,height:h),cornerWidth:radius,cornerHeight:radius,transform:nil)); c.fillPath()
    }
    private func poly(_ color:Int,_ points:[(CGFloat,CGFloat)]) {
        guard let first = points.first else { return }
        ink(color); c.beginPath(); c.move(to:CGPoint(x:first.0,y:first.1))
        for p in points.dropFirst() { c.addLine(to:CGPoint(x:p.0,y:p.1)) }
        c.closePath(); c.fillPath()
    }
    private func stroke(_ color:Int,_ width:CGFloat,_ points:[(CGFloat,CGFloat)]) {
        guard let first = points.first else { return }
        ink(color,stroke:true); c.setLineWidth(width); c.beginPath(); c.move(to:CGPoint(x:first.0,y:first.1))
        for p in points.dropFirst() { c.addLine(to:CGPoint(x:p.0,y:p.1)) }
        c.strokePath()
    }
    private func plow(_ p:CGFloat) {
        // Spreader, glazed cab, rotating hubs, hydraulic lift, curved steel blade.
        poly(0x324352,[(-32,-27),(-10,-27),(-12,-14),(-26,-14)])
        poly(0xE69432,[(-32,-28),(-11,-28),(-14,-20),(-28,-20)])
        rect(0xD5E7EA,-34,-30,25,3,1)
        for x in [-27,-21,-15] { stroke(0xA9652D,1.5,[(CGFloat(x),-26),(CGFloat(x-2),-21)]) }
        rect(0x314956,-31,-16,59,8,2)
        poly(0xCC602D,[(-11,-32),(-7,-36),(8,-36),(16,-24),(26,-22),(27,-13),(-12,-13)])
        poly(0xF2A045,[(-8,-32),(-5,-34),(7,-34),(14,-23),(24,-22),(24,-17),(-9,-17)])
        poly(0x3A5765,[(-6,-32),(6,-32),(12,-24),(-6,-24)])
        poly(0x89C2D1,[(-4,-31),(4,-31),(9,-25),(-4,-25)])
        stroke(0xE1F1F0,1,[(-2,-26),(2,-30)])
        rect(0xF0F3E8,-10,-36,22,2.5,1)
        rect(0x3F505C,-3,-39,7,3,1)
        oval(cos(p)>0 ? 0xFFE091:0xF7A742,0.5,-39,2,1.6)
        rect(0xFFF1B3,21,-22,4,2.7,0.7); rect(0x405661,-8,-22,4,1.5,0.5)
        for x:CGFloat in [-19,16] {
            oval(0x253946,x,-7,7.3,7.3); oval(0x59717B,x,-7,5.25,5.25)
            oval(0xBCCDD0,x,-7,3.3,3.3); oval(0x4B646D,x,-7,1.3,1.3)
            for index in 0..<4 {
                let a=p+CGFloat(index)*(.pi/2)
                oval(0xDAC29B,x+cos(a)*2.2,-7+sin(a)*2.2,0.55,0.55)
            }
        }
        stroke(0x5C7179,2.6,[(23,-9),(29,-7),(31,-11)])
        poly(0x536A73,[(30.6,-14),(34.6,-14.2),(31.6,-8),(33.4,-2.6),(35.8,-0.3),(31.9,-0.3),(28.5,-7.7)])
        stroke(0xC1D9D9,1.5,[(34,-13.5),(31,-8),(32.8,-2.7),(35.2,-0.9)])
        stroke(0xF9B65D,1.8,[(30.5,-14.2),(34.8,-14.2)])
    }
    private func sleigh(_ p:CGFloat) {
        // Runners and sleigh follow the rein; reindeer legs gallop independently.
        stroke(0xE6C47D,1.2,[(-18,-24),(4,-13+sin(p)),(26,-12),(54,-22)])
        stroke(0xA87C4F,0.9,[(-17,-22),(7,-12+sin(p)),(29,-11),(54,-20)])
        c.saveGState(); c.translateBy(x:43,y:-12+sin(p)*2)
        for limb in 0..<4 {
            let phase = p + CGFloat(limb)*(.pi*0.56)
            let root:CGFloat = limb < 2 ? -11:7
            let knee = root + sin(phase)*5, toe=knee + cos(phase)*4
            stroke(limb%2==0 ? 0x875C48:0xB98056,2.9,[(root,-1),(knee,5),(toe,11+cos(phase)*2)])
            stroke(0x473F40,2.3,[(toe,11+cos(phase)*2),(toe+2,11+cos(phase)*2)])
        }
        oval(0xB98054,-1,-3,16,7.2)
        poly(0xB98054,[(4,-4),(10,-15),(14,-22),(19,-20),(17,-12),(11,-1)])
        poly(0xE4B779,[(8,-2),(13,-13),(15,-11),(12,-3)])
        oval(0xBF895C,19,-18,7,5); oval(0xD8A773,24,-16.6,5,2.9)
        oval(0xCD4D43,28,-17,1.9,1.8); oval(0x373B3F,21,-19.5,1,1)
        poly(0xA46E4D,[(15,-21),(10,-27),(15,-25),(18,-21)])
        stroke(0x805A3F,1.9,[(18,-22),(16,-29),(20,-35)]); stroke(0x805A3F,1.6,[(16,-29),(12,-31),(11,-35)])
        stroke(0x805A3F,1.4,[(18,-32),(22,-32),(24,-35)])
        poly(0xF2E1B9,[(-15,-5),(-18,-12),(-13,-10),(-10,-7)])
        stroke(0xA94437,2.6,[(10,-12),(14,-9)]); oval(0xF2C75E,13,-8,1.6,1.6)
        c.restoreGState()
        stroke(0xD9AD64,2.2,[(-52,-2),(-43,-1),(-15,-1),(-5,-3),(-2,-7)])
        stroke(0xC49D63,1.9,[(-46,-4),(-42,-10)]); stroke(0xC49D63,1.9,[(-18,-3),(-22,-11)])
        oval(0x617954,-48,-20,9,11); poly(0x809165,[(-52,-28),(-55,-34),(-47,-32),(-44,-35),(-45,-28)])
        oval(0xB63F3D,-33,-22,8,11); oval(0xEDC298,-30,-32,5.4,5.6)
        poly(0xB34140,[(-37,-36),(-37,-42),(-42,-38),(-39,-46),(-33,-44),(-26,-36)])
        oval(0xFBF1DB,-41,-38,2,2); rect(0xFFF2D9,-37,-37.4,11,3,1.5)
        oval(0xF5E8CD,-29,-28.6,5.2,4.7); oval(0xC98D76,-25,-31.3,1.9,1.4)
        stroke(0xB23F3E,3.8,[(-32,-23),(-24,-23),(-20,-26)]); oval(0xE3C9A4,-19,-26,2.2,2.1)
        poly(0x933E3F,[(-58,-25),(-49,-20),(-25,-17),(-15,-19),(-10,-24),(-5,-25),(-8,-16),(-17,-9),(-44,-9),(-54,-14)])
        poly(0xC05145,[(-51,-19),(-26,-15),(-14,-18),(-18,-12),(-43,-12)])
        stroke(0xE9BE71,1.4,[(-57,-24),(-49,-20),(-26,-17),(-15,-19),(-9,-25),(-5,-25)])
    }
    private func snowmen(_ p:CGFloat) {
        snowFriend(at:-14,scale:0.72,phase:p + .pi,scarf:0xC65D54)
        snowFriend(at:9,scale:1,phase:p,scarf:0x447F81)
    }
    private func snowFriend(at x:CGFloat,scale:CGFloat,phase:CGFloat,scarf:Int) {
        c.saveGState(); c.translateBy(x:x,y:0); c.scaleBy(x:scale,y:scale)
        let swing=sin(phase)*3
        oval(0x48555C,-5+swing,-2,4.6,1.9); oval(0x48555C,5-swing,-2,4.6,1.9)
        c.translateBy(x:0,y:-abs(cos(phase)))
        stroke(0x705C49,1.8,[(-6,-20),(-13,-23+swing),(-15,-27+swing)])
        stroke(0x705C49,1.4,[(-13,-23+swing),(-16,-23+swing)])
        stroke(0x705C49,1.8,[(6,-20),(11,-21-swing),(15,-25-swing)])
        for (r,y): (CGFloat,CGFloat) in [(10,-11),(8,-23),(6.7,-33.5)] {
            oval(0xB8D3DC,0,y,r,r); oval(0xF2F6EE,-0.6,y-0.5,r*0.90,r*0.91)
        }
        for y:CGFloat in [-24,-20,-13] { oval(0x43535C,1,y,1,1) }
        rect(scarf,-6.9,-29.6,14.3,3.4,1.4)
        poly(scarf,[(-1,-28),(-3,-21),(-6,-22),(-5,-28)])
        oval(0x3F4D52,1,-34.7,0.8,1); oval(0x3F4D52,4.7,-34.7,0.75,1)
        poly(0xD98B48,[(3,-33.5),(10,-32.6),(4,-31.8)])
        rect(0x3A505C,-5.4,-47,9.4,9,1); rect(scarf,-5.4,-41,9.4,2,0)
        rect(0x374852,-8,-39,15,2.1,0.9); c.restoreGState()
    }
}
