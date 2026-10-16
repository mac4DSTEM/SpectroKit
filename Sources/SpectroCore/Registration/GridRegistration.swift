import Foundation

/// An affine from source pixel centres to target spectrum pixel centres.
/// Each pixel covers the unit square centred on its integer coordinate.
/// Reflections are allowed. Spectra remain on their native grid.
public struct GridRegistration: Sendable, Equatable {
    /// Row-major 2 × 3 affine: `[a00, a01, a02, a10, a11, a12]`.
    public let matrix: [Double]
    /// Source grid dimensions in pixels.
    public let scanWidth: Int
    public let scanHeight: Int
    /// Target spectrum grid dimensions in pixels.
    public let spectrumWidth: Int
    public let spectrumHeight: Int

    /// Refuses malformed matrices, singular maps, nonpositive or overflowing grid sizes.
    public init(matrix: [Double], scanWidth: Int, scanHeight: Int,
                spectrumWidth: Int, spectrumHeight: Int) throws {
        guard matrix.count == 6, matrix.allSatisfy({ $0.isFinite && abs($0) < 1e9 }),
              scanWidth > 0, scanHeight > 0, spectrumWidth > 0, spectrumHeight > 0,
              !scanWidth.multipliedReportingOverflow(by: scanHeight).overflow,
              !spectrumWidth.multipliedReportingOverflow(by: spectrumHeight).overflow else {
            throw MaskTransportError(description: "Invalid affine matrix or grid dimensions.")
        }
        self.matrix = matrix
        self.scanWidth = scanWidth; self.scanHeight = scanHeight
        self.spectrumWidth = spectrumWidth; self.spectrumHeight = spectrumHeight
        guard isInvertible else { throw MaskTransportError(description: "The registration is singular.") }
    }

    /// Signed area scale; negative for a mirror.
    public var determinant: Double { matrix[0] * matrix[4] - matrix[1] * matrix[3] }
    /// The source uses a determinant floor of 1e-12.
    public var isInvertible: Bool { determinant.isFinite && abs(determinant) > 1e-12 }
}
