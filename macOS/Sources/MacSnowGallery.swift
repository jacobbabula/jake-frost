import AppKit
import ImageIO

/// Export the real overlay frames on a neutral desktop so trajectories and foot contact are visible.
@MainActor func runMacSnowGalleryIfRequested()->Bool {
    guard let output=ProcessInfo.processInfo.environment["JAKEFROST_MAC_GALLERY"] else{return true}
    let dir=URL(fileURLWithPath:output,isDirectory:true),size=CGSize(width:600,height:240)
    let suite="io.jakefrost.gallery."+UUID().uuidString
    guard let prefs=UserDefaults(suiteName:suite) else{return false}
    defer {prefs.removePersistentDomain(forName:suite)}
    prefs.set(200,forKey:"visitors.Yeti.size");prefs.set(150,forKey:"visitors.Snowplow.size")
    let controls=MacVisitorControls(settings:prefs,summon:{_ in},onChange:{})
    func capture(_ name:String,_ prepare:(SnowCanvas)->Void,warmup:Int,interval:Int)->Bool {
        let view=SnowCanvas(frame:CGRect(origin:.zero,size:size)),world=view.world
        world.setDesktop(size:size,edges:[]);world.clear();world.amount=0
        view.workshop.configure(settings:prefs,displayID:0);view.workshop.clear();view.workshop.sync(world:world)
        view.visitors.configure(controls)
        let floor=world.banks[0]
        for i in floor.depth.indices {
            let x=CGFloat(i)*floor.spacing
            floor.add(at:x,amount:6+12*pow(sin(x/93),2),spread:0)
        }
        func step(_ n:Int) {
            for _ in 0..<n {
                let dt=1.0/30
                world.step(dt);view.visitors.step(dt,world:world);view.workshop.step(dt);view.workshop.sync(world:world)
            }
        }
        prepare(view);step(warmup)
        let frames=28,file=dir.appendingPathComponent(name+".gif")
        guard let movie=CGImageDestinationCreateWithURL(file as CFURL,"com.compuserve.gif" as CFString,frames,nil) else{return false}
        CGImageDestinationSetProperties(movie,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
        for i in 0..<frames {
            step(interval)
            let ok=autoreleasepool {()->Bool in
                let drawing=NSImage(size:size,flipped:true){bounds in
                    view.draw(bounds)
                    NSColor(calibratedRed:0.12,green:0.20,blue:0.29,alpha:1).setFill()
                    bounds.fill(using:.destinationOver);return true
                }
                guard let tiff=drawing.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let image=bitmap.cgImage else{return false}
                CGImageDestinationAddImage(movie,image,[kCGImagePropertyGIFDictionary:[
                    kCGImagePropertyGIFDelayTime:Double(interval)/30]] as CFDictionary)
                if i==12 {
                    guard let png=bitmap.representation(using:.png,properties:[:]) else{return false}
                    do {try png.write(to:dir.appendingPathComponent(name+".png"))} catch {return false}
                }
                return true
            }
            if !ok {return false}
        }
        return CGImageDestinationFinalize(movie)
    }
    do {try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)} catch {return false}
    let plough=capture("snowplough",{view in
        let p=CGPoint(x:210,y:view.world.banks[0].surface(210))
        view.workshop.beginPlacement(.present);_=view.workshop.down(p);view.workshop.up(p);view.workshop.finishEditing()
        view.visitors.summon(.snowplow,in:view.world)
    },warmup:100,interval:5)
    let yeti=capture("yeti-woodcutting",{view in
        let p=CGPoint(x:245,y:view.world.banks[0].surface(245))
        view.workshop.beginPlacement(.tree);_=view.workshop.down(p);view.workshop.up(p);view.workshop.finishEditing()
        view.visitors.summon(.yeti,in:view.world)
    },warmup:193,interval:5)
    let battle=capture("snowball-fight",{view in
        view.world.dropVisitorSnowman(at:262,scale:1.25);_=view.world.wakeSnowmen()
    },warmup:22,interval:6)
    return plough && yeti && battle
}
