import Foundation
import Testing
import SpectroCore

/// Benchmark (not a test; runs only with SPECTRO_BENCH_SPARSE=1, under tools/memcap.sh): 300 disjoint regions of a 512 x 512 scan
/// transported onto a 512 x 512 spectrum grid through a rotated, scaled registration. Dense baseline: one
/// `transport(labels:classCount: 300)`; sparse: `regions(...)`. Prints wall time (best of 3), result bytes and peak resident size.
struct BenchmarkSparseRegionsTests {

    static func peakResidentMB() -> Double {
        var u = rusage(); getrusage(RUSAGE_SELF, &u)
        return Double(u.ru_maxrss) / 1_048_576          // bytes on macOS
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SPECTRO_BENCH_SPARSE"] != nil))
    func regions512x512x300() throws {
        let n = 512, nr = 300
        let c = cos(0.02), s = sin(0.02)
        let reg = try GridRegistration(matrix: [c, -s, 5.3, s, c, 2.1], scanWidth: n, scanHeight: n, spectrumWidth: n, spectrumHeight: n)
        // 20 x 15 blocks of 25 x 34 scan pixels, in order, leaving a margin at the bottom and the right.
        var labels = [Int](repeating: -1, count: n * n)
        var sets = [[Int]](repeating: [], count: nr)
        for by in 0..<15 { for bx in 0..<20 {
            let r = by * 20 + bx
            for y in (by * 34)..<(by * 34 + 34) { for x in (bx * 25)..<(bx * 25 + 25) { labels[y * n + x] = r; sets[r].append(y * n + x) } }
        } }
        let regions = sets.map { SparseRegion(pixelIndices: $0) }

        func time<T>(_ body: () throws -> T) rethrows -> (T, Double) {
            var best = Double.infinity, out: T?
            for _ in 0..<3 {
                let t0 = DispatchTime.now().uptimeNanoseconds
                out = try body()
                best = min(best, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9)
            }
            return (out!, best)
        }
        let baseMB = Self.peakResidentMB()
        let (sparse, tSparse) = try time { try MaskTransport.regions(regions, registration: reg) }
        let sparseMB = Self.peakResidentMB()
        var denseOverlapMB = 0.0, tDense = 0.0, dense: TransportedLabels?
        do {
            let (d, t) = try time { try MaskTransport.transport(labels: labels, classCount: nr, registration: reg) }
            dense = d; tDense = t; denseOverlapMB = Double(nr * n * n * 8) / 1_048_576
        }
        let denseMB = Self.peakResidentMB()
        // Equal on a spot check of 20 regions.
        for r in stride(from: 0, to: nr, by: 15) {
            let d = try sparse.dense(region: r)
            #expect(d.overlap[0] == dense!.overlap[r])
        }
        print(String(format: "BENCH sparse regions 512x512 x 300: sparse %.3f s, %.1f MB result, peak RSS %.0f MB (start %.0f MB) | dense %.3f s, %.0f MB overlap, peak RSS %.0f MB | speed-up %.2fx",
                     tSparse, Double(sparse.storageBytes) / 1_048_576, sparseMB, baseMB, tDense, denseOverlapMB, denseMB, tDense / tSparse))
    }
}
