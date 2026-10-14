//
//  MeanFreePath.swift
//  Role: The inelastic mean free path λ and the angular correction, as exSpy applies them to turn t/λ into a thickness
//        in nm (`exspy/signals/_eels.py:817-851`), from
//        `exspy/utils/eels/electron_inelastic_mean_free_path.py` at 7185a4d1.
//
//  The arithmetic follows the Python expressions operand by operand (`**` is `pow`, as CPython's float power is), so the
//  values equal exSpy's to rounding (pinned: relative 1e-13 on a grid of 4 densities x 5 beam energies x 3 convergence
//  x 3 collection angles).
//

import Foundation

/// Where λ comes from, and whether exSpy's angular correction is applied.
///
/// exSpy's three routes (`_eels.py:817-851`):
///  * only a mean free path (`.given`): thickness = (t/λ) · λ, no correction;
///  * only a density (`.iakoubovskii`): the correction multiplies t/λ and λ is Iakoubovskii's eq. 9;
///  * both (`.givenWithAngularCorrection`): the correction still multiplies t/λ, and the GIVEN λ is used. (A given λ that
///    already includes the finite collection angle would be corrected twice: that is exSpy's behaviour, ported as is.)
public nonisolated enum MeanFreePathSource: Sendable, Equatable {
    /// λ in nm, taken as given; no angular correction (exSpy `mean_free_path=`, no `density=`).
    case given(_ nanometres: Double)
    /// λ from the material's density by Iakoubovskii et al. 2008 eq. 9 (`iMFP_Iakoubovskii`, `electron_inelastic_mean_free_path.py:32-68`)
    /// with the angular correction of the same paper (`iMFP_angular_correction`, `:121-161`).
    /// Density in g/cm³, beam energy in keV, convergence (α) and collection (β) semi-angles in mrad.
    case iakoubovskii(density: Double, beamEnergyKeV: Double, convergenceMrad: Double, collectionMrad: Double)
    /// A given λ (nm) AND the angular correction from the density (exSpy `density=` and `mean_free_path=` together).
    case givenWithAngularCorrection(_ nanometres: Double, density: Double, beamEnergyKeV: Double,
                                    convergenceMrad: Double, collectionMrad: Double)
}

public nonisolated enum InelasticMeanFreePath {

    /// `_F(E0) = (1 + E0/1022) / (1 + E0/511)²` (`electron_inelastic_mean_free_path.py:24-25`), E0 in keV.
    package static func relativisticF(_ e0: Double) -> Double {
        (1 + e0 / 1022) / pow(1 + e0 / 511, 2.0)
    }

    /// `_theta_E(ρ, E0) = 5.5 ρ^0.3 / (F E0)` mrad (`:28-29`).
    package static func thetaE(density: Double, beamEnergyKeV e0: Double) -> Double {
        5.5 * pow(density, 0.3) / (relativisticF(e0) * e0)
    }

    /// Iakoubovskii et al. 2008 eq. 9, exSpy `iMFP_Iakoubovskii` (`:32-68`): 1/λ = 11 ρ^0.3 / (200 F E0) · ln(θ_C² / θ_E²),
    /// θ_C = 20 mrad. λ in nm.
    public static func iakoubovskii(density: Double, beamEnergyKeV e0: Double) -> Double {
        let thetaC = 20.0
        let invLambda = 11 * pow(density, 0.3) / (200 * relativisticF(e0) * e0)
            * log(pow(thetaC, 2.0) / pow(thetaE(density: density, beamEnergyKeV: e0), 2.0))
        return 1 / invLambda
    }

    /// exSpy `iMFP_angular_correction` (`:121-161`): ln(θ_C²/θ_E²) / ln(A θ_C² / (B θ_E²)), with
    /// A = α² + β² + 2θ_E² + |α² − β²| and B = α² + β² + 2θ_C² + |α² − β²| (mrad).
    public static func angularCorrection(density: Double, beamEnergyKeV e0: Double, convergenceMrad alpha: Double,
                                         collectionMrad beta: Double) -> Double {
        let thetaC = 20.0
        let te = thetaE(density: density, beamEnergyKeV: e0)
        let a = pow(alpha, 2.0) + pow(beta, 2.0) + 2 * pow(te, 2.0) + abs(pow(alpha, 2.0) - pow(beta, 2.0))
        let b = pow(alpha, 2.0) + pow(beta, 2.0) + 2 * pow(thetaC, 2.0) + abs(pow(alpha, 2.0) - pow(beta, 2.0))
        return log(pow(thetaC, 2.0) / pow(te, 2.0)) / log(a * pow(thetaC, 2.0) / b / pow(te, 2.0))
    }

    /// The λ and correction a source implies, validated. `correction` is nil for `.given` (no density).
    package static func resolve(_ source: MeanFreePathSource) throws -> (lambdaNM: Double, correction: Double?) {
        func bad(_ why: String) -> EELSThicknessError { .invalidMeanFreePath(why) }
        func validate(density: Double, beamEnergyKeV: Double, convergence: Double, collection: Double) throws {
            guard density.isFinite, density > 0 else { throw bad("density \(density) g/cm3 is not a positive number") }
            guard beamEnergyKeV.isFinite, beamEnergyKeV > 0 else { throw bad("beam energy \(beamEnergyKeV) keV is not a positive number") }
            guard convergence.isFinite, convergence >= 0, collection.isFinite, collection >= 0 else {
                throw bad("convergence \(convergence) and collection \(collection) mrad must be finite and not negative")
            }
        }
        switch source {
        case .given(let nm):
            guard nm.isFinite, nm > 0 else { throw bad("mean free path \(nm) nm is not a positive number") }
            return (nm, nil)
        case .iakoubovskii(let rho, let e0, let alpha, let beta):
            try validate(density: rho, beamEnergyKeV: e0, convergence: alpha, collection: beta)
            let lambda = iakoubovskii(density: rho, beamEnergyKeV: e0)
            let correction = angularCorrection(density: rho, beamEnergyKeV: e0, convergenceMrad: alpha, collectionMrad: beta)
            guard lambda.isFinite, lambda > 0, correction.isFinite, correction > 0 else {
                throw bad("Iakoubovskii's model gives lambda \(lambda) nm and correction \(correction) for these inputs (outside its range)")
            }
            return (lambda, correction)
        case .givenWithAngularCorrection(let nm, let rho, let e0, let alpha, let beta):
            guard nm.isFinite, nm > 0 else { throw bad("mean free path \(nm) nm is not a positive number") }
            try validate(density: rho, beamEnergyKeV: e0, convergence: alpha, collection: beta)
            let correction = angularCorrection(density: rho, beamEnergyKeV: e0, convergenceMrad: alpha, collectionMrad: beta)
            guard correction.isFinite, correction > 0 else {
                throw bad("the angular correction is \(correction) for these inputs (outside the model's range)")
            }
            return (nm, correction)
        }
    }
}
