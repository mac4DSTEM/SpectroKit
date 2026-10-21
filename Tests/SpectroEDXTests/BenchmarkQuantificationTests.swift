import Foundation
import Testing
import SpectroEDX

/// Benchmark harness (not a test): runs only when SPECTRO_BENCH_OUT names a directory. tools/benchmarks/run.sh drives it and
/// tools/benchmarks/bench.py runs the Python side on the same closed-form inputs. Times: one warm-up, then five runs, seconds.
/// Sizes by SPECTRO_BENCH_SIZES (comma list of small, typical, large; default small,typical). Input for pixel p, element e:
/// I = base_e * (0.4 + 1.2 * frac(p * 0.6180339887498949 + e * 0.31)), base = 300, 500, 700 (Al, Cr, Ni lines).
struct BenchmarkQuantificationTests {
    static let sizes: [String: (Int, Int)] = ["small": (8, 8), "typical": (256, 256), "large": (1024, 1024)]

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SPECTRO_BENCH_OUT"] != nil))
    func quantifyMaps() throws {
        let env = ProcessInfo.processInfo.environment
        let wanted = (env["SPECTRO_BENCH_SIZES"] ?? "small,typical").split(separator: ",").map(String.init)
        var rows: [[String: Any]] = []
        let elements = ["Al", "Cr", "Ni"]
        let energies = [XRayLines.line("Al_Ka")!.energy, XRayLines.line("Cr_Ka")!.energy, XRayLines.line("Ni_Ka")!.energy]
        let base = [300.0, 500.0, 700.0]
        for name in wanted {
            guard let (r, c) = Self.sizes[name] else { continue }
            let n = r * c
            let maps: [[Double]] = (0..<3).map { e in
                (0..<n).map { p in
                    let x = Double(p) * 0.6180339887498949 + Double(e) * 0.31
                    return base[e] * (0.4 + 1.2 * (x - x.rounded(.down)))
                }
            }
            let abs = EDXAbsorptionSetting(takeOffDegrees: 35, lineEnergiesKeV: energies)
            let cases: [(String, EDXQuantificationSetup)] = [
                ("CL", .init(elements: elements, method: .cliffLorimer(kFactors: [0.982, 1.32, 1.60], thicknessNm: nil))),
                ("CL+absorption", .init(elements: elements, method: .cliffLorimer(kFactors: [0.982, 1.32, 1.60], thicknessNm: 80), absorption: abs)),
                ("zeta", .init(elements: elements, method: .zeta(zetaFactors: [20, 40, 60]), beamCurrentNA: 0.05, liveTimeSeconds: 2.5)),
                ("zeta+absorption", .init(elements: elements, method: .zeta(zetaFactors: [20, 40, 60]), absorption: abs, beamCurrentNA: 0.05, liveTimeSeconds: 2.5)),
                ("cross_section", .init(elements: elements, method: .crossSection(sectionsBarn: [3, 4, 5], probeAreaNm2: 0.25), beamCurrentNA: 0.05, liveTimeSeconds: 2.5)),
            ]
            for (label, setup) in cases {
                var times: [Double] = []
                for i in 0..<6 {
                    let t0 = DispatchTime.now().uptimeNanoseconds
                    let q = try EDXQuantification.quantifyMaps(intensityMaps: maps, rows: r, columns: c, setup: setup)
                    let dt = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9
                    #expect(q.failures.allSatisfy { $0 == nil })
                    if i > 0 { times.append(dt) }
                }
                rows.append(["function": "quantification maps: \(label)", "size": name, "pixels": n, "swift_cpu_s": times])
            }
        }
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: env["SPECTRO_BENCH_OUT"]!).appendingPathComponent("swift-edx.json"))
    }
}
