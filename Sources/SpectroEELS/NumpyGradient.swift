//
//  NumpyGradient.swift
//  Role: `numpy.gradient(f, x)` (edge_order=1) of a spectrum on the cropped energy axis `x`, which is what exSpy's
//        `estimate_elastic_scattering_threshold(window_length=0)` uses as the derivative (`exspy/signals/_eels.py:723-724`,
//        `s.derivative(-1)`, HyperSpy `signal.py:4846-4853`, `np.gradient(der_data, axis.axis, axis=...)`).
//
//  Ported from NumPy 2.5.4 `numpy/lib/_function_base_impl.py:1265-1357`. `diffx = diff(x)`; when every spacing is equal
//  (`diffx == diffx[0]`) the spacing is a scalar and the interior is `(f[i+1] - f[i-1]) / (2 * dx)`; otherwise, with
//  `dx1 = dx[i-1]`, `dx2 = dx[i]`: `a = -dx2 / (dx1 (dx1 + dx2))`, `b = (dx2 - dx1) / (dx1 dx2)`, `c = dx1 / (dx2 (dx1 + dx2))`
//  and `out[i] = a f[i-1] + b f[i] + c f[i+1]` evaluated left to right, each product rounded (no fused multiply-add).
//  The edges are the one-sided differences `(f[1] - f[0]) / dx[0]` and `(f[n-1] - f[n-2]) / dx[n-2]`. The planted axis
//  (scale 0.05) has spacings that differ by an ulp and takes the second branch; the line scan (scale 0.5) the first.
//

import Foundation

package nonisolated struct NumpyGradient: Sendable {
    package let uniformSpacing: Double?
    package let dx: [Double]
    package let a: [Double]
    package let b: [Double]
    package let c: [Double]
    package let count: Int

    /// Spacing from the axis values `x` (at least two).
    package init(axis x: [Double]) {
        precondition(x.count >= 2)
        count = x.count
        var d = [Double](repeating: 0, count: x.count - 1)
        for i in 0..<(x.count - 1) { d[i] = x[i + 1] - x[i] }
        dx = d
        if d.allSatisfy({ $0 == d[0] }) {
            uniformSpacing = d[0]
            a = []; b = []; c = []
        } else {
            uniformSpacing = nil
            var aa = [Double](), bb = [Double](), cc = [Double]()
            for i in 0..<(d.count - 1) {
                let dx1 = d[i], dx2 = d[i + 1]
                aa.append(-(dx2) / (dx1 * (dx1 + dx2)))
                bb.append((dx2 - dx1) / (dx1 * dx2))
                cc.append(dx1 / (dx2 * (dx1 + dx2)))
            }
            a = aa; b = bb; c = cc
        }
    }

    package func apply(_ f: UnsafeBufferPointer<Double>, into out: UnsafeMutableBufferPointer<Double>) {
        let n = f.count
        precondition(n == count && out.count == n)
        if let h = uniformSpacing {
            let twoH = 2.0 * h
            for i in 1..<(n - 1) { out[i] = (f[i + 1] - f[i - 1]) / twoH }
            out[0] = (f[1] - f[0]) / h
            out[n - 1] = (f[n - 1] - f[n - 2]) / h
        } else {
            for i in 1..<(n - 1) {
                let t1 = a[i - 1] * f[i - 1]
                let t2 = b[i - 1] * f[i]
                let t3 = c[i - 1] * f[i + 1]
                out[i] = (t1 + t2) + t3
            }
            out[0] = (f[1] - f[0]) / dx[0]
            out[n - 1] = (f[n - 1] - f[n - 2]) / dx[n - 2]
        }
    }
}
