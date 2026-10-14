import sys; sys.argv=[sys.argv[0]]
exec(open("probe4.py").read().split("\n"+"if __name__"+"==")[0])
def sur2(y,R=130.0):
    cols=[col(el,R) for el in ("Al","Si","Mg")]+CC
    D=np.array(cols)[:,CH].T; yy=y[CH]; nrm=np.linalg.norm(D,axis=0); Dn=D/nrm
    th,_=nnls(Dn,yy,maxiter=20000); mu=Dn@th; ia=2
    K=np.linalg.pinv(Dn); s0=sqrt(np.sum(K[ia]**2*np.maximum(mu-Dn[:,ia]*th[ia],0)))
    e0=1.2536; f=fn_fwhm(e0,R); z2=[]
    for side in (-1,1):
        for b in range(5):
            a_=e0+side*(1.5+b)*f; c_=e0+side*(2.5+b)*f; lo,hi=min(a_,c_),max(a_,c_)
            m=(E[CH]>=lo)&(E[CH]<hi)
            if m.sum()>=3: z2.append(((yy-mu)[m].sum())**2/np.maximum(mu[m],1).sum())
    mf=sqrt(max(1,np.mean(z2)))
    return th[ia]/nrm[ia], 2.71+4.65*s0, 2.71+4.65*s0*mf, mf
CF=0.03
rng=np.random.default_rng(3)
print("planted: Fano widths, realistic continuum, no tail, no axis error; model: F-N R=130, file axis. 20 Poisson seeds")
print(" N_Al   rho   truth   net_mean(sd)     L_D(no scaling)  L_D(flank-scaled)  misfit_f   P(net>=L_D scaled)  P(net>=L_D unscaled)")
for N in (1e5,1e6,1e7):
    for rho in (0.0,0.002,0.01,0.05):
        mu=planted2(N,rho,widthlaw="fano",cont="real",cont_frac=CF); r=[sur2(rng.poisson(mu).astype(float)) for _ in range(20)]
        r=np.array(r)
        print("%.0e %.3f %7.0f %9.0f(%5.0f) %10.0f %12.0f %11.2f %10.2f %14.2f"%(N,rho,N*rho,r[:,0].mean(),r[:,0].std(),r[:,1].mean(),r[:,2].mean(),r[:,3].mean(),(r[:,0]>=r[:,2]).mean(),(r[:,0]>=r[:,1]).mean()))
