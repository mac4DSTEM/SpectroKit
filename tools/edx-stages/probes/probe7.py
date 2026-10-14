import sys; sys.argv=[sys.argv[0]]
exec(open("probe4.py").read().split("\n"+"if __name__"+"==")[0])
from exspy.utils.eds import get_xray_lines_near_energy
rng=np.random.default_rng(11)
def peaks(y, amp=None, med=5):
    s=hs.signals.Signal1D(y.astype(float)); ax=s.axes_manager.signal_axes[0]; ax.offset=OFF; ax.scale=SC; ax.units="keV"
    p=s.find_peaks1D_ohaver(amp_thresh=amp, medfilt_radius=med, peakgroup=10)[0]
    return [(round(float(a),4), round(float(h),1), round(float(w),4)) for a,h,w in zip(p["position"],p["height"],p["width"])] if len(p) else []
print("find_peaks1D_ohaver on planted Poisson spectra (Fano widths, realistic continuum), keV positions; Mg Ka true 1.2536, Al 1.4865, Si 1.7400")
for N in (1e5,1e6,1e7):
    for rho in (0.002,0.01,0.05):
        y=rng.poisson(planted2(N,rho,widthlaw="fano",cont="real")); 
        pk_def=[p for p in peaks(y) if 0.8<p[0]<2.5]
        for amp in (None,):
            pass
        pk_lo=[p for p in peaks(y,amp=0.002*y.max(), med=3) if 0.8<p[0]<2.5]
        print(f"N_Al {N:.0e} rho {rho}: default(10% max) {pk_def}\n        amp 0.2% max, medfilt 3: {pk_lo}")
print(get_xray_lines_near_energy(1.2536,width=0.2), get_xray_lines_near_energy(1.4865,width=0.2,only_lines=["a"]))
