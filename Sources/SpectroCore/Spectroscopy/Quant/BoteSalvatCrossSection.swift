//
//  BoteSalvatCrossSection.swift
//  Role: Total electron-impact ionisation cross-section of K, L and M shells,
//        Bote-Salvat 2008, from the tables NIST EPQ ships (public domain in the US).
//
//  Port of EPQ `EPQLibrary/AbsoluteIonizationCrossSection.java`, class
//  BoteSalvatCrossSection (commit 249dd3f8, lines ~80-185), itself a transcription
//  of D. Bote and F. Salvat's Fortran `xion.f` (Sept 2008). References:
//  D. Bote and F. Salvat, Phys. Rev. A 77, 042701 (2008); D. Bote et al., At. Data
//  Nucl. Data Tables 95, 871 (2009).
//  Tables (Resources/Spectroscopy, pinned by tools/lib/fetch-epq.sh):
//    SalvatXionA.csv  Z, then 5 fit coefficients per shell (K, L1, L2, L3, M1..M5)
//    SalvatXionB.csv  Z, then 6 numbers per shell: Be, Anlj, g1, g2, g3, g4
//    xionUis.csv      Z, then the shell ionisation energies in eV (K, L1, ...)
//  EDGE ENERGY: U = E / Ec uses `xionUis.csv`, the Dirac-Hartree-Slater energies the
//  coefficients were fitted with (EPQ's EdgeEnergy.DHSIonizationEnergy reads the
//  same file) -- not a measured edge such as FFAST's.
//  Formula (EPQ's, E in eV): U <= 16 -> opu = 1/(1+U), f = a0 + a1 U + opu(a2 +
//  opu^2 (a3 + opu^2 a4)), xi = (U-1)(f/U)^2;  U > 16 -> beta^2 = E(E+2m)/(E+m)^2,
//  x = sqrt(E(E+2m))/m, ffit = (2 ln x - beta^2)(1 + g1/x) + g2 + g3 (m^2/(E+m)^2)^(1/4)
//  + g4/x, xi = (Anlj/beta^2) U/(U+Be) ffit;  sigma[cm^2] = 4 pi a0^2 xi.
//  CONSTANTS ARE EPQ's CODATA-2002 VALUES ON PURPOSE (m_e c^2 = 510 998.916 eV, a0 =
//  5.291772083e-11 m); CODATA 2018's 510 998.95 eV would break EPQ parity -- do not "fix" them.
//  Constants are EPQ's CODATA 2002 values so the numbers match EPQ's, not CODATA 2018:
//  Bohr radius 5.291772083e-11 m, m_e c^2 = 8.1871047e-14 J / 1.60217653e-19 C.
//
//  DEVIATIONS: a shell with no table row returns nil (EPQ: `isSupported` false ->
//  zero); only K lines map to a shell in `IonisationCrossSection.sigma` (L and M
//  need subshell ionisation plus Coster-Kronig, deferred); Z outside 1...99
//  returns nil (EPQ throws). NOT Velox's Brown-Powell: Velox's manual says Bote-
//  Salvat "typically under-estimates the atomic fractions for lighter elements".
//

import Foundation

package nonisolated struct BoteSalvatCrossSection: IonisationCrossSection {
    package static let shellNames = ["K", "L1", "L2", "L3", "M1", "M2", "M3", "M4", "M5"]
    private static let bohrRadiusCm = 5.291772083e-11 * 100
    private static let restMassEV = 8.1871047e-14 / 1.60217653e-19
    private static let fourPiA0Sq = 4 * Double.pi * bohrRadiusCm * bohrRadiusCm

    private let a: [Int: [[Double]]]      // [Z][shell][5]
    private let b: [Int: [[Double]]]      // [Z][shell][6]: Be, Anlj, g1...g4
    private let uis: [Int: [Double]]      // [Z][shell] eV

    package let sourceName =
        "Bote-Salvat 2008 (NIST EPQ tables, PRA 77 042701), edges DHS xionUis.csv; not Velox's Brown-Powell default"

    package init(tableA: String, tableB: String, edges: String) {
        func parse(_ s: String) -> [Int: [Double]] {
            var out: [Int: [Double]] = [:]
            for line in s.split(whereSeparator: \.isNewline) {
                let f = line.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                if f.count > 1 { out[Int(f[0].rounded())] = Array(f.dropFirst()) }
            }
            return out
        }
        func blocks(_ d: [Int: [Double]], _ n: Int) -> [Int: [[Double]]] {
            d.mapValues { v in stride(from: 0, to: v.count - n + 1, by: n).map { Array(v[$0..<$0 + n]) } }
        }
        a = blocks(parse(tableA), 5); b = blocks(parse(tableB), 6); uis = parse(edges)
    }

    package init(directory: URL) throws {
        func read(_ n: String) throws -> String { try String(contentsOf: directory.appendingPathComponent(n), encoding: .utf8) }
        self.init(tableA: try read("SalvatXionA.csv"), tableB: try read("SalvatXionB.csv"), edges: try read("xionUis.csv"))
    }

    package static func bundled(in bundle: Bundle = .main) -> BoteSalvatCrossSection? {
        guard let url = bundle.url(forResource: "xionUis", withExtension: "csv", subdirectory: "Spectroscopy")
            ?? bundle.url(forResource: "xionUis", withExtension: "csv") else { return nil }
        return try? BoteSalvatCrossSection(directory: url.deletingLastPathComponent())
    }

    /// Ionisation energy (eV) of `shell` (0 = K, 1 = L1, ...), nil if untabulated.
    package func edgeEV(z: Int, shell: Int) -> Double? {
        guard let u = uis[z], u.indices.contains(shell) else { return nil }
        return u[shell]
    }

    /// Cross-section in cm^2; 0 at or below the edge; nil when the shell has no table.
    package func sigma(z: Int, shell: Int, energyEV eev: Double) -> Double? {
        guard let uev = edgeEV(z: z, shell: shell) else { return nil }
        guard uev >= 1e-35, eev > uev else { return 0 }
        let overV = eev / uev
        let m = Self.restMassEV
        var xi = 0.0
        if overV <= 16 {
            guard let c = a[z], c.indices.contains(shell) else { return 0 }
            let p = c[shell]
            let opu = 1 / (1 + overV), opu2 = opu * opu
            let f = p[0] + p[1] * overV + opu * (p[2] + opu2 * (p[3] + opu2 * p[4]))
            xi = (overV - 1) * pow(f / overV, 2)
        } else {
            guard let c = b[z], c.indices.contains(shell) else { return 0 }
            let p = c[shell]
            let (be, anlj, g1, g2, g3, g4) = (p[0], p[1], p[2], p[3], p[4], p[5])
            let beta2 = eev * (eev + 2 * m) / ((eev + m) * (eev + m))
            let x = (eev * (eev + 2 * m)).squareRoot() / m
            let ffit = (2 * log(x) - beta2) * (1 + g1 / x) + g2 + g3 * pow(m * m / ((eev + m) * (eev + m)), 0.25) + g4 / x
            xi = (anlj / beta2) * overV / (overV + be) * ffit
        }
        return Self.fourPiA0Sq * xi
    }

    package func sigma(element: String, line: String, beamEnergyKeV: Double) -> Double? {
        guard line.hasPrefix("K"), let z = QuantElementData.entry(element)?.z else { return nil }
        return sigma(z: z, shell: 0, energyEV: beamEnergyKeV * 1000)
    }
}
