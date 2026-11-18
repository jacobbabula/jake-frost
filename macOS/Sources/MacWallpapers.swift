import AppKit
import ImageIO
import QuartzCore

enum MacLandscape: String, CaseIterable {
    case system = "System wallpaper", switchback = "Switchback Station", lantern = "Lantern Sound"
    var resource: String { self == .switchback ? "Switchback" : "Lantern" }
}
enum MacLighting: String, CaseIterable {
    case clock = "Follow local time", dawn = "Dawn", morning = "Morning", midday = "Midday"
    case golden = "Golden hour", dusk = "Dusk", night = "Night"
    func hour(at date: Date) -> CGFloat {
        if self == .clock {
            let parts=Calendar.current.dateComponents([.hour,.minute],from:date)
            return CGFloat(parts.hour ?? 12)+CGFloat(parts.minute ?? 0)/60
        }
        switch self {
        case .dawn:return 6
        case .morning:return 9
        case .midday:return 12
        case .golden:return 17.5
        case .dusk:return 19.4
        default:return 0
        }
    }
}
private struct WallpaperLight: Equatable {
    let dark, warmth: CGFloat
    init(hour:CGFloat) {
        func smooth(_ x:CGFloat)->CGFloat {let t=max(0,min(1,x));return t*t*(3-2*t)}
        dark=1-smooth((hour-4.7)/3.6)*(1-smooth((hour-17.0)/3.8))
        let dawn=(hour-6.7)/1.4, dusk=(hour-17.9)/1.45
        warmth=max(exp(-dawn*dawn),exp(-dusk*dusk))
    }
}

@MainActor private final class LandscapePainting {
    let day, night: CGImage
    init?(_ scene: MacLandscape) {
        func read(_ suffix:String)->CGImage? {
            guard let url=Bundle.main.url(forResource:scene.resource+suffix,withExtension:"jpg",subdirectory:"Wallpapers"),
                  let src=CGImageSourceCreateWithURL(url as CFURL,nil) else{return nil}
            return CGImageSourceCreateImageAtIndex(src,0,[kCGImageSourceShouldCacheImmediately:true] as CFDictionary)
        }
        guard scene != .system, let a=read(""),let b=read("Night") else{return nil}
        day=a;night=b
    }
}

@MainActor private final class WallpaperMotion: NSView {
    var scene=MacLandscape.switchback, dark:CGFloat=0, seconds:CGFloat=0
    override var isFlipped:Bool {true}
    private static let colors=CGColorSpaceCreateDeviceRGB()
    private static func glow(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat)->CGGradient {
        CGGradient(colorsSpace:colors,colors:[CGColor(red:r,green:g,blue:b,alpha:1),CGColor(red:r,green:g,blue:b,alpha:0)] as CFArray,locations:[0,1])!
    }
    private static let mist=glow(0.90,0.93,0.97), lamp=glow(1,0.83,0.49)
    override func draw(_ dirtyRect:NSRect) {
        guard let c=NSGraphicsContext.current?.cgContext else{return}
        NSColor.clear.setFill();dirtyRect.fill(using:.copy)
        let w:CGFloat=1672,h:CGFloat=941,k=max(bounds.width/w,bounds.height/h)
        guard k>0 else{return}
        c.saveGState();defer{c.restoreGState()}
        c.translateBy(x:(bounds.width-w*k)/2,y:(bounds.height-h*k)/2);c.scaleBy(x:k,y:k)
        let t=seconds
        if scene == .switchback {
            for i in 0..<13 {
                let f=(t*0.092+CGFloat(i)/13).truncatingRemainder(dividingBy:1)
                let x=1511-77*f+8*f*sin(t*0.36+CGFloat(i)*0.7), y=151-105*f
                c.saveGState();c.translateBy(x:x,y:y);c.scaleBy(x:5+21*f,y:4+14*f);c.setAlpha(0.29*sin(.pi*f))
                c.drawRadialGradient(Self.mist,startCenter:.zero,startRadius:0,endCenter:.zero,endRadius:1,options:[])
                c.restoreGState()
            }
        } else {
            let sweep=cos(t*0.51)
            c.saveGState();c.translateBy(x:1356,y:282);c.scaleBy(x:sweep,y:0.7+abs(sweep)*0.25)
            c.beginPath();c.move(to:.zero);c.addLine(to:CGPoint(x:-575,y:-26))
            c.addQuadCurve(to:CGPoint(x:-575,y:27),control:CGPoint(x:-590,y:-3));c.closePath();c.clip()
            c.setAlpha(0.09+0.4*dark)
            c.drawLinearGradient(Self.lamp,start:.zero,end:CGPoint(x:-585,y:0),options:[]);c.restoreGState()
            c.setAlpha((0.23+0.39*dark)*(0.7+0.3*cos(t*1.02)))
            let beacon=CGPoint(x:1356,y:282)
            c.drawRadialGradient(Self.lamp,startCenter:beacon,startRadius:0,endCenter:beacon,endRadius:36,options:[])
            c.setStrokeColor(CGColor(red:0.83,green:0.92,blue:0.91,alpha:0.6));c.setLineWidth(1.3)
            for i in 1...31 {
                let x=CGFloat(i*137%950)+5*sin(t*0.37+CGFloat(i)), y=CGFloat(450+i*173%245)
                let wave=0.5+0.5*sin(t*1.3+CGFloat(i));c.setAlpha(0.12+0.24*wave)
                c.move(to:CGPoint(x:x,y:y));c.addLine(to:CGPoint(x:x+5+15*wave,y:y-0.5));c.strokePath()
            }
        }
        if dark>0.2 {
            c.setFillColor(CGColor(gray:1,alpha:1))
            for i in 1..<48 {
                c.setAlpha(dark*(0.38+0.22*sin(CGFloat(i)+t*0.58)));let r=0.65+CGFloat(i%3)*0.27
                c.fillEllipse(in:CGRect(x:CGFloat(i*5861%1530+30)-r,y:CGFloat(i*1103%132+9)-r,width:2*r,height:2*r))
            }
        }
    }
}

@MainActor private final class WallpaperSurface: NSView {
    private let day=CALayer(),night=CALayer(),wash=CAGradientLayer()
    let motion=WallpaperMotion()
    override init(frame:NSRect) {
        super.init(frame:frame);wantsLayer=true
        day.contentsGravity = .resizeAspectFill;night.contentsGravity = .resizeAspectFill
        wash.colors=[CGColor(red:0.58,green:0.34,blue:0.62,alpha:0.24),CGColor(red:1,green:0.64,blue:0.37,alpha:0.48),
                     CGColor(red:0.96,green:0.67,blue:0.51,alpha:0.15),CGColor(red:0.45,green:0.30,blue:0.44,alpha:0.11)]
        wash.locations=[0,0.33,0.66,1];wash.startPoint=CGPoint(x:0,y:1);wash.endPoint=CGPoint(x:0.15,y:0)
        for child in [day,night,wash] {layer?.addSublayer(child)}
        motion.wantsLayer=true;motion.frame=bounds;motion.autoresizingMask=[.width,.height];addSubview(motion)
    }
    required init?(coder:NSCoder){fatalError("Programmatic view")}
    override func layout() {
        super.layout();CATransaction.begin();CATransaction.setDisableActions(true)
        for child in [day,night,wash] {child.frame=bounds}
        CATransaction.commit()
    }
    func paint(_ scene:MacLandscape,_ painting:LandscapePainting,_ light:WallpaperLight) {
        CATransaction.begin();CATransaction.setDisableActions(true)
        day.contents=painting.day;night.contents=painting.night;night.opacity=Float(light.dark);wash.opacity=Float(light.warmth)
        CATransaction.commit()
        motion.scene=scene;motion.dark=light.dark;motion.needsDisplay=true
    }
}

@MainActor final class MacWallpapers: NSObject {
    private struct Surface {let window:NSWindow;let view:WallpaperSurface}
    private var surfaces=[UInt32:Surface](), painting:LandscapePainting?, light:WallpaperLight?
    private var elapsed:CGFloat=0, pending:TimeInterval=0, minute:Int?
    private let settings: UserDefaults
    private let onChange:()->Void
    private(set) var scene:MacLandscape, lighting:MacLighting
    private(set) var motionEnabled:Bool
    var activeScreens:Int {surfaces.count}
    /// Capture only the app's desktop layers, without sampling personal desktop contents.
    func snapshot() -> NSBitmapImageRep? {
        guard let surface=surfaces.values.first else{return nil}
        let view=surface.view
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded();view.motion.displayIfNeeded()
        let w=800,h=max(1,Int(800*view.bounds.height/view.bounds.width))
        guard let context=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return nil}
        context.scaleBy(x:CGFloat(w)/view.bounds.width,y:CGFloat(h)/view.bounds.height)
        view.layer?.render(in:context)
        return context.makeImage().map { NSBitmapImageRep(cgImage:$0) }
    }
    var hasDesktopLayer:Bool {
        !surfaces.isEmpty && surfaces.values.allSatisfy {$0.window.isVisible && $0.window.ignoresMouseEvents &&
            $0.window.level.rawValue > Int(CGWindowLevelForKey(.desktopWindow)) &&
            $0.window.level.rawValue < Int(CGWindowLevelForKey(.desktopIconWindow))}
    }
    init(settings:UserDefaults,onChange:@escaping ()->Void) {
        self.settings=settings;self.onChange=onChange
        scene=MacLandscape(rawValue:settings.string(forKey:"wallpaper.scene") ?? "") ?? .system
        lighting=MacLighting(rawValue:settings.string(forKey:"wallpaper.lighting") ?? "") ?? .clock
        motionEnabled=settings.object(forKey:"wallpaper.motion") as? Bool ?? true
    }
    func append(to menu:NSMenu) {
        let group=NSMenu(title:"Desktop wallpaper")
        menu.addItem(withTitle:group.title,action:nil,keyEquivalent:"").submenu=group
        for choice in MacLandscape.allCases {
            let row=group.addItem(withTitle:choice.rawValue,action:#selector(selectScene(_:)),keyEquivalent:"")
            row.target=self;row.representedObject=choice.rawValue;row.state=scene == choice ? .on:.off
        }
        group.addItem(.separator());let phases=NSMenu(title:"Lighting")
        group.addItem(withTitle:phases.title,action:nil,keyEquivalent:"").submenu=phases
        for choice in MacLighting.allCases {
            let row=phases.addItem(withTitle:choice.rawValue,action:#selector(selectLighting(_:)),keyEquivalent:"")
            row.target=self;row.representedObject=choice.rawValue;row.state=lighting == choice ? .on:.off
        }
        let motion=group.addItem(withTitle:"Animate wallpaper",action:#selector(toggleMotion),keyEquivalent:"")
        motion.target=self;motion.state=motionEnabled ? .on:.off
    }
    @objc private func selectScene(_ row:NSMenuItem) {
        guard let key=row.representedObject as? String,let choice=MacLandscape(rawValue:key) else{return}
        if scene != choice {painting=nil;light=nil;minute=nil}
        scene=choice;settings.set(key,forKey:"wallpaper.scene");onChange()
    }
    @objc private func selectLighting(_ row:NSMenuItem) {
        guard let key=row.representedObject as? String,let choice=MacLighting(rawValue:key) else{return}
        lighting=choice;minute=nil;settings.set(key,forKey:"wallpaper.lighting");onChange()
    }
    @objc private func toggleMotion() {motionEnabled.toggle();settings.set(motionEnabled,forKey:"wallpaper.motion");onChange()}
    func sync(_ screens:[NSScreen],enabled:Set<UInt32>) {
        let wanted=scene == .system ? Set<UInt32>() : enabled
        for id in Array(surfaces.keys) where !wanted.contains(id) {surfaces.removeValue(forKey:id)?.window.close()}
        guard !wanted.isEmpty else{if scene == .system {painting=nil};return}
        if painting == nil {painting=LandscapePainting(scene)}
        guard let painting=painting else{return}
        let now=Date(), current=WallpaperLight(hour:lighting.hour(at:now))
        for screen in screens {
            guard let id=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                  wanted.contains(id) else{continue}
            if surfaces[id] == nil {
                let window=NSPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
                window.isReleasedWhenClosed=false;window.hidesOnDeactivate=false
                window.level=NSWindow.Level(rawValue:Int(CGWindowLevelForKey(.desktopWindow))+1)
                window.collectionBehavior=[.canJoinAllSpaces,.stationary,.ignoresCycle]
                window.hasShadow=false;window.ignoresMouseEvents=true
                let view=WallpaperSurface(frame:CGRect(origin:.zero,size:screen.frame.size))
                window.contentView=view;surfaces[id]=Surface(window:window,view:view);window.orderFrontRegardless()
            }
            guard let surface=surfaces[id] else{continue}
            surface.window.setFrame(screen.frame,display:true);surface.view.paint(scene,painting,current)
        }
        light=current;minute=Int(now.timeIntervalSince1970/60)
    }
    func tick(_ dt:TimeInterval,paused:Bool,lowPower:Bool,date:Date=Date()) {
        guard !surfaces.isEmpty,let painting=painting else{return}
        let nowMinute=Int(date.timeIntervalSince1970/60)
        if lighting == .clock,minute != nowMinute {
            minute=nowMinute;let next=WallpaperLight(hour:lighting.hour(at:date))
            if next != light { for surface in surfaces.values {surface.view.paint(scene,painting,next)};light=next }
        }
        guard motionEnabled,!paused else{return}
        pending+=min(0.12,max(0,dt))
        guard pending >= (lowPower ? 0.16 : 0.08) else{return}
        elapsed+=CGFloat(pending);pending=0
        for surface in surfaces.values {surface.view.motion.seconds=elapsed;surface.view.motion.needsDisplay=true}
    }
}
