import sys; sys.argv=[sys.argv[0]]
exec(open("probe4.py").read().split("\n"+"if __name__"+"==")[0])
def run(mu):
    return surrogate(mu,flank=False)[0]
N=1e7
print("noise-free, cont_frac 0.03, FN-matched widths (planted FN), N_Al 1e7: Mg net / truth vs small axis shifts and width scale")
for rho in (0.002,0.01):
    print(" rho",rho)
    for dE in (0.0,0.001,0.002,0.003,0.005):
        mu=planted2(N,rho,widthlaw="fn",cont="real",dE=dE,cont_frac=0.03); print("   shift %+d eV  ratio %.2f"%(dE*1000,run(mu)/(N*rho)))
    for sc in (1.01,1.02,1.04,1.06):
        # width scale on all lines: emulate by changing planted R so FN FWHM at Al scales ~sc: solve R
        lo,hi=100,200
        for _ in range(60):
            mid=(lo+hi)/2
            if fn_fwhm(1.4865,mid)<sc*fn_fwhm(1.4865,130): lo=mid
            else: hi=mid
        mu=planted2(N,rho,widthlaw="fn",cont="real",R=mid,cont_frac=0.03)
        print("   planted width at Al x%.2f (R=%.1f)  ratio %.2f"%(sc,mid,run(mu)/(N*rho)))
