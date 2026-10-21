import Foundation
import Testing
import SpectroEELS

/// Benchmark harness (not a test): see BenchmarkQuantificationTests in SpectroEDXTests. Spectrum of pixel p, channel k, energy
/// E = -5 + 0.05 k eV, 2048 channels: m * (2e4 exp(-E^2 / (2 * 0.6^2)) + 300 exp(-(E - 15)^2 / (2 * 5^2)) + 20 exp(-(E - 45)^2 /
/// (2 * 12^2))) with m = 0.5 + frac(p * 0.6180339887498949). Pixels row-major.
struct BenchmarkThicknessTests {
    static let sizes: [String: (Int, Int)] = ["small": (8, 8), "typical": (64, 64), "large": (256, 256)]

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SPECTRO_BENCH_OUT"] != nil))
    func thickness() throws {
        let env = ProcessInfo.processInfo.environment
        let wanted = (env["SPECTRO_BENCH_SIZES"] ?? "small,typical").split(separator: ",").map(String.init)
        var rows: [[String: Any]] = []
        let nch = 2048
        let shape: [Double] = (0..<nch).map { k in
            let e = -5 + 0.05 * Double(k)
            return 2e4 * exp(-e * e / (2 * 0.36)) + 300 * exp(-(e - 15) * (e - 15) / 50) + 20 * exp(-(e - 45) * (e - 45) / 288)
        }
        for name in wanted {
            guard let (ny, nx) = Self.sizes[name] else { continue }
            let n = ny * nx
            var counts = [Double](repeating: 0, count: n * nch)
            for p in 0..<n {
                let x = Double(p) * 0.6180339887498949
                let m = 0.5 + (x - x.rounded(.down))
                for k in 0..<nch { counts[p * nch + k] = m * shape[k] }
            }
            let image = try LowLossSpectrumImage(nx: nx, ny: ny, channels: nch, counts: counts, energyOffsetEV: -5, energyScaleEV: 0.05)
            for (label, rule) in [("fixed 3 eV", ThresholdRule.fixed(3)), ("estimated", ThresholdRule.estimated())] {
                var times: [Double] = []
                for i in 0..<6 {
                    let t0 = DispatchTime.now().uptimeNanoseconds
                    let map = try EELSThickness.logRatio(image, threshold: rule)
                    let dt = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9
                    #expect(map.pixels.count == n)
                    if i > 0 { times.append(dt) }
                }
                rows.append(["function": "t/lambda log ratio: \(label)", "size": name, "pixels": n, "swift_cpu_s": times])
            }
        }
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: env["SPECTRO_BENCH_OUT"]!).appendingPathComponent("swift-eels.json"))
    }
}
