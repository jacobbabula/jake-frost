import AppKit

enum WorkshopKind: String, CaseIterable, Codable {
    case tree = "Christmas tree", lights = "String lights", wreath = "Wreath", star = "Star"
    case present = "Wrapped gift", bauble = "Red bauble", candle = "Candle", candy = "Candy cane"
    case mitten = "Mitten"
    case goldBauble = "Gold bauble", stocking = "Stocking", bells = "Bells"
    case gingerbread = "Gingerbread", holly = "Holly", santaHat = "Santa hat"
    case snowGlobe = "Snow globe", cocoa = "Cocoa", boat = "Boat"
}

// One silhouette serves both the art and snow contact, including when the item is tilted.
@MainActor final class WorkshopSymbol {
    private struct Ink {
        let path: CGPath
        let color: CGColor
    }
    private var inks: [Ink] = []
    private let silhouette: CGMutablePath
    private let image: NSImage
    let bounds: CGRect
    private static var symbols: [WorkshopKind: WorkshopSymbol] = [:]
    static func forKind(_ kind: WorkshopKind) -> WorkshopSymbol {
        if let symbol = symbols[kind] { return symbol }
        let symbol = WorkshopSymbol(kind)
        symbols[kind] = symbol
        return symbol
    }
    private init(_ kind: WorkshopKind) {
        var layers: [Ink] = []
        func color(_ rgb: Int) -> CGColor {
            CGColor(red: CGFloat(rgb >> 16)/255, green: CGFloat((rgb >> 8)&255)/255, blue: CGFloat(rgb&255)/255, alpha: 1)
        }
        func paint(_ path: CGPath, _ rgb: Int) { layers.append(Ink(path: path, color: color(rgb))) }
        func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ rgb: Int) {
            paint(CGPath(ellipseIn: CGRect(x:x,y:y,width:w,height:h),transform:nil),rgb)
        }
        func tile(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ rgb: Int) {
            paint(CGPath(roundedRect: CGRect(x:x,y:y,width:w,height:h),cornerWidth:r,cornerHeight:r,transform:nil),rgb)
        }
        func shape(_ rgb: Int, _ pairs: [(CGFloat,CGFloat)]) {
            let p = CGMutablePath()
            p.addLines(between:pairs.map { CGPoint(x:$0.0,y:$0.1) })
            p.closeSubpath(); paint(p,rgb)
        }
        func stroke(_ rgb: Int, _ width: CGFloat, _ body:(CGMutablePath)->Void) {
            let p=CGMutablePath(); body(p)
            paint(p.copy(strokingWithWidth:width,lineCap:.round,lineJoin:.round,miterLimit:3),rgb)
        }
        func star(_ x:CGFloat, _ y:CGFloat, _ size:CGFloat, _ rgb:Int) {
            shape(rgb,(0..<10).map { i in
                let angle = CGFloat(i) * .pi / 5 - .pi/2
                let r = i.isMultiple(of:2) ? size : size*0.44
                return (x + cos(angle)*r,y + sin(angle)*r)
            })
        }
        func dot(_ x:CGFloat,_ y:CGFloat,_ r:CGFloat,_ rgb:Int) { oval(x-r,y-r,2*r,2*r,rgb) }
        switch kind {
        case .tree:
            tile(-5,25,10,18,1.5,0x795340); tile(-4,27,3,16,1,0xAC8054)
            for (tip,base,wide,pine) in [(-23,32,32,0x1B574C),(-34,15,26,0x266E56),(-43,-2,19,0x328662)] {
                let t=CGFloat(tip), b=CGFloat(base), w=CGFloat(wide)
                shape(pine,[(0,t),(w*0.54,(t+b)/2),(w*0.48,(t+b)/2),(w,b-4),(w*0.66,b-5),(w*0.51,b),(w*0.12,b-2),(-w*0.31,b),(-w*0.42,b-3),(-w*0.82,b-1),(-w,b-3),(-w*0.40,(t+b)/2)])
                shape(0xCEE6D8,[(0,t),(w*0.53,(t+b)/2),(w*0.31,(t+b)/2-1),(w*0.17,(t+b)/2+2),(0,(t+b)/2-2),(-w*0.2,(t+b)/2+1),(-w*0.5,(t+b)/2+3)])
            }
            star(0,-43,7,0xE8A746);star(-0.4,-44,5.8,0xFFE8A0)
        case .wreath:
            let greens=[0x1E5B50,0x277058,0x3E8768]
            for i in 0..<22 {
                let a=CGFloat(i)*2 * .pi/22
                dot(cos(a)*15,sin(a)*15,6.8,greens[i%3])
                dot(cos(a)*18+1,sin(a)*18-1,1.3,0xAFD9AC)
            }
            for (x,y) in [(-11,-11),(16,-6),(-16,7),(10,13)] {
                dot(CGFloat(x),CGFloat(y),2.8,0xC84148);dot(CGFloat(x)+3,CGFloat(y)-2,2,0xEB6965)
            }
            shape(0xB73F4E,[(-1,12),(-12,8),(-10,19),(-1,16),(9,21),(12,10)])
            shape(0xCB4D56,[(-1,15),(-6,24),(-2,23),(0,26),(3,16),(6,22),(8,20),(11,21),(3,14)])
            dot(0,14,3.7,0xE27567)
        case .star:
            star(0,0,22,0xAE722B);star(0,-1,20,0xF8C762)
            for i in 0..<5 {
                let a=CGFloat(i)*2 * .pi/5 - .pi/2
                let aa = a + .pi/5
                shape(0xFFE89D,[(0,-1),(20*cos(a),-1+20*sin(a)),(8.8*cos(aa),-1+8.8*sin(aa))])
            }
        case .present:
            tile(-19,-8,38,29,2,0xAA444F);tile(-15,-7,25,27,1,0xCC5D61)
            tile(-21,-11,42,8,2,0xE27172);tile(-4,-11,7,32,0.8,0xEFBB70)
            for dir: CGFloat in [-1,1] {
                stroke(0xF4C981,3.5) { p in
                    p.move(to:.init(x:0,y:-10))
                    p.addCurve(to:.init(x:0,y:-10),control1:.init(x:dir*26,y:-12),control2:.init(x:dir*10,y:-35))
                }
            }
            dot(0,-11,3.6,0xE6A85A)
        case .bauble, .goldBauble:
            let gold = kind == .goldBauble
            stroke(0xD0A35C,1.5) { $0.addEllipse(in:CGRect(x:-3.3,y:-23,width:6.6,height:7)) }
            oval(-16,-14,32,34,gold ? 0xAD742B : 0x9F3B4A);oval(-15,-14,27,30,gold ? 0xF5BC4E : 0xD7545B)
            tile(-6,-17,12,5.5,1.5,0xDCB36C)
            stroke(0xF3C574,1.8) { p in p.move(to:.init(x:-15,y:1));p.addQuadCurve(to:.init(x:15,y:4),control:.init(x:0,y:11)) }
            oval(-10,-9,5.5,8,gold ? 0xFFF3B3 : 0xF4AE9C);dot(5,10,1.6,0xFFD794)
        case .stocking:
            let p=CGMutablePath()
            p.move(to:.init(x:-7,y:-17));p.addLine(to:.init(x:11,y:-17));p.addLine(to:.init(x:12,y:9))
            p.addQuadCurve(to:.init(x:4,y:19),control:.init(x:12,y:18))
            p.addLine(to:.init(x:-11,y:24));p.addQuadCurve(to:.init(x:-20,y:13),control:.init(x:-26,y:25))
            p.addLine(to:.init(x:-7,y:5));p.closeSubpath();paint(p,0xB53F4F)
            tile(-10,-24,24,10,3,0xF6F1D9);tile(-7,-23,18,2,1,0xFFFFFF)
            star(2,-1,5,0xF6CB89);oval(-18,15,8,5,0xDE6868)
        case .bells:
            for (offset,dy) in [(-9,1),(9,-3)] {
                let x=CGFloat(offset), y=CGFloat(dy)
                dot(x,y+13,3.2,0x8F602B)
                let p=CGMutablePath();p.move(to:.init(x:x-12,y:y+10))
                p.addQuadCurve(to:.init(x:x-7,y:y-5),control:.init(x:x-7,y:y+4))
                p.addQuadCurve(to:.init(x:x+7,y:y-5),control:.init(x:x,y:y-19))
                p.addQuadCurve(to:.init(x:x+12,y:y+10),control:.init(x:x+8,y:y+5))
                p.closeSubpath();paint(p,0xEBB04D);oval(x-12,y+8,24,5,0xC68A37)
                oval(x-5,y-6,3.3,8,0xFFE9A3)
            }
            shape(0xAD3747,[(0,-12),(-13,-21),(-13,-10),(-2,-9),(10,-6),(13,-19)])
            dot(0,-12,3.4,0xE26763)
        case .gingerbread:
            stroke(0x98522F,10){p in p.move(to:.init(x:-10,y:18));p.addLine(to:.init(x:0,y:1));p.addLine(to:.init(x:10,y:18))}
            stroke(0xBB7444,9){p in p.move(to:.init(x:-17,y:-6));p.addLine(to:.init(x:0,y:0));p.addLine(to:.init(x:17,y:-6))}
            tile(-8,-8,16,22,6,0xB87140);dot(0,-16,10,0xC4804D)
            dot(-3.4,-18,1.2,0xFFF4DB);dot(3.4,-18,1.2,0xFFF4DB)
            stroke(0xFFF4DB,1.4){p in p.move(to:.init(x:-3,y:-13));p.addQuadCurve(to:.init(x:3,y:-13),control:.init(x:0,y:-10))}
            dot(0,-2,1.8,0x9D3042);dot(0,4,1.8,0xFFF4DB)
            for x:CGFloat in [-12,12] {tile(x-2,13,4,2,1,0xF8E9CC)}
        case .holly:
            for side:CGFloat in [-1,1] {
                shape(side<0 ? 0x24634B : 0x39865A,[(0,6),(side*9,9),(side*10,5),(side*18,6),(side*17,0),(side*23,-9),(side*15,-9),(side*14,-15),(side*8,-11),(side*3,-14)])
                stroke(0x81B37C,1.15){p in p.move(to:.init(x:0,y:6));p.addLine(to:.init(x:side*17,y:-8))}
            }
            for (xx,yy) in [(-4,7),(4,6),(0,12)] { let x=CGFloat(xx),y=CGFloat(yy);dot(x,y,4.4,0xB63E4B);dot(x-1,y-1.3,1.1,0xFFAE95) }
        case .santaHat:
            let p=CGMutablePath();p.move(to:.init(x:-23,y:11))
            p.addQuadCurve(to:.init(x:2,y:-20),control:.init(x:-10,y:-17))
            p.addQuadCurve(to:.init(x:23,y:-2),control:.init(x:14,y:-23))
            p.addQuadCurve(to:.init(x:9,y:-8),control:.init(x:13,y:-10));p.addLine(to:.init(x:12,y:11))
            p.closeSubpath();paint(p,0xB8444D)
            stroke(0xD9605E,2.5){p in p.move(to:.init(x:-15,y:5));p.addQuadCurve(to:.init(x:2,y:-16),control:.init(x:-9,y:-9))}
            tile(-24,8,39,11,5,0xF3EBD8);oval(-20,10,7,3,0xFFFAEF);dot(22,-1,5.8,0xF5EDDB)
        case .snowGlobe:
            oval(-18,-25,36,38,0x80BACA);oval(-15,-22,30,31,0xBCE3DF)
            shape(0x35735D,[(3,-15),(-4,-4),(-2,-4),(-7,3),(12,3),(7,-5),(9,-5)])
            oval(-13,2,27,8,0xF9F6E8)
            for (x,y) in [(-8,-13),(-10,-6),(9,-11),(12,-3)]{dot(CGFloat(x),CGFloat(y),1.3,0xFFFFFF)}
            shape(0x9E5839,[(-13,9),(13,9),(18,21),(-18,21)]);tile(-18,18,36,5,2,0x87503A);tile(-12,12,24,3,1,0xCCA36D)
        case .cocoa:
            stroke(0xC65B56,4){p in p.addEllipse(in:CGRect(x:10,y:-5,width:12,height:15))}
            tile(-16,-8,32,27,6,0xBA4C50);oval(-16,-12,32,10,0xF1D1A3);oval(-13,-10,26,6,0x674537)
            for xx:CGFloat in [-8,1] {
                stroke(0xDEE9E4,1.5){p in p.move(to:.init(x:xx,y:-14));p.addCurve(to:.init(x:xx+2,y:-26),control1:.init(x:xx-4,y:-20),control2:.init(x:xx+6,y:-19))}
            }
            star(-2,6,5.5,0xF9DEC0);tile(-15,14,28,2,1,0xDB6862)
        case .boat:
            tile(-1,-25,2,36,0.8,0x83553D)
            shape(0xF5DDAC,[(-3,-24),(-18,0),(-3,-1)]);shape(0xC35853,[(2,-21),(16,-1),(2,-2)])
            shape(0xDEB05F,[(1,-25),(13,-23),(1,-19)])
            shape(0x9E4D42,[(-24,3),(24,3),(16,15),(-13,15)]);tile(-23,2,47,4,1,0xDBAC6D)
            for xx:CGFloat in [-9,0,9] {dot(xx,9,1.4,0xF3CA87)}
        case .candle:
            oval(-15,14,30,8,0xA57747);oval(-15,12,30,6,0xD7AC68)
            tile(-9,-10,18,27,2,0xD65853);tile(-7,-11,8,27,2,0xED7567)
            tile(-9,-12,18,6,2,0xF7B187);tile(3,-10,3.5,9,1.7,0xF6B087)
            tile(-0.7,-16,1.4,5,0.5,0x583A37)
            let p=CGMutablePath();p.move(to:.init(x:1,y:-31));p.addQuadCurve(to:.init(x:4,y:-15),control:.init(x:11,y:-20))
            p.addQuadCurve(to:.init(x:-2,y:-24),control:.init(x:-7,y:-11));p.closeSubpath();paint(p,0xF8AD51)
            oval(-1.7,-24,4,8.5,0xFFEA9E)
        case .candy:
            let cane: (CGMutablePath)->Void = { p in
                p.move(to:.init(x:-8,y:20));p.addLine(to:.init(x:1,y:-13))
                p.addCurve(to:.init(x:15,y:-11),control1:.init(x:4,y:-25),control2:.init(x:20,y:-22))
            }
            stroke(0xB34853,9,cane);stroke(0xFFF3D8,7,cane)
            for i in 0..<4 {
                let y=14-CGFloat(i)*8, x = -6 + CGFloat(i)*2.1
                shape(0xCC5057,[(x-3.9,y),(x-2.9,y-4),(x+3.6,y-0.5),(x+2.8,y+3)])
            }
            shape(0xCC5057,[(3,-21),(6,-24),(9,-16),(6,-15)])
            shape(0xCC5057,[(12,-23),(16,-22),(15,-15),(12,-16)])
        case .mitten:
            let p=CGMutablePath()
            p.move(to:.init(x:-11,y:15));p.addQuadCurve(to:.init(x:-16,y:-6),control:.init(x:-17,y:5))
            p.addCurve(to:.init(x:9,y:-11),control1:.init(x:-18,y:-24),control2:.init(x:8,y:-30))
            p.addLine(to:.init(x:9,y:-3));p.addCurve(to:.init(x:18,y:1),control1:.init(x:16,y:-14),control2:.init(x:24,y:-11))
            p.addQuadCurve(to:.init(x:10,y:15),control:.init(x:11,y:11));p.closeSubpath();paint(p,0x3B8685)
            tile(-12,10,24,9,2,0xE3C79A)
            for x: CGFloat in [-8,-4,0,4,8] {tile(x,11,1.4,7,0.5,0xB79F7D)}
            star(-3,-7,6,0xE7E6C6)
        case .lights:
            break // The adjustable wire is drawn from its endpoints.
        }
        let outline=CGMutablePath()
        for ink in layers { outline.addPath(ink.path) }
        silhouette=outline
        inks=layers
        let rect = layers.isEmpty ? CGRect(x:-1,y:-1,width:2,height:2) : outline.boundingBoxOfPath.integral.insetBy(dx:-1,dy:-1)
        bounds=rect
        let density:CGFloat=4
        let bitmap=CGContext(data:nil,width:Int(rect.width*density),height:Int(rect.height*density),bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.scaleBy(x:density,y:-density)
        bitmap.translateBy(x:-rect.minX,y:-rect.maxY)
        for ink in layers {bitmap.setFillColor(ink.color);bitmap.addPath(ink.path);bitmap.fillPath()}
        image=NSImage(cgImage:bitmap.makeImage()!,size:rect.size)
    }
    func rotatedBounds(scale:CGFloat, angle:CGFloat)->CGRect {
        let x=cos(angle)*scale, y=sin(angle)*scale
        var matrix=CGAffineTransform(a:x,b:y,c:-y,d:x,tx:0,ty:0)
        return silhouette.copy(using:&matrix)?.boundingBoxOfPath ?? bounds
    }
    func contains(_ p:CGPoint)->Bool {
        inks.reversed().contains { $0.path.contains(p) }
    }
    func draw() {
        image.draw(in:bounds,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
    }
}
