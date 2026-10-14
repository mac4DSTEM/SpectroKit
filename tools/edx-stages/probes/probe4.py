import sys; sys.argv=[sys.argv[0]]
exec(open("probe3.py").read().split("\n"+"if __name__"+"==")[0])
def planted2(NAl, rho, widthlaw="fano", cont="real", tail=0.0, dE=0.0, R=130.0, rho_si=0.01, cont_frac=0.3):
    wf = (lambda e: fwhm_fano(e,R)) if widthlaw=="fano" else (lambda e: fn_fwhm(e,R))
    mu=np.zeros(NCH)
    for el,N in (("Al",NAl),("Mg",NAl*rho),("Si",NAl*rho_si)):
        tot=sum(w for _,w in LINES[el])
        for e,w in LINES[el]:
            area=N*w/tot; g=binint(e+dE,wf(e)); mu+=area*g
            if tail>0 and el=="Al" and w==1.0:
                sh=np.where(E<e+dE,np.exp((E-(e+dE))/0.15),0.0); sh/=sh.sum(); mu+=area*tail*(sh-g)
    en=np.clip(E,1e-3,None)
    c=np.where((E>0.15)&(E<200),(200-en)/en*(1-np.exp(-(en/0.30)**2.5)),0.0)
    c*=cont_frac*NAl/c[(E>0.2)&(E<20)].sum()
    if cont=="family":
        D=np.array(CC)[:,CH].T; nr=np.linalg.norm(D,axis=0); th,_=nnls(D/nr,c[CH]); cf=np.zeros(NCH); cf[CH]=(D/nr)@th; c=cf
    return mu+c
def row(label, NAl, rho, **kw):
    mu=planted2(NAl,rho,**kw); net,lc,ld,s0=surrogate(mu,flank=False)
    print("%-44s N_Al %.0e rho %.3f truth %8.0f net %9.0f (%+.0f%%)  s0 %6.0f L_D %7.0f"%(label,NAl,rho,NAl*rho,net,100*(net/(NAl*rho)-1),s0,ld))
if __name__=="__main__":
    for N,rho in ((1e6,0.01),(1e7,0.01),(1e7,0.002)):
        row("A  FN widths, in-family continuum",N,rho,widthlaw="fn",cont="family")
        row("B  FN widths, realistic continuum",N,rho,widthlaw="fn",cont="real")
        row("C  Fano widths(+8%), in-family continuum",N,rho,widthlaw="fano",cont="family")
        row("D  Fano widths, realistic continuum",N,rho,widthlaw="fano",cont="real")
        for dE in (0.005,0.010,-0.010): row("E  FN, in-family, axis shift %+.0f eV"%(dE*1000),N,rho,widthlaw="fn",cont="family",dE=dE)
        row("F  FN, in-family, Al tail 2 %%",N,rho,widthlaw="fn",cont="family",tail=0.02)
        print()
