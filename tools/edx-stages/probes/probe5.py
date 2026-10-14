import sys; sys.argv=[sys.argv[0]]
exec(open("probe4.py").read().split("\n"+"if __name__"+"==")[0])
def surrogate_w(y, R=130.0, dE=0.0, weighted=False):
    elements=("Al","Si"); cols=[col(el,R,dE) for el in elements]+[col("Mg",R,dE)]+CC
    D=np.array(cols)[:,CH].T; yy=y[CH]
    nrm=np.linalg.norm(D,axis=0); Dn=D/nrm
    th,_=nnls(Dn,yy,maxiter=20000)
    if weighted:
        for _ in range(3):
            mu=Dn@th; w=1/np.sqrt(np.maximum(mu,1)); th,_=nnls(Dn*w[:,None],yy*w,maxiter=20000)
    rss=np.sum((yy-Dn@th)**2)
    return th[2]/nrm[2], rss
N=1e7
for rho in (0.002,0.01):
    mu=planted2(N,rho,widthlaw="fano",cont="real")
    print("rho",rho,"truth",N*rho)
    for R in (120,125,130,135,138,140,142,145,150):
        a,rss=surrogate_w(mu,R=R); b,rssw=surrogate_w(mu,R=R,weighted=True)
        print("  model R_MnKa %3d  LS net %8.0f (rss %.3e)   iter-WLS net %8.0f"%(R,a,rss,b))
    print(" ", "FN FWHM at Al for R=130,138,142:",[round(fn_fwhm(1.4865,r)*1000,1) for r in (130,138,142)],"planted Fano at Al:",round(fwhm_fano(1.4865,130)*1000,1))
