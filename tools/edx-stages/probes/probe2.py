import sys; sys.argv=[sys.argv[0]]
exec(open("probe1.py").read().split("\n"+"if __name__"+"==")[0])
import numpy as np, itertools, json
rng=np.random.default_rng(20261016)
def run(NAl, rho, tail, nrep=200, R_mn=130.0, dE=0.0, lines=("Al_Ka","Mg_Ka","Si_Ka"), merge=True):
    mu,truth=planted(NAl,rho,tail=tail,R_mn=R_mn,dE=dE)
    data=rng.poisson(mu, size=(nrep,NCH)).astype(float)
    s=EDSTEMSpectrum(data)
    ax=s.axes_manager.signal_axes[0]; ax.offset=OFF; ax.scale=SC; ax.units="keV"
    s.set_microscope_parameters(beam_energy=200.0, energy_resolution_MnKa=R_mn)
    s.set_elements([l.split("_")[0] for l in lines]); s.set_lines(list(lines))
    xl=list(s._get_xray_lines())
    if merge: bw=s.estimate_background_windows(xray_lines=xl)
    else:
        bw=np.vstack([s.estimate_background_windows(xray_lines=[x])[0] for x in xl])
    I=s.get_lines_intensity(xray_lines=xl, background_windows=bw)
    out={x:np.array(i.data).ravel() for x,i in zip(xl,I)}
    # window geometry for the Currie bar
    iw=s.estimate_integration_windows(2.0, xray_lines=xl)
    info={}
    for j,x in enumerate(xl):
        w=iw[j]; b=bw[j]
        i0,i1=ax.value2index(w[0]),ax.value2index(w[1])
        # chans as exSpy slices: isig[a:b] -> [index(a), index(b))
        info[x]=(i1-i0, (ax.value2index(b[1])-ax.value2index(b[0]))+(ax.value2index(b[3])-ax.value2index(b[2])))
    return out, info, truth
if __name__=="__main__":
    # truth: Mg window share (areas of Ka+Kb falling in the exSpy window) is computed separately; here net vs planted Mg area
    rows=[]
    for NAl in (1e4,1e5,1e6,1e7):
        for tail in (0.0,0.02):
            for rho in (0,0.001,0.002,0.005,0.01,0.02,0.05):
                out,info,truth=run(NAl,rho,tail)
                m=out["Mg_Ka"]; n=NAl*rho
                rows.append((NAl,tail,rho,n,m.mean(),m.std(ddof=1)))
    print("NAl tail rho Mg_true  net_mean  net_sd  (exSpy windows, 200 realisations)")
    for r in rows: print("%8.0e %.2f %.3f %9.0f %10.1f %8.1f"%r)
