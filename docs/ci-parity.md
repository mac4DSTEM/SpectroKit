# macos-26 parity investigation (0.5.2)

Run [38871127107](https://github.com/mac4DSTEM/SpectroKit/actions/runs/38871127107), commit `0653404`,
main job `116875206484`, Xcode 26.6 / Swift 6.3.3 / arm64 macOS 26. The full log is necessary:
`gh run view --log-failed` omits the test step because its pipeline returned `tee`'s exit status.
There are **120 unexpected issues in eight tests**, plus two registered known issues, rather than 122 failed tests.

Reproduce the measurements without running an oracle or rewriting a fixture:

```sh
gh run view 38871127107 --job 116875206484 --log -R mac4DSTEM/SpectroKit > .build/ci-main.log
python3 -I -B tools/ci-parity/gaps.py .build/ci-main.log > .build/ci-gaps.json
```

ULPs below count adjacent representable Doubles (ordered bits); relative error is `abs(actual-reference)/abs(reference)`.
The five golden outputs are pinned **Swift** baselines, not Python reference values. Other references are the existing
SciPy 1.18.1 / NumPy 2.5.4 / HyperSpy 2.4.0 / exSpy `7185a4d1` fixtures. No fixture was regenerated on the runner.

| Failing test | Issues | Measurable gap from existing log | Relative error | Interpretation |
|---|---:|---|---|---|
| `testOutputsAreByteIdenticalToTheBaseline` | 5 | 1–43 ulps at the five first differing lines | up to 8.661574206200392e-15 | Accelerate fit/covariance arithmetic; full differing arrays are not logged |
| `testCoefficientsAreBitIdenticalToSciPy` | 3 | noncentral coefficients up to 13 ulps; centre up to 11578856003771043 ulps | noncentral up to 1.7319479184152436e-15; centre 0.8291422401597813 | The mathematically zero centre changes from -8.308485920120681e-15 to -1.4195692919758177e-15; max absolute coefficient difference 1.9539925233402755e-14 |
| `testWholeDerivativeWithOwnCoefficientsIsBitIdentical` | 3 | unavailable: only mismatch indices logged (199/200, 195/200, 20/20) | unavailable | Need operand diagnostics on next owner run |
| `testWholeDerivativeIsBitIdenticalWithSciPysCoefficients` | 3 | unavailable: only mismatch indices logged (3/200, 4/200, 4/20) | unavailable | Only edge fits differ when the pinned coefficients are supplied |
| `testCoefficientsAndDerivativeAreBitIdenticalToSciPy` | 2 | unavailable: 1507 coefficient and 158772 derivative mismatches, operands absent | unavailable | Mismatch totals cannot determine ulp or relative error |
| `testEveryRefuterImageMatchesExSpyAtEveryPixel` | 28 | finite threshold pairs up to 4507487822963555 ulps; 4.5 eV | threshold up to 0.5003840070762412 | Eight additional finite reference thresholds become nil; I₀ 617 vs 643, t/λ 0.5533447187253107 vs 0.5120690183930791; real output differences |
| `testEstimatedThresholdPins` | 61 | threshold 2.5 vs 8.65 eV: 8247216817622221 ulps; derivative minima up to 4386506037058863104 ulps (including zero vs tiny residual) | threshold 0.7109826589595376; minima up to 15 | I₀ relative error up to 0.015805890033367184; t/λ absolute error up to 0.01593213515805436; cannot fix with a tolerance |
| `testAbsoluteThicknessPins` | 15 | absolute errors 0.001945244080907571–2.4311039098139418 nm; up to 71534958451813 ulps | up to 0.008042465090735171 | Reconstructed from logged absolute differences and named `pins.json` expectations; both possible signs give the same ULP distance in all 15 cases; downstream threshold error, do not loosen |

Five golden first differences:

| Scenario / field | ULPs | Relative error |
|---|---:|---:|
| demo-edx-tiny-dm4 / row 2 sigma | 1 | 1.1759343686702348e-16 |
| eds-realistic-l-sim / row 0 sigma | 43 | 8.661574206200392e-15 |
| eds-unlisted-sim / row 0 net | 1 | 2.1551218261689812e-16 |
| eds-proposer-sim / candidate 0 net | 2 | 2.287120657698457e-16 |
| eds-weakline-sim / row 0 sigma | 4 | 5.740275450939182e-16 |

## Backend constraint

The pinned SciPy wheel itself links Accelerate (checked with the pinned venv's `scipy.show_config()`, under
`../tools/memcap.sh`). The logged coefficient arrays show a CPU/toolchain-dependent small residual at a mathematically zero coefficient.
`ElasticThreshold` compares derivative magnitudes with an exact `<=`, then chooses a discrete channel. The observed tiny
coefficient differences can therefore produce large changes in thickness; the reduction to only edge mismatches when
pinned coefficients are supplied isolates the coefficient solve as the main suspected cause. A more accurate scalar solver alone does not
preserve the pinned solver's accidental tie choices. A reproducible backend needs an explicit decision about those ties;
fixture-specific coefficient lookup would hide the issue for untested windows and scales.
