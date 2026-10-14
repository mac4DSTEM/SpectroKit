//
//  SDDEfficiency.swift
//  Role: A GENERIC silicon-drift-detector efficiency model with every layer named.
//        It is NOT the owner's Super-X calibration (Thermo publishes no layer data we hold).
//
//  eps(E) = exp(-mu_Au rho t_Au) exp(-mu_Al rho t_Al) exp(-mu_Si rho t_dead)
//           (1 - exp(-mu_Si rho t_Si))
//  Port of the formula in EPQ `Detector/SiLiCalibration.java` getEfficiency()
//  (lines ~92-129): same layers (Ni layer omitted = 0, no window), MACs from FFAST
//  (`MassAbsorptionTable`), densities from QuantElementData (Au 19.3, Al 2.7, Si 2.33
//  g/cm^3). The constant detector area and 1/4pi of EPQ cancel in k ratios and are
//  dropped; ONLY ratios of eps enter a k-factor.
//  Defaults are EPQ's `DetectorProperties.getDefaultSDDProperties` EXACTLY: Au 0 nm,
//  Al 10 nm, Si dead layer 0 um, Si 450 um (named in the source string). All four are
//  parameters; typing others is the user's act, never a silent mix of EPQ's SiLi and
//  SDD defaults (round 2 had such a mix; round 3 removed it).
//  Outside the FFAST table of any layer element, eps returns 0 and ComputedKFactor
//  refuses.
//

import Foundation

package nonisolated struct SDDEfficiency: DetectorEfficiency {
    package var goldNm = 0.0
    package var aluminiumNm = 10.0
    package var deadLayerMicrons = 0.0
    package var siliconMicrons = 450.0
    package let table: MassAbsorptionTable

    package init(table: MassAbsorptionTable, goldNm: Double = 0, aluminiumNm: Double = 10,
                 deadLayerMicrons: Double = 0, siliconMicrons: Double = 450) {
        self.table = table; self.goldNm = goldNm; self.aluminiumNm = aluminiumNm
        self.deadLayerMicrons = deadLayerMicrons; self.siliconMicrons = siliconMicrons
    }

    package var sourceName: String {
        "EPQ getDefaultSDDProperties (Au \(goldNm) nm, Al \(aluminiumNm) nm, Si dead layer \(deadLayerMicrons) \u{00B5}m, Si \(siliconMicrons) \u{00B5}m); "
            + "generic SDD model, not the owner's Super-X calibration; FFAST MACs"
    }

    package func efficiency(energyKeV e: Double) -> Double {
        func rho(_ s: String) -> Double { QuantElementData.entry(s)!.density! }
        guard let au = try? table.mac(element: "Au", energyKeV: e),
              let al = try? table.mac(element: "Al", energyKeV: e),
              let si = try? table.mac(element: "Si", energyKeV: e) else { return 0 }
        return exp(-au * rho("Au") * goldNm * 1e-7) * exp(-al * rho("Al") * aluminiumNm * 1e-7)
            * exp(-si * rho("Si") * deadLayerMicrons * 1e-4) * (1 - exp(-si * rho("Si") * siliconMicrons * 1e-4))
    }
}
