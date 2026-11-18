import AppKit

/// A storm temporarily covers the selected weather. Its snow settles in the same drifts
/// that can be sculpted, rolled into balls and cleared by a plough.
@MainActor final class MacSky {
    private struct Flake { var x,y,depth,radius,phase: CGFloat }
    private var flakes = [Flake]()
    private var rng = SnowRandom(state: .random(in: 1...UInt64.max))
    private var travel: CGFloat = 0, age: CGFloat = 0, waveIn: CGFloat = 0
    private var wave = 0
    private(set) var inBlizzard = false
    private(set) var strength: CGFloat = 0
    var snowCount: Int { flakes.count }

    func startStorm() {
        guard !inBlizzard else { return }
        inBlizzard = true; age = 0; waveIn = 0.35; wave = 0; strength = 0
    }
    func endStorm() {
        inBlizzard = false; strength = 0; flakes.removeAll(keepingCapacity: true)
    }
    private func flake(_ size: CGSize, inside: Bool) -> Flake {
        let d = rng.between(0,1)
        return Flake(x:rng.between(-12,size.width+12), y:inside ? rng.between(-8,size.height) : -8,
                     depth:d, radius:1.15+4*d*d+rng.between(0,1), phase:rng.between(0,6.28))
    }
    func step(_ seconds: TimeInterval, world: SnowWorld, clouds: Bool, wind: CGFloat,
              sendYeti: (CGFloat)->Void, ended: ()->Void) {
        guard !world.paused, world.size.width > 1, !world.banks.isEmpty else { return }
        let dt = CGFloat(min(0.12,max(0,seconds)))
        guard inBlizzard else {
            if clouds { travel += dt*(8+wind*0.6) }
            return
        }
        age += dt
        if age >= 22 { endStorm(); ended(); return }
        let gust = 0.5+0.5*sin(age*1.16+0.6*sin(age*0.72))
        strength = min(1,age/2.2)*min(1,(22-age)/3.8)*(0.8+0.2*gust)
        travel += dt*(22+68*strength)
        let size = world.size
        let limit = Int(min(900,max(140,size.width*size.height/1720))*strength)
        if flakes.count < limit {
            flakes.reserveCapacity(limit)
            while flakes.count < limit { let f = flake(size,inside:true); flakes.append(f) }
        } else if flakes.count > limit { flakes.removeLast(flakes.count-limit) }
        let speed = wind*0.38+strength*(86+180*gust)
        for i in flakes.indices {
            var f = flakes[i]
            let oldX = f.x, oldY = f.y
            f.x += (speed*(0.47+0.84*f.depth)+15*sin(age+f.phase))*dt
            f.y += (26+(60+35*gust)*f.depth+7*cos(age*1.4+f.phase))*dt
            if let bank = world.intercept(x:(f.x+oldX)*0.5,previous:oldY,next:f.y) {
                if f.depth > 0.63 { bank.add(at:f.x,amount:0.43+f.radius*0.19,spread:1) }
                f = flake(size,inside:false)
            } else if f.y > size.height+9 { f = flake(size,inside:false) }
            else if f.x > size.width+12 { f.x = -10 } else if f.x < -12 { f.x = size.width+10 }
            flakes[i] = f
        }
        waveIn -= dt
        if age<16, waveIn<=0 {
            sendYeti((wave/3)%2==0 ? 1 : -1); wave+=1; waveIn=wave%3==0 ? 3.5 : 1.1
        }
    }

    private static func noise(_ x:CGFloat,_ y:CGFloat,_ seed:Int) -> CGFloat {
        func value(_ x:Int,_ y:Int) -> CGFloat {
            var n=UInt32(truncatingIfNeeded:x) &* 1597334677 &+ UInt32(truncatingIfNeeded:y) &* 381201581 &+ UInt32(seed*171713)
            n=(n^(n>>16)) &* 0x85ebca6b; n=(n^(n>>13)) &* 0xc2b2ae35
            return CGFloat((n^(n>>16))&65535)/65535
        }
        let a=Int(floor(x)), b=Int(floor(y))
        let fx=x-CGFloat(a), fy=y-CGFloat(b), u=fx*fx*(3-2*fx), v=fy*fy*(3-2*fy)
        return (value(a,b)*(1-u)+value(a+1,b)*u)*(1-v)+(value(a,b+1)*(1-u)+value(a+1,b+1)*u)*v
    }
    // Build these small alpha textures once, shared by all displays.
    private static let cloudTextures: [CGImage] = (0..<3).compactMap { seed in
        let w=300,h=106
        var densities=[CGFloat](repeating:0,count:w*h), pixels=[UInt8](repeating:0,count:w*h*4)
        for y in 0..<h { for x in 0..<w {
            let u=(CGFloat(x)+0.5)/CGFloat(w), v=(CGFloat(y)+0.5)/CGFloat(h)
            let crown=0.51-0.13*sin(6.3*u+CGFloat(seed)*0.85)-0.052*sin(16*u+CGFloat(seed))
            let radius=0.35+0.09*sin(8*u-CGFloat(seed)), ux=(u-0.5)/0.46, vy=(v-crown)/radius
            let detail=(noise(u*5,v*2.3,seed)-0.5)*0.95+(noise(u*14,v*5.3,seed+24)-0.5)*0.43
            let fine=(noise(u*39,v*15,seed+17)-0.5)*0.20+(noise(u*92,v*31,seed+30)-0.5)*0.07
            let edge=min(1,CGFloat(min(x,w-1-x,y,h-1-y))/7)
            densities[y*w+x]=max(0,min(1,((1-ux*ux-vy*vy)*0.74+detail+fine-0.13)*1.9))*edge
        }}
        for y in 0..<h { for x in 0..<w {
            let i=y*w+x, d=densities[i], a=d*0.78
            let shade=densities[max(0,y-9)*w+max(0,x-7)]
            let l=min(1,max(0,0.82+d*0.31-shade*0.54-0.18*CGFloat(y)/CGFloat(h)))
            pixels[i*4]=UInt8((139+114*l)*a);pixels[i*4+1]=UInt8((161+90*l)*a)
            pixels[i*4+2]=UInt8((202+51*l)*a);pixels[i*4+3]=UInt8(255*a)
        }}
        guard let provider=CGDataProvider(data:Data(pixels) as CFData) else{return nil}
        return CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,
                       space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent)
    }
    func draw(in c:CGContext,size:CGSize,intensity:CGFloat) {
        guard size.width>1,size.height>1 else{return}
        let density=inBlizzard ? strength : min(1,intensity*0.8)
        guard density>0 else{return}
        c.saveGState()
        for (i,cloud) in Self.cloudTextures.enumerated() {
            let k=CGFloat(i), width=max(170,min(620,size.width*(0.34+0.10*k)))
            let period=width*1.58
            let offset=(travel*(0.19+0.12*k)+period*(0.15+0.31*k)).truncatingRemainder(dividingBy:period)
            let y=min(86,size.height*0.12)*k-16
            c.setAlpha(density*(0.28+0.15*k))
            var x=offset-period
            while x < size.width {
                c.saveGState();c.translateBy(x:x,y:y+width*0.34);c.scaleBy(x:1,y:-1)
                c.draw(cloud,in:CGRect(x:0,y:0,width:width,height:width*0.34));c.restoreGState()
                x+=period
            }
        }
        c.restoreGState()
        if inBlizzard { drawSnow(in:c,front:false) }
    }
    func drawForeground(in c:CGContext) { if inBlizzard {drawSnow(in:c,front:true)} }
    private func drawSnow(in c:CGContext,front:Bool) {
        c.saveGState()
        c.setFillColor(CGColor(gray:1,alpha:front ? 0.88 : 0.65));c.beginPath()
        for f in flakes where (f.depth>0.72)==front {
            let r=f.radius*(front ? 0.85 : 0.65)
            c.addEllipse(in:CGRect(x:f.x-r,y:f.y-r,width:2.3*r,height:1.75*r))
        }
        c.fillPath();c.restoreGState()
    }
}
