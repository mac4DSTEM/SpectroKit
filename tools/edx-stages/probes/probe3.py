# NOT an oracle: a NumPy/SciPy surrogate of SpectroEDX's proposer test for ONE candidate (Mg) alone against {Al, Si},
# same design family (Kramers x Bernstein (9,5) split at 1.5596, F-N widths, table weights, unweighted NNLS, Currie L_D from the
# LS sandwich with the candidate absent, flank-misfit scaling). Used only to quote predictions for the registration.
import sys; sys.argv=[sys.argv[0]]
exec(open("probe1.py").read().split("\n"+"if __name__"+"==")[0])
from scipy.optimize import nnls
from math import comb
TAB={"Mg":[(1.2536,1.0),(1.305,0.01)],"Al":[(1.4865,1.0),(1.5596,0.0132)],"Si":[(1.7397,1.0),(1.8389,0.02779)]}
def fn_fwhm(e,R): return sqrt(2.5*(e-5.8987)*1000+R*R)/1000
def col(el,R,dE=0.0):
    c=np.zeros(NCH)
    for e,w in TAB[el]: c+=w*binint(e+dE,fn_fwhm(e,R))
    return c
def cont_cols(E0=200.0, lo=0.2, hi=20.0, edge=1.5596, orders=(9,5)):
    ch=np.where((E>=lo)&(E<=hi))[0]; cols=[]
    for s,(a,b,n) in enumerate(((lo,edge,orders[0]),(edge,hi,orders[1]))):
        idx=[i for i in ch if E[i]>=a and (E[i]<b if s==0 else E[i]<=b)]
        for k in range(n+1):
            c=np.zeros(NCH)
            for i in idx:
                t=(E[i]-a)/(b-a); c[i]=comb(n,k)*t**k*(1-t)**(n-k)*(E0-E[i])/E[i]
            cols.append(c)
    return cols,ch
CC,CH=cont_cols()
def surrogate(y, R=130.0, elements=("Al","Si"), cand="Mg", flank=True, dEmodel=0.0):
    cols=[col(el,R,dEmodel) for el in elements]+[col(cand,R,dEmodel)]+CC
    D=np.array(cols)[:,CH].T; yy=y[CH]
    nrm=np.linalg.norm(D,axis=0); Dn=D/nrm
    th,_=nnls(Dn,yy,maxiter=20000); mu=Dn@th
    ia=len(elements)
    net=th[ia]/nrm[ia]                         # area in counts (unit-area column)
    K=np.linalg.pinv(Dn)
    own=Dn[:,ia]*th[ia]
    v0=np.sum(K[ia]**2*np.maximum(mu-own,0))
    s0=sqrt(v0)
    if flank:
        e0=1.2536; f=fn_fwhm(e0,R); z2=[]
        for side in (-1,1):
            for b in range(5):
                a_=e0+side*(1.5+b)*f; c_=e0+side*(2.5+b)*f; lo,hi=min(a_,c_),max(a_,c_)
                m=(E[CH]>=lo)&(E[CH]<hi)
                if m.sum()>=3: z2.append(((yy-mu)[m].sum())**2/np.maximum(mu[m],1).sum())
        if len(z2)>=3: s0*=sqrt(max(1,np.mean(z2)))
    return net, 2.33*s0, 2.71+4.65*s0, s0
if __name__=="__main__":
    rng=np.random.default_rng(7)
    print("noise-free (expected counts as data): Mg net bias,  N_Al, rho, tail")
    for NAl in (3e5,1e6,1e7):
        for tail in (0.0,0.02):
            for rho in (0.0,0.002,0.01):
                mu,t=planted(NAl,rho,tail=tail)
                net,lc,ld,s0=surrogate(mu,flank=False)
                print("NAl %.0e tail %.2f rho %.3f  truth %8.0f  net %9.0f  bias %8.0f  sigma0(noise-free) %7.0f L_D %8.0f"%(NAl,tail,rho,NAl*rho,net,net-NAl*rho,s0,ld))
