//
//  EdgeCrossSection.swift
//  Role: The energy-differential cross section of a K edge (barn/eV) as exSpy 7185a4d1's `EELSCLEdge` with the dft GOS
//        computes it: the effective collection angle (`exspy/utils/eels/effective_angle.py:23-80`, Egerton 2nd ed. p. 420),
//        the q integration (`exspy/_misc/eels/base_gos.py`, `get_qaxis_and_gos` and `integrateq`), the interpolating
//        spline between tabulated energies and the power law beyond them (`components/_eels_cl_edge.py:436-494`).
//
//
//  Precision as exSpy runs on NumPy 2.5.4: the GOS arrays are float32 and, by NEP 50, a Python float meeting a float32
//  scalar or array is cast to float32, so the q limits, the GOS interpolated to q_max, the prefactor and the
//  extrapolation's E^-r are float32 there and are float32 here (each place marked "f32"). Constants as SciPy 1.18.1
//  holds them (CODATA 2022): the Bohr radius and the Rydberg energy in eV.
//

import Foundation

package nonisolated struct EdgeCrossSection: Sendable {
    /// `scipy.constants.value("Bohr radius")`, m.
    package static let bohrRadius = 5.29177210544e-11
    /// `scipy.constants.value("Rydberg constant times hc in eV")`, eV.
    package static let rydbergEV = 13.60569312299

    package let table: GOSTable
    package let beamEnergyKeV: Double
    /// The effective collection semi-angle used, mrad.
    package let effectiveAngleMrad: Double
    /// `qint`: barn/eV at each tabulated energy.
    package let qint: [Double]
    package let spline: InterpolatingSpline
    /// The last tabulated energy (float32, as exSpy's `Emax`).
    package let maxEnergy: Float
    package let powerLawR: Double
    package let powerLawA: Double

    /// `effective_angle(E0, E, alpha, beta)`, mrad.
    package static func effectiveAngle(beamEnergyKeV e0In: Double, energyLossEV e: Double, convergenceMrad alpha: Double,
                                       collectionMrad beta: Double) -> Double {
        var e0 = e0In
        e0 *= 1e3
        if alpha == 0 { return beta }
        e0 *= Libm.pow(10.0, -3)
        let tgt = e0 * (1.0 + e0 / 1022.0) / (1.0 + e0 / 511.0)
        let thetaE = e / tgt
        let a2 = alpha * alpha * 1e-6
        let b2 = beta * beta * 1e-6
        let t2 = thetaE * thetaE * 1e-6
        let eta1 = sqrt(Libm.pow(a2 + b2 + t2, 2) - 4.0 * a2 * b2) - a2 - b2 - t2
        let eta2 = 2.0 * b2 * log(0.5 / t2 * (sqrt(Libm.pow(a2 + t2 - b2, 2) + 4.0 * b2 * t2) + a2 + t2 - b2))
        let eta3 = 2.0 * a2 * log(0.5 / t2 * (sqrt(Libm.pow(b2 + t2 - a2, 2) + 4.0 * a2 * t2) + b2 + t2 - a2))
        let f1 = (eta1 + eta2 + eta3) / 2 / a2 / log(1.0 + b2 / t2)
        var f2 = f1
        if (alpha / beta) > 1 { f2 = f1 * a2 / b2 }
        return thetaE * sqrt(exp(f2 * log(1.0 + b2 / t2)) - 1.0)
    }

    /// `set_microscope_parameters(E0, alpha, beta, scale)` then `_integrate_GOS()`; nil when exSpy would raise (a q limit
    /// outside what the table can interpolate, a singular spline).
    package init?(table: GOSTable, beamEnergyKeV e0: Double, convergenceMrad alpha: Double, collectionMrad beta: Double) {
        guard e0 > 0, alpha >= 0, beta > 0, e0.isFinite, alpha.isFinite, beta.isFinite,
              table.energyAxis.count >= 4, table.q.count >= 2 else { return nil }
        self.table = table
        self.beamEnergyKeV = e0
        let angleMrad = Self.effectiveAngle(beamEnergyKeV: e0, energyLossEV: table.edge.onsetEV, convergenceMrad: alpha,
                                            collectionMrad: beta)
        self.effectiveAngleMrad = angleMrad
        let angle = angleMrad * 1e-3
        let a0 = Self.bohrRadius, r = Self.rydbergEV
        let gamma = 1 + e0 / 511.06
        let t = 511060 * (1 - 1 / Libm.pow(gamma, 2)) / 2
        // Python-float subexpressions, computed in double, then cast to float32 where they meet a float32 value.
        let den1 = Float(4 * r * t)
        let den2 = Float(8 * Libm.pow(gamma, 3) * r * Libm.pow(t, 2))
        let p02 = t / (r * (1 - 2 * t / 511060))
        let sin2 = Libm.pow(sin(angle / 2), 2)
        var qint = [Double](repeating: 0, count: table.energyAxis.count)
        for i in 0 ..< table.energyAxis.count {
            let e = table.energyAxis[i] + Float(0.0)                                   // f32: energy_axis[i] + shift
            let qa0sqmin = Libm.powf(e, 2) / den1 + Libm.powf(e, 3) / den2                       // f32
            let pp2 = Float(p02) - e / Float(r) * (Float(gamma) - e / Float(1022120))  // f32
            let qa0sqmax = qa0sqmin + Float(4) * (Float(p02) * pp2).squareRoot() * Float(sin2)   // f32
            let qmin = Double(qa0sqmin).squareRoot() / a0
            let qmax = Double(qa0sqmax).squareRoot() / a0
            guard let (qaxis, g) = Self.qaxisAndGOS(table: table, energyIndex: i, qmin: qmin, qmax: qmax) else { return nil }
            let logq = qaxis.map { v -> Double in let s = a0 * v; return log(s * s) }
            qint[i] = ScipySimpson.integrate(g, x: logq)
        }
        // qint *= (4.0*np.pi*a0**2.0*R**2/E/T*subshell_factor)*1e28, the bracket float32 (E is the float32 energy axis).
        let c = 4.0 * Double.pi * Libm.pow(a0, 2.0) * Libm.pow(r, 2)
        for i in 0 ..< qint.count {
            let e = table.energyAxis[i] + Float(0.0)
            let pre = (Float(c) / e / Float(t) * table.occupancyRatio) * Float(1e28)  // f32
            qint[i] *= Double(pre)
        }
        self.qint = qint
        guard let s = InterpolatingSpline(x: table.energyAxis.map { Double($0) }, y: qint) else { return nil }
        self.spline = s
        let n = table.energyAxis.count
        let e1 = table.energyAxis[n - 2] + Float(0.0), e2 = table.energyAxis[n - 1] + Float(0.0)   // f32
        let y1 = qint[n - 2], y2 = qint[n - 1]
        let rr = log(y2 / y1) / log(Double(e1 / e2))
        self.powerLawR = rr
        self.powerLawA = y1 / Double(Libm.powf(e1, Float(-rr)))                            // E1**-r in f32
        self.maxEnergy = e2
    }

    /// exSpy's `function(E)` with intensity 1 and no fine structure: barn/eV at each energy (eV).
    package func differential(_ energies: [Double]) -> [Double] {
        let emax = Double(maxEnergy), onset = table.edge.onsetEV
        return energies.map { e in
            if e < emax && e >= onset { return spline(e) }
            if e >= emax { return powerLawA * Libm.pow(e, -powerLawR) }
            return 0
        }
    }

    /// `get_qaxis_and_gos(i, qmin, qmax)`: the tabulated q axis cut to [qmin, qmax] with the GOS linearly interpolated at
    /// both ends (hyperspy `get_linear_interpolation`) and clipped at 0; nil where exSpy's slicing would fail.
    private static func qaxisAndGOS(table: GOSTable, energyIndex i: Int, qmin: Double, qmax: Double)
        -> (q: [Double], gos: [Double])? {
        let qt = table.q, row = table.gos[i], m = qt.count
        // A NaN limit (E0 so low, or an angle so large, that the momentum transfer has no real value at this energy) is
        // where exSpy's arithmetic produces NaN and its slicing fails; the port refuses (review of the consumer check).
        guard qmin.isFinite, qmax.isFinite, qmin <= qmax else { return nil }
        var qaxis: [Double]
        var g32: [Float]
        if qmax > Double(qt[m - 1]) {
            let gq = interpolate32(q1: qt[m - 2], g1: row[m - 2], q2: qt[m - 1], g2: row[m - 1], at: qmax)
            qaxis = qt.map { Double($0) } + [qmax]
            g32 = row + [gq]
        } else {
            let index = qt.firstIndex { Double($0) >= qmax } ?? m             // searchsorted, side 'left'
            guard index >= 1, index < m else { return nil }
            let gq = interpolate32(q1: qt[index - 1], g1: row[index - 1], q2: qt[index], g2: row[index], at: qmax)
            qaxis = qt[..<index].map { Double($0) } + [qmax]
            g32 = Array(row[..<index]) + [gq]
        }
        guard qmin > 0 else { return (qaxis, g32.map { max(Double($0), 0) }) }
        let index = qt.firstIndex { Double($0) >= qmin } ?? m                // on the tabulated axis, as exSpy
        guard index >= 1, index + 1 <= qaxis.count, index < g32.count else { return nil }
        // g1, g2 float32 and q1, q2 float64: (g2 - g1) in f32, everything after in f64.
        let g1 = g32[index - 1], g2 = g32[index], q1 = qaxis[index - 1], q2 = qaxis[index]
        let a = Double(g2 - g1) / (q2 - q1)
        let b = (q2 * Double(g1) - q1 * Double(g2)) / (q2 - q1)
        let gmin = a * qmin + b
        let q = [qmin] + Array(qaxis[index...])
        let g = [gmin] + g32[index...].map { Double($0) }
        return (q, g.map { max($0, 0) })
    }

    /// `get_linear_interpolation((q1, g1), (q2, g2), x)` with float32 points and a Python-float x: all in float32.
    private static func interpolate32(q1: Float, g1: Float, q2: Float, g2: Float, at x: Double) -> Float {
        let a = (g2 - g1) / (q2 - q1)
        let b = (q2 * g1 - q1 * g2) / (q2 - q1)
        return a * Float(x) + b
    }
}
