import AppKit

/// Cache icicles by exposed edge geometry. Snow depth changes much more often.
final class WindowIce {
    private struct Shape {
        let edge: SnowEdge
        let level: Int
        let body: CGPath
        let glints: CGPath
    }
    private var cache: [UInt32:Shape] = [:]
    private static let frost = CGColor(red:0.71,green:0.90,blue:1,alpha:0.68)
    private static let shine = CGColor(red:0.95,green:0.99,blue:1,alpha:0.8)
    func draw(_ context: CGContext, banks: [Drift], level: Int) {
        guard level > 0 else {cache.removeAll(keepingCapacity:true);return}
        if cache.count > banks.count + 8 {
            let ids = Set(banks.map { $0.edge.id });cache = cache.filter { ids.contains($0.key) }
        }
        context.saveGState()
        context.setLineWidth(0.85)
        for bank in banks where bank.edge.id != 0 {
            let edge = bank.edge
            let shape: Shape
            if let saved=cache[edge.id],saved.edge == edge,saved.level == level {shape=saved}
            else {
                let body=CGMutablePath(), shine=CGMutablePath()
                let spacing=CGFloat(33 - min(3,level)*5), seed=Int(edge.id % 113)
                for segment in edge.visible {
                    let left=segment.lowerBound,right=segment.upperBound, y=edge.y
                    body.addRect(CGRect(x:left,y:y,width:right-left,height:1.4))
                    var i=Int(ceil((left-edge.x)/spacing))
                    while true {
                        let noise=(i*73+seed*29)%103
                        let x=edge.x+CGFloat(i)*spacing+CGFloat(noise%7)
                        if x+4>=right {break}
                        if x-4>=left {
                            let length=CGFloat(2+level*2)+CGFloat(noise%17)*CGFloat(level)/3
                            let width=1.6+length*0.09
                            body.move(to:CGPoint(x:x-width,y:y));body.addLine(to:CGPoint(x:x+0.6,y:y+length))
                            body.addLine(to:CGPoint(x:x+width,y:y));body.closeSubpath()
                            shine.move(to:CGPoint(x:x-width*0.5,y:y+1));shine.addLine(to:CGPoint(x:x+0.3,y:y+length*0.77))
                        }
                        i+=1
                    }
                }
                shape=Shape(edge:edge,level:level,body:body,glints:shine);cache[edge.id]=shape
            }
            context.setFillColor(Self.frost);context.addPath(shape.body);context.fillPath()
            context.setStrokeColor(Self.shine);context.addPath(shape.glints);context.strokePath()
        }
        context.restoreGState()
    }
}
