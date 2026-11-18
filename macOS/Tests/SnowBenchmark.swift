import Foundation

@main enum SnowBenchmark {
    static func main() {
        let size = CGSize(width: 1920, height: 1080)
        // Exposed tops span several columns and elevations, as on a busy desktop.
        let edges = (0..<24).map { i -> SnowEdge in
            let x = CGFloat((i * 233) % 1360), y = CGFloat(180 + (i * 71) % 830)
            return SnowEdge(id: UInt32(i+1), x: x, y: y, width: 540, visible: [x...(x+540)])
        }
        var trials = [Double]()
        for _ in 0..<5 {
            let scene = SnowWorld()
            scene.setDesktop(size:size, edges:edges)
            scene.amount = 2.2
            for _ in 0..<300 { scene.step(1.0/30) }
            var particleSteps = 0
            let start = ProcessInfo.processInfo.systemUptime
            for _ in 0..<1500 {
                particleSteps += scene.particles.count
                scene.step(1.0/30)
            }
            precondition(particleSteps > 100_000 && scene.banks.count == 25)
            trials.append((ProcessInfo.processInfo.systemUptime - start) * 1e9 / Double(particleSteps))
        }
        print(String(format:"%.2f", trials.sorted()[2]))
    }
}
