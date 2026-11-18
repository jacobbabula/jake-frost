import AppKit
import CoreGraphics

let side=1024
guard let bitmap=CGContext(data:nil,width:side,height:side,bitsPerComponent:8,bytesPerRow:side*4,
                          space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{exit(1)}
let tile=CGPath(roundedRect:CGRect(x:42,y:42,width:940,height:940),cornerWidth:210,cornerHeight:210,transform:nil)
bitmap.addPath(tile);bitmap.clip()
let shades=[CGColor(red:0.12,green:0.29,blue:0.31,alpha:1),CGColor(red:0.06,green:0.12,blue:0.17,alpha:1)] as CFArray
let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:shades,locations:[0,1])!
bitmap.drawLinearGradient(gradient,start:CGPoint(x:150,y:900),end:CGPoint(x:880,y:90),options:[.drawsBeforeStartLocation,.drawsAfterEndLocation])
bitmap.translateBy(x:512,y:512);bitmap.setLineCap(.round);bitmap.setLineJoin(.round)
bitmap.setStrokeColor(CGColor(red:0.82,green:0.95,blue:0.91,alpha:1));bitmap.setLineWidth(27)
for _ in 0..<6 {
    bitmap.move(to:.zero);bitmap.addLine(to:CGPoint(x:0,y:310))
    for y in [CGFloat(175),CGFloat(252)] {
        bitmap.move(to:CGPoint(x:-49,y:y+42));bitmap.addLine(to:CGPoint(x:0,y:y));bitmap.addLine(to:CGPoint(x:49,y:y+42))
    }
    bitmap.strokePath();bitmap.rotate(by:.pi/3)
}
guard let cg=bitmap.makeImage(),let png=NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:]) else{exit(1)}
try png.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
