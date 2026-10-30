//
//  WindowRules.swift
//  Role: The rules behind the window-based line intensities and the default line of an element, as one value. Every field's
//        default is the value the windows have always used; a different value is a different, named choice, never a hidden one.
//

import Foundation

/// The choices that shape the integration and background windows of a line, the report of what a background window lies on, the
/// family an element is quantified with by default, and whether two windows of one element may overlap.
///
/// `WindowRules.default` is the rule set of eXSpy 7185a4d1 for the first three fields and the library's own choice for the rest.
/// A window is always E ± a multiple of the line's FWHM (the detector's line width at that energy), so every width here is in
/// FWHM units.
///
/// The window results (`ElementWindows`, the maps of `WindowIntensity`) carry numbers and no notes, so they do not name the rules
/// they were built with: a caller that passes a non-default value records it with the numbers it shows.
public nonisolated struct WindowRules: Sendable, Equatable, Codable {
    /// Integration window `[E - W F / 2, E + W F / 2]`: W. Default 2.0 (eXSpy `estimate_integration_windows`), which holds 98 % of a
    /// Gaussian line. A smaller W loses signal (W = 1 holds 76 %); a larger one adds noise.
    public var integrationWindowsWidth: Double
    /// Gap between the line and the left background window, in FWHM (eXSpy `line_width[0]`). Default 2.
    public var backgroundGapLeft: Double
    /// Gap between the line and the right background window, in FWHM (eXSpy `line_width[1]`). Default 2.
    public var backgroundGapRight: Double
    /// Width of each background window, in FWHM (eXSpy `windows_width`). Default 1. A wider window averages more channels and
    /// reaches farther along a sloping or peaked background.
    public var backgroundWindowsWidth: Double
    /// The conflict report (`WindowConflict`) considers only table lines at least this heavy relative to their family's alpha
    /// line. Default 0.01. It changes the report, never the counts.
    public var conflictMinimumWeight: Double
    /// The conflict report counts a table line's flank as `max(F_other * this, half its integration window)`. Default 2. It
    /// changes the report, never the counts.
    public var conflictFlankFWHM: Double
    /// An element is quantified by default on its K alpha line while that line is at or below this energy, keV, otherwise on L
    /// (M when the table has no L alpha). Default 20 keV, the boundary one instrument's 200 kV files showed. It changes which
    /// line a window is built on by default, never a fit.
    public var kFamilyLimitKeV: Double
    /// Two checked lines of one element whose signal windows overlap: the later window starts where the earlier ends, and its
    /// background scale shrinks with it, so a sum of nets counts every channel once. Default true. False leaves each window as
    /// the formulas build it, so the shared channels are counted in both nets.
    public var clipOverlappingWindows: Bool

    public init(integrationWindowsWidth: Double = 2.0, backgroundGapLeft: Double = 2, backgroundGapRight: Double = 2,
                backgroundWindowsWidth: Double = 1, conflictMinimumWeight: Double = 0.01, conflictFlankFWHM: Double = 2,
                kFamilyLimitKeV: Double = 20, clipOverlappingWindows: Bool = true) {
        self.integrationWindowsWidth = integrationWindowsWidth
        self.backgroundGapLeft = backgroundGapLeft
        self.backgroundGapRight = backgroundGapRight
        self.backgroundWindowsWidth = backgroundWindowsWidth
        self.conflictMinimumWeight = conflictMinimumWeight
        self.conflictFlankFWHM = conflictFlankFWHM
        self.kFamilyLimitKeV = kFamilyLimitKeV
        self.clipOverlappingWindows = clipOverlappingWindows
    }

    /// The values the windows have always used.
    public static let `default` = WindowRules()

    /// True when every field is the default's.
    public var isDefault: Bool { self == .default }

    /// `[left gap, right gap]`, the form `BackgroundWindows.estimate(lineWidth:)` takes.
    package var backgroundLineWidth: [Double] { [backgroundGapLeft, backgroundGapRight] }
}
