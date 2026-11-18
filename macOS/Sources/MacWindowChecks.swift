import AppKit

@MainActor func runMacWindowChecks() -> Bool {
    var passed=true
    func check(_ result:Bool,_ name:String) {
        print((result ? "PASS: " : "FAIL: ")+name)
        if !result {passed=false}
    }
    let size=CGSize(width:180,height:130), world=SnowWorld()
    world.snowEnabled=false
    let edge=SnowEdge(id:23,x:10,y:70,width:155,visible:[10...60,110...165])
    world.setDesktop(size:size,edges:[edge])
    for _ in 0..<90 {world.step(1.0/30)}
    check(world.particles.isEmpty && !world.hasMotion,"turning snow off inhibits both seeding and steady-state snowfall")
    world.snowEnabled=true
    for _ in 0..<90 {world.step(1.0/30)}
    world.burst(CGPoint(x:15,y:45),count:5)
    world.snowEnabled=false
    check(world.particles.count==5 && world.particles.allSatisfy { $0.powder },"switching weather preserves snowball powder")
    guard let ledge=world.banks.last else {return false}
    world.setAccumulation(140)
    for _ in 0..<30 {ledge.add(at:45,amount:9,spread:0)}
    world.setAccumulation(24)
    check(ledge.maximumDepth==12 && (ledge.depth.max() ?? 0)<=12 &&
          world.intercept(x:45,previous:0,next:100) === ledge,"depth changes update both existing snow and collision geometry")
    let ice = WindowIce(), width=180, height=130
    func raster(_ level:Int) -> [UInt8] {
        var pixels=[UInt8](repeating:0,count:width*height*4)
        pixels.withUnsafeMutableBytes { bytes in
            guard let c=CGContext(data:bytes.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
                                  space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue |
                                      CGBitmapInfo.byteOrder32Big.rawValue) else {return}
            c.translateBy(x:0,y:CGFloat(height));c.scaleBy(x:1,y:-1)
            ice.draw(c,banks:world.banks,level:level)
        }
        return stride(from:3,to:pixels.count,by:4).map {pixels[$0]}
    }
    let off=raster(0),light=raster(1),heavy=raster(3)
    let lit=heavy.indices.filter { heavy[$0] > 30 }
    check(off.allSatisfy{$0==0} && light.filter{$0>30}.count<lit.count &&
          lit.count>110 && lit.allSatisfy { i in
              let x=i%width,y=i/width
              return ((10...59).contains(x) || (110...164).contains(x)) && (69...98).contains(y)
          },"ice intensity changes visible pixels and respects occluded sections of a window")
    let kinds=WorkshopKind.allCases.filter { $0 != .lights }
    check(kinds.count==17 && kinds.allSatisfy { kind in
        let art=WorkshopSymbol.forKind(kind),r=art.bounds
        return r.width>12 && r.height>12 &&
            stride(from:r.minY,through:r.maxY,by:2).contains { y in
                stride(from:r.minX,through:r.maxX,by:2).contains {x in art.contains(CGPoint(x:x,y:y))}
            } && art.rotatedBounds(scale:1.6,angle:0.7).width>17
    },"every Mac decoration has selectable art and rotated sizing bounds")
    return passed
}
