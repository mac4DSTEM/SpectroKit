# EELS task 16: zero-loss alignment, background, deconvolution, edge fit (design note)

Suite ROADMAP task 16, SpectroKit 0.9.0. Written 2026-10-21 for a Mac session to implement without further design work.
Reference: exSpy 0.3.2 (`exspy/signals/eels.py`, `exspy/models/eelsmodel.py`, `exspy/components/eels_cl_edge.py`) and
HyperSpy 2.4.0 (`hyperspy/_signals/signal1d.py`, `hyperspy/misc/math_tools.py`, `hyperspy/_components/power_law.py`)
in `../References/python/hyperspy` (suite `tools/setup-python-refs.sh hyperspy`; NumPy 2.5.4, SciPy 1.18.1). Line
numbers below are from those files. Every result stays `validation: "none"`. No code beyond signatures; one screen per
section.

## 0. Scope and order

What the apps need first (macTEM task 8, then mac4DSTEM): the EELS room opens a spectrum image, shows the t/lambda map
and the zero-loss diagnostic. t/lambda exists; the room's first new need is **zero-loss alignment** (real data is never
at 0 eV) and the **zero-loss mask**. Everything else is composition from EELS, which the room offers only once the fit
lands. Implementation order, each step its own commit with a test that fails before and passes after:

1. Zero-loss alignment and mask (section 2). Unblocks macTEM task 8.
2. Power-law extrapolation and Hanning taper (section 3). Small; the deconvolutions stand on them.
3. L-subshell GOS tables and the edge database rows the fit needs (section 6.1).
4. Fourier-log and Fourier-ratio deconvolution (section 4).
5. Edge model fit, background fit, quantify (section 6.2).
6. Richardson-Lucy (section 5), only if the session has time: the ROADMAP lists it out of scope, the coordinator asked
   for its API, so it is designed and ordered last.

Out of scope (ROADMAP): fine-structure fitting, Kramers-Kronig, `rebin`, EDS calibration, hydrogenic and Dirac GOS.
Dependencies: one new package dependency, ImagoKit `"0.6.0"..<"1.0.0"` for `ImagoCore.FFT2DDouble` used as a 1-D plan
(`nx: size, ny: 1`; vDSP for 2^n × {1,3,5,15}, Bluestein for the rest; DiffractoKit precedent; sections 4 and 11 say why).
`ImagoFFT.FFT1DDouble` is power-of-two only and does not fit `next_fast_len` sizes. Readers unchanged.

## 1. Shared types (SpectroEELS)

Inputs stay `LowLossSpectrumImage` and `CoreLossSpectrumImage` (same layout, `counts[(y*nx+x)*channels+c]`, uniform axis
`energyOffsetEV + energyScaleEV * c`, counts per channel). New, public:

```swift
/// One EELS spectrum image regardless of region; LowLoss/CoreLoss images conform. Lets alignment, taper and
/// extrapolation return the caller's type.
public protocol EELSSpectrumImage: Sendable { nx, ny, channels, counts: [Double], energyOffsetEV, energyScaleEV;
    init(nx:ny:channels:counts:energyOffsetEV:energyScaleEV:) throws }

/// A per-pixel answer the method could not give, with the reason (the kit's rule: nil with a reason, never NaN).
public enum EELSUnavailable: String, Error, Sendable { case masked, nonFiniteResult, noPeak, divisionByZero, noTwoRoots }

public enum EELSAlignmentError: Error, Equatable, Sendable {
    case maskShapeMismatch(expected: Int, got: Int), alsoAlignShapeMismatch(index: Int), signalRangeOutsideAxis(fromEV: Double, toEV: Double),
    emptyAfterCrop, nonUniformInput }
public enum EELSDeconvolutionError: Error, Equatable, Sendable {
    case shapeMismatch(expected: Int, got: Int), kernelSizeMismatch(expected: Int, got: Int), invalidFWHM(Double),
    invalidIterations(Int), extrapolationWindowTooWide(window: Int, channels: Int), tooFewChannels(Int) }
public enum EELSModelError: Error, Equatable, Sendable {
    case noEdgeInRange(fromEV: Double, toEV: Double), edgeNotBundled(String), duplicateEdge(String), lowLossShapeMismatch(expected: Int, got: Int),
    backgroundWindowEmpty, fitDidNotConverge(pixel: Int) }
```

`PixelMask = [Bool]` (SpectroCore) is the navigation mask everywhere: `true` = skip the pixel (HyperSpy's `mask`).
Progress and cancellation follow `EELSThickness.logRatio`: `cancelled: @Sendable () -> Bool = SpectroCancellation.task`,
`progress: (@Sendable (Double) -> Void)? = nil`, one check per block of pixels. Every method name string carries the
reference and its version, as `EELSThickness.methodName` does.

## 2. Zero-loss alignment and mask

Reference: `EELSSpectrum.align_zero_loss_peak` (exSpy `eels.py:318-483`), `estimate_zero_loss_peak_centre` (`:275-316`,
`valuemax`: first argmax), `get_zero_loss_peak_mask` (`:485-511`); HyperSpy `Signal1D.shift1D` (`signal1d.py:423-551`,
`_shift1D :252-274`: `make_interp_spline(k=1)` = linear interpolation at `axis - shift`, outside the axis NaN),
`estimate_shift1D` (`:626-736`, `_estimate_shift1D :236-249`, `interpolate1D :220-233`), `align1D` (`:738-853`).

```swift
public struct ZeroLossAlignmentOptions: Sendable, Equatable {
    public var calibrate: Bool = true              // offset -= nanmean(zlpc) after each pass
    public var subpixel: Bool = true               // align1D over signalRangeEV ?? -3...3 eV, reference = pixel 0, linear x6 interpolation
    public var signalRangeEV: ClosedRange<Double>? = nil   // search window for the maximum (value slicing, HyperSpy isig end-exclusive)
    public var crop: Bool = true                   // drop channels any shift left undefined (shift1D ilow/ihigh); false keeps size, NaN -> nil pixels
    public var interpolationPoints: Int = 5        // HyperSpy number_of_interpolation_points; ip = points + 1
}
public struct ZeroLossAlignment: Sendable {
    public let aligned: LowLossSpectrumImage       // new offset and channel count
    public let alsoAligned: [CoreLossSpectrumImage]
    public let initialCentreEV: [Double?]          // zlpc before anything moved (the app's diagnostic); nil where masked
    public let shiftEV: [Double?]                  // total shift applied per pixel (coarse + subpixel)
    public let keptChannels: Range<Int>            // of the input axis, after crop
    public let methodName: String                  // "align_zero_loss_peak, exSpy 0.3.2 / HyperSpy 2.4.0"
}
public enum EELSAlignment {
    public static func alignZeroLossPeak(_ image: LowLossSpectrumImage, alsoAlign: [CoreLossSpectrumImage] = [], mask: PixelMask? = nil,
        options: ZeroLossAlignmentOptions = .init(), cancelled:..., progress:...) throws -> ZeroLossAlignment
    public static func zeroLossPeakCentre(_ image: LowLossSpectrumImage, mask: PixelMask? = nil, signalRangeEV: ClosedRange<Double>? = nil) -> [Double?]
    public static func zeroLossPeakMask(_ image: LowLossSpectrumImage, widthEV: Double = 5.0, signalMask: [Bool]? = nil) -> [Bool]  // per channel
    public static func estimateShift(_ image: LowLossSpectrumImage, fromEV: Double?, toEV: Double?, referencePixel: Int = 0, interpolationPoints: Int = 5,
        mask: PixelMask? = nil) -> [Double?]      // estimate_shift1D in eV; HyperSpy's max_shift is a no-op there (clip without assignment) and is not offered
    public static func shift<I: EELSSpectrumImage>(_ image: I, byEV shifts: [Double?], crop: Bool = true) throws -> (image: I, keptChannels: Range<Int>)
}
```

Port exactly: coarse pass shifts every pixel by `mean(zlpc) - zlpc` (not to zero: to the mean), calibrate subtracts the
new nanmean centre from the offset, subpixel pass only when `pixelCount > 1`, window clamped to the axis as `:453-462`,
`np.correlate(ref, data, "full")` on mean-subtracted, linearly upsampled (`ch*ip-(ip-1)` points) signals, argmax ties to
the first index, shift = (argmax - len(ref) + 1) / ip × scale; then calibrate again. Cross-correlation on the CPU via
`vDSP_convD` in float64 (direct, so the argmax is reproducible). `zlpc` of an all-equal or all-NaN pixel: first index, as
NumPy. `interpolationPoints < 0` and an empty `signalRangeEV` are refused.

Tolerances (upstream): `test_eels.py::TestAlignZLP` mean and std of the re-estimated centre at `assert_allclose`
defaults (rtol 1e-7, atol 0; with mask atol `eps`), `calibrate=False` std atol 1e-2, crop=False keeps size exactly,
`test_align_zero_loss_peak_with_spike_signal_range` max 8 at defaults; HyperSpy `test_1D_tools.py::TestAlignTools`
`test_estimate_shift` atol 1e-3 (eV), `test_shift1D` / `test_align` data at defaults, new offset exact.

## 3. Power-law extrapolation and Hanning taper

Reference: `EELSSpectrum.power_law_extrapolation(window_size=20, extrapolation_size=1024, add_noise=False, fix_neg_r=False)`
(exSpy `eels.py:1236-1331`; `PowerLaw.estimate_parameters(s, E1=index2value(size-window), E2=index2value(size-1), out=True)`
on the zero-extended signal, binned axis multiplies by the scale, `A = where(r <= 0, 0, A)` for `fix_neg_r`);
HyperSpy `Signal1D.hanning_taper(side="both", channels=None, offset=0)` (`signal1d.py:1453-1531`: `channels = max(20,
round(0.02 n))`, `np.hanning(2 channels)` halves, in place, returns `channels`).

```swift
public enum EELSSpectrumOps {
    /// exSpy power_law_extrapolation; add_noise is not offered (random). The window is the existing PowerLawFit (two-area) over the last `windowChannels`.
    public static func powerLawExtrapolation<I: EELSSpectrumImage>(_ image: I, windowChannels: Int = 20, extrapolationChannels: Int = 1024,
        fixNegativeR: Bool = false) throws -> (image: I, fits: [PowerLawParameters?])      // nil where the window sum is not positive (kit rule)
    public static func hanningTaper<I: EELSSpectrumImage>(_ image: I, side: TaperSide = .both, channels: Int? = nil, offset: Int = 0) throws -> (image: I, taperedChannels: Int)
}
public struct PowerLawParameters: Sendable, Equatable { public let a: Double, r: Double }     // HyperSpy A, r
public enum TaperSide: Sendable { case left, right, both }
```

`PowerLawFit` (package) becomes the engine of both; its two-area formula is already pinned (`EdgePinsTests`). The
extrapolation reuses `PowerLawWindow(axis:from:to:)` with HyperSpy's own `value2index` rounding on the extended axis.
Tolerances: `test_eels.py::TestPowerLawExtrapolation` unbinned and binned, extrapolated data atol 1e-2 against the exact
power law (`atol=10e-3`); HyperSpy `tests/component/test_power_law.py` A and r at defaults. Hanning: exact (a product with
`np.hanning`, which is `0.5 - 0.5 cos(2πk/(2c-1))`; compute it the same way, no `vDSP_hann_window` whose normalisation
differs).

## 4. Fourier-log and Fourier-ratio deconvolution

Reference: `fourier_log_deconvolution(zlp, add_zlp=False, crop=False)` (`eels.py:872-977`), `fourier_ratio_deconvolution(low_loss,
fwhm=None, threshold=None, extrapolate_lowloss=True, extrapolate_coreloss=True)` (`:979-1097`), `optimal_fft_size`
(HyperSpy `math_tools.py:148`, `scipy.fft.next_fast_len(size, real)`), `estimate_peak_width(factor=0.5)` (`signal1d.py:1612-1725`,
cubic `UnivariateSpline(s=0)` roots of `y - 0.5 max`, exactly two roots else NaN), HyperSpy `Gaussian` (`A/(σ√2π) exp(-(x-c)²/2σ²)`).

```swift
public struct FourierLogOptions: Sendable, Equatable { public var addZeroLoss = false; public var crop = false }
public struct FourierRatioOptions: Sendable, Equatable {
    public var fwhmEV: Double? = nil                // nil: estimate_peak_width of pixel 0 of the low loss (exSpy uses the current = first spectrum)
    public var threshold: ThresholdRule = .estimated()   // exSpy: estimate_elastic_scattering_threshold() default; a fixed eV is .fixed
    public var extrapolateLowLoss = true, extrapolateCoreLoss = true   // (window 100, size 100) and (20, 100) channels, as exSpy
}
public struct DeconvolvedSpectrumImage<I: EELSSpectrumImage>: Sendable {
    public let image: I; public let unavailable: [EELSUnavailable?]     // per pixel
    public let fftSize: Int; public let fwhmEV: Double?; public let taperedChannels: Int; public let methodName: String
}
public enum EELSDeconvolution {
    public static func fourierLog(_ spectrum: LowLossSpectrumImage, zeroLoss: LowLossSpectrumImage, options: FourierLogOptions = .init(),
        cancelled:..., progress:...) throws -> DeconvolvedSpectrumImage<LowLossSpectrumImage>
    public static func fourierRatio(coreLoss: CoreLossSpectrumImage, lowLoss: LowLossSpectrumImage, options: FourierRatioOptions = .init(),
        cancelled:..., progress:...) throws -> DeconvolvedSpectrumImage<CoreLossSpectrumImage>
    /// scipy.fft.next_fast_len: smallest 2,3,5-smooth (real) or 2,3,5,7,11-smooth (complex) integer >= n. Public so the pins can assert it.
    public static func optimalFFTSize(_ n: Int, real: Bool) -> Int
}
```

Faithful details: Fourier-log takes `size = next_fast_len(zlp + self - 1, real=True)`, `j1 = z · nan_to_num(log(j/z))`,
keeps the first `self` channels, `addZeroLoss` adds the ZLP over its channels, `crop` removes the last `taperedChannels`.
Fourier-ratio takes `size = next_fast_len(ll + cl - 1)` (complex rule: `optimal_fft_size(size)` without `real`), Gaussian on
`linspace(ll.offset, ll.offset + ll.scale (size-1), size)`, result `irfft(z · jk / jl) · I0` cropped to the core-loss size.
The FFT runs on `ImagoCore.FFT2DDouble(nx: size, ny: 1)` (vDSP for 2^n × {1,3,5,15}, Bluestein otherwise) so every
`next_fast_len` size is exact in length (if the `ny: 1` plan proves awkward, an any-length `FFT1DDouble` is a one-task
ImagoKit change, not a SpectroKit copy); `irfft` of a half spectrum follows NumPy's Hermitian rule (imaginary parts of bins 0 and N/2 dropped).

Tolerances: upstream has none (`TestFourierRatioDeconvolution::test_running` only runs). D17 fallback: `assert_allclose`
defaults are rtol 1e-7 with atol 0, which a deconvolved channel near zero can never meet across two FFT libraries. Kit
decision, recorded in `parity.md`: rtol 1e-7 **and** atol 1e-7 × max|pinned result| per pixel; `fftSize`, `taperedChannels`
and the FWHM root positions exact to 1e-9 eV (`UnivariateSpline` roots are a cubic solve; port `scipy`'s `sproot`-free
route: cubic not-a-knot spline through the points, roots per interval by Cardano, as `InterpolatingSpline` already builds
the spline). The planted truth test (section 8) checks that deconvolving a planted plural-scattering spectrum returns
the planted single-scattering distribution within its counting noise.

## 5. Richardson-Lucy deconvolution (ordered last)

Reference: `richardson_lucy_deconvolution(psf, iterations=15)` (`eels.py:1099-1170`): per pixel `imax = argmax(kernel)`,
`first = convolve(kernel, result)[imax : imax+n]`, `result *= convolve(kernel[::-1], signal/first)[n-1-imax : 2n-1-imax]`,
`n = psf_size`, which the slices make equal to the spectrum length (exSpy never checks; the kit refuses a mismatch).

```swift
public enum EELSDeconvolution {   // continued
    public static func richardsonLucy<I: EELSSpectrumImage>(_ spectrum: I, kernel: LowLossSpectrumImage, iterations: Int = 15,
        cancelled:..., progress:...) throws -> DeconvolvedSpectrumImage<I>     // kernel: one spectrum (pixelCount 1) or one per pixel
}
```

Full linear convolution per iteration via `vDSP_convD` (float64, direct; 2048 channels × 15 iterations × 4096 pixels is
about 1 s single-threaded, parallel over pixels as `quantifyMaps` does). A division by a zero `first` gives inf/NaN in
exSpy; the kit marks the pixel `.divisionByZero` and leaves its channels unchanged. Tolerance: none upstream; same
rule as section 4 (rtol 1e-7, atol 1e-7 × max|result|); `iterations < 1` refused.

## 6. Edge model: GOS tables, background fit, edge intensities

### 6.1 Tables and edges

`CoreLossEdge` grows `subshell` beyond K1: `tools/eels-edge/extract_gos.py --subshells L1,L2,L3` writes
`Resources/GOS/dft-<El>-<sub>.json` the same way (float32 kept, sorted keys, md5 of the GOSH file checked). Bundle for
0.9.0 (the study's alloys and the usual contaminants; a pure engineering pick): K1 for C, N, O, Mg, Al, Si; L1, L2, L3 for
Mg, Al, Si, Fe, Cu. Onsets from exSpy's `eels_binding_energies.json` (exact, `tests/misc/test_gos.py::test_binding_energy_database`).
`EdgeCrossSection` already integrates any subshell's table (`_integrate_GOS`, `function(E)` at rtol 5e-7, `test_eels_cl_edge.py`);
the only new rule is exSpy's twin: the subshells of one element share one intensity, the master is the lexicographically
last name (`L3` over `L2` over `L1`, `eelsmodel.py:283-327`), the others' onsets ride on the master's with the fixed
table difference.

```swift
public struct CoreLossEdge { public let element: String, subshell: String, onsetEV: Double; public static let bundled: [CoreLossEdge]
    public static func bundled(_ element: String, _ subshell: String) -> CoreLossEdge?; public var family: String /* "K", "L" */ }
```

### 6.2 Background fit, model fit, quantify

Reference: `EELSSpectrum.create_model(auto_background=True, auto_add_edges=True, GOS="dft")` (`eels.py:1628`), `EELSModel`
(`eelsmodel.py`): `_preedge_safe_window_width = 2` eV, `fit_background` (`:509-546`: range `[start, firstOnset - 2)`, edges
at or above it disabled), `two_area_background_estimation` (`:548-592`), `smart_fit` (`:444-480`: background, then edges one
by one over `[start, nextOnset - 2)`), `fit` = HyperSpy `Model1D.fit` (unbounded Levenberg-Marquardt, "ls" loss),
convolution with the low loss when given, `quantify` (`:673-697`: prints `intensity.value` per element, twins skipped).

```swift
public struct EELSModelOptions: Sendable, Equatable {
    public var startEnergyEV: Double? = nil             // exSpy start_energy; nil = axis start
    public var preEdgeSafeWindowEV: Double = 2          // _preedge_safe_window_width
    public var background: BackgroundModel = .powerLaw  // .powerLaw | .none (auto_background False)
    public var fitKind: EELSFitKind = .smart            // .smart (cascade) | .standard (all at once, from the two-area start)
    public var freeOnsetEnergy: Bool = false            // enable_free_onset_energy: not offered in 0.9.0; the field is reserved and refused if true
}
public struct EdgeIntensityPixel: Sendable, Equatable {
    public let intensity: Double?                       // exSpy's intensity.value (counts × barn⁻¹ scale); nil with `unavailable`
    public let arealDensityPerNM2: Double?              // n from intensity by the ratioMethod unit rule (1 barn = 1e-10 nm²); see the pin, section 8
    public let background: PowerLawParameters?; public let unavailable: EELSUnavailable?
}
public struct EELSModelResult: Sendable {
    public let edges: [CoreLossEdge]                    // masters only, in fit order
    public let pixels: [[EdgeIntensityPixel]]           // [pixel][edge]
    public let fitRangeEV: [ClosedRange<Double>]        // per edge, the smart-fit window used
    public let methodName: String; public let validation: String  // "none"
}
public enum EELSModelFit {
    public static func fit(coreLoss: CoreLossSpectrumImage, edges: [CoreLossEdge], microscope: EELSMicroscope, lowLoss: LowLossSpectrumImage? = nil,
        mask: PixelMask? = nil, options: EELSModelOptions = .init(), cancelled:..., progress:...) throws -> EELSModelResult
    public static func fitBackground(coreLoss:..., edges:..., options:...) throws -> [PowerLawParameters?]   // fit_background alone
    public static func twoAreaBackground(coreLoss:..., edges:..., startEnergyEV: Double? = nil) throws -> [PowerLawParameters?]
}
```

Solver: the model is linear in the edge intensities and `A` for a fixed `r`, so the kit solves `r` by a bounded 1-D
minimiser (Brent, `r ∈ [0, 10]`, start from the two-area estimate) with intensities and `A` by the existing
`LeastSquaresFit` (NNLS, variable projection) at each `r`. This is the EDX precedent (`LeastSquaresFit.swift` header:
HyperSpy's LM stops short of the minimum by 1e-4 relative) and is the `DEVIATION` to write inline. Low-loss convolution:
exSpy convolves each component with the raw low-loss counts over the model's convolution axis; port that convolution
(linear, `vDSP_convD`, axis as `set_convolution_axis`) and record the factor between exSpy's `intensity` and `n` on the
planted set before fixing `arealDensityPerNM2` (the pin script writes both numbers, section 8).

Tolerances: `test_eelsmodel.py::test_two_area_powerlaw_estimation_{BC,C,no_edge}` A and r at defaults (pinned numbers
2.1451237089380295 / 3.0118980767392736 and the two others); `test_fit_background_{B_C,C}` offset at defaults;
`test_quantify` exact intensity text; `test_eels_cl_edge.py` rtol 5e-7 for the component. For `fit` upstream states no
tolerance; kit decision: fitted intensities and `r` within rtol 1e-3 of exSpy's converged values on the planted set (the
LM shortfall is 1e-4), and within the counting-statistics sigma of the planted truth (`EdgeTruthTests` rule).

## 7. Reference functions and tolerances, one table

| kit function | reference (file:lines) | upstream test and tolerance |
|---|---|---|
| `alignZeroLossPeak` | exSpy `eels.py:318-483`; HyperSpy `shift1D :423`, `estimate_shift1D :626`, `align1D :738` | `test_eels.py::TestAlignZLP` defaults / eps / atol 1e-2; `test_1D_tools.py::TestAlignTools` atol 1e-3 (shift), defaults (data) |
| `zeroLossPeakCentre` | `eels.py:275-316` | `test_estimate_zero_loss_peak_centre` defaults |
| `zeroLossPeakMask` | `eels.py:485-511` | `test_get_zero_loss_peak_mask*` exact |
| `powerLawExtrapolation` | `eels.py:1236-1331`; `power_law.py` `estimate_parameters` | `TestPowerLawExtrapolation` atol 1e-2; `test_power_law.py` defaults |
| `hanningTaper` | `signal1d.py:1453-1531` | no numeric test; exact by construction |
| `fourierLog` | `eels.py:872-977`; `math_tools.py:148` | none upstream; kit: rtol 1e-7 + atol 1e-7·max, sizes exact |
| `fourierRatio` | `eels.py:979-1097`; `signal1d.py:1612` | `test_running` only; kit rule as above, FWHM roots 1e-9 eV |
| `richardsonLucy` | `eels.py:1099-1170` | none upstream; kit rule as above |
| `twoAreaBackground`, `fitBackground` | `eelsmodel.py:548-592`, `:509-546` | `test_two_area_powerlaw_estimation_*`, `test_fit_background_*` defaults |
| `EELSModelFit.fit` | `eelsmodel.py:444-480`, `:594-671`; `eels_cl_edge.py:441-497` | component rtol 5e-7; fit: none upstream, kit rtol 1e-3 + planted sigma |
| `CoreLossEdge` L tables | `gosh_gos.py` `read_gos_data`; `eels_binding_energies.json` | `test_gos.py::test_binding_energy_database` exact; tables bit for bit |

Pin environment: exSpy 0.3.2 and HyperSpy 2.4.0 from `References/python/bin/python -I -B` (Python 3.14,
NumPy 2.5.4, SciPy 1.18.1), the dft GOSH 1.5.0 file by md5 `7fee8891c147a4f769668403b54c529b`, as the existing scripts.

## 8. Pin scripts and fixtures (existing layout: `tools/<slice>/pins.py` writes `Tests/SpectroEELSTests/Fixtures/`)

| script | writes | holds |
|---|---|---|
| `tools/eels-align/make_planted.py` (NumPy only) | `align-planted.f64`, `align-planted.json` | 4×4×400 low loss, ZLP Gaussian FWHM 1.2 eV at planted shifts (−0.9…+1.3 eV, incl. the exact `TestAlignZLP` grid), background 2, a 20-count spike at channel 300, mask pixels [3, 5]; truth shifts |
| `tools/eels-align/pins.py` | `align-pins.json` | per option set (calibrate × subpixel × signal_range × crop × mask): zlpc before, shifts, new offset, kept channel range, aligned data (f64 sidecar), `get_zero_loss_peak_mask` for widths 2, 5, 10; `estimate_shift1D` raw |
| `tools/eels-deconv/make_planted.py` | `deconv-ssd.f64`, `deconv-zlp.f64`, `deconv-plural.f64`, `deconv-core.f64`, `.json` | planted single-scattering distribution, ZLP, plural spectrum = ZLP ⊛ exp(SSD) (Poisson series to order 6), core loss = SSD ⊛ edge; noiseless and `default_rng(20261021)` Poisson copies |
| `tools/eels-deconv/pins.py` | `deconv-pins.json` (+ `.f64` results) | `power_law_extrapolation` (20/100, 100/100, fix_neg_r), `hanning_taper` channels, `optimal_fft_size` for 1…5000 both rules, Fourier-log (add_zlp × crop), Fourier-ratio (fwhm given / estimated × extrapolate flags × threshold fixed / estimated) with `fftSize`, FWHM roots, I0; Richardson-Lucy 1, 5, 15 iterations |
| `tools/eels-edge/extract_gos.py --subshells` | `Resources/GOS/dft-<El>-<sub>.json` | the L tables, section 6.1 |
| `tools/eels-model/make_planted.py` | `model-core-*.f64`, `model-low-*.f64`, `model-planted.json`, `model-truth.json` | 3×5 pixels: power law × {3 backgrounds} with C K + O K (two K) and Fe L2,3 + O K (L twins) at planted n, low loss from `edge-low-ps07`; noiseless and noisy |
| `tools/eels-model/pins.py` | `model-pins.json` | `two_area_background_estimation` (A, r) incl. the three `test_eelsmodel` cases, `fit_background` range and parameters, `smart_fit` per pixel: every parameter, the fit range per edge, `quantify` text, and the intensity → n factor (exSpy `intensity`, I_low, σ per edge) |

Every script records versions, its own sha256 and the GOSH md5 (as `tools/eels-edge/pins.py` does), writes byte-identical
output on a second run, and gets a `README.md` with the run lines. The exSpy-internal truth (`test_eelsmodel` numbers)
is copied into the pin, not retyped in Swift.

## 9. `docs/parity.md` rows to move or add

Zero-loss peak section: `estimate_zero_loss_peak_centre` partial → present TOL (mask and `signal_range` now held);
`align_zero_loss_peak`, `get_zero_loss_peak_mask` missing → present TOL / exact; new rows for HyperSpy `shift1D`,
`estimate_shift1D`, `align1D` under "Shared numerics" (TOL; note the `max_shift` no-op). Deconvolution section:
`fourier_log_deconvolution`, `fourier_ratio_deconvolution`, `richardson_lucy_deconvolution`, `power_law_extrapolation`
missing → present TOL, tolerance column "none upstream; kit rtol 1e-7 + atol 1e-7·max (decision, design note eels-task-16
section 4)"; new rows `hanning_taper` (exact), `optimal_fft_size` (exact), `estimate_peak_width` (TOL). Model section:
`create_model` / `EELSModel` row splits into `two_area_background_estimation` (TOL defaults), `fit_background` (TOL
defaults), `smart_fit` / `fit` (DEV: variable projection + NNLS, rtol 1e-3, planted sigma), `quantify` (exact text
reproduced by a formatter test); `EELSCLEdge` L edges row → present for the bundled L elements, M and other K stay missing;
edges database row → partial with the new onsets. Summary table counts updated; "largest gaps" item 1 rewritten to what
remains (fine structure, Kramers-Kronig, hydrogenic/Dirac GOS, free onset energy).

## 10. Tests: fast target against parity target

`SpectroEELSTests` (fast, per session, must stay under a few seconds): refusals and shapes for every new error case;
hand-derived rules (`optimalFFTSize` against a list of 5-smooth numbers, Hanning window values, `next_fast_len` real vs
complex, twin master selection, `preEdgeSafeWindow`); planted truth tests (alignment recovers planted shifts within
0.5 channel coarse / atol 1e-3 eV subpixel; Fourier-log of the planted plural spectrum returns the SSD within noise;
model fit recovers planted n within the counting sigma); the `quantify` formatter against the exact text.

`SpectroKitParityTests` (before a tag and nightly, CI on push): one `*PinsTests` class per fixture (`AlignPinsTests`,
`DeconvPinsTests`, `ModelPinsTests`) comparing against exSpy's numbers at the section 7 tolerances; the `.f64` results
loaded through `SpectroTestSupport` (`FixtureDirs.fixtures(of: "SpectroEELSTests")`, a `DeconvFixtures.swift` beside
`EELSFixtures.swift`). Benchmarks (`tools/benchmarks/bench.py`, nightly): alignment and Fourier-ratio at 64×64×2048 against
exSpy, with the Python side timed in the same venv.

## 11. Performance: Accelerate, no Metal

Every path is per pixel on a 1-D axis of 1k to 4k channels: linear interpolation, one correlation, two FFTs and a
division, an NNLS of three to six columns. At the study's size (64×64×2048, 8 M values) that is tens of milliseconds
per step on the CPU in float64 with the pixel loop parallel over chunks (the pattern of `EDXQuantification.quantifyMaps`,
at most 8 threads). A Metal float32 path would spend its dispatch and copy on work smaller than the copy; D16's "where
size pays" does not hold for anything in this task, so no kernel, no `.metal` option, and the result records
`backend: "cpu"` only. Richardson-Lucy at 15 iterations is the heaviest (about 1 s at the study size); if a spectrum
image ten times larger arrives, the FFT-based convolution on the same plan is the first step, Metal the second. The FFT comes
from ImagoKit (`FFT2DDouble`, vDSP for 2^n × {1,3,5,15}, Bluestein for the other `next_fast_len` sizes); writing a second
Bluestein in SpectroKit was the alternative and is not worth a copy.

## 12. Decisions a reviewer should see

1. ImagoKit becomes a dependency of SpectroKit (FFT only). Reverse by vendoring the Bluestein plan; nothing else changes.
2. Deconvolution tolerance: rtol 1e-7 plus atol 1e-7 × max|result| where exSpy tests nothing numerically (D17 fallback
   with an atol, because allclose's atol 0 is unattainable across FFT libraries for near-zero channels).
3. The model fit is an exact minimiser (variable projection + NNLS), not HyperSpy's LM; pinned at rtol 1e-3, truth at
   the planted sigma. Same deviation as the EDX fit, same inline `DEVIATION` note.
4. Non-finite per-pixel outcomes are nil with a reason (`EELSUnavailable`), never NaN, as every EELS result today.
5. `max_shift` and `add_noise` are not offered (a no-op and a random draw in the reference).
6. Richardson-Lucy is designed but ordered last; the ROADMAP lists it out of scope, so skipping it is not a gap.
7. The bundled L edges (Mg, Al, Si, Fe, Cu) are an engineering pick for the study's alloys; a different list is a
   one-line change in `extract_gos.py` plus a resources commit.

Closeout for the implementing session (CLAUDE.md): fast target green per commit, full suite before the tag, `CHANGELOG.md`
0.9.0 entry with a Migration paragraph (new dependency, `CoreLossEdge.subshell` values beyond `K1`), `docs/parity.md`
rows per section 9, `docs/status.md` one line, open item 4 rewritten, hand-off paragraph in the last commit.
