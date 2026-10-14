import sys; sys.argv=[sys.argv[0]]
exec(open("probe4.py").read().split("\n"+"if __name__"+"==")[0])
for tail in (0.0,0.02):
  for rho in (0.0,0.002,0.01):
    mu=planted2(1e7,rho,widthlaw="fano",cont="real",tail=tail)
    def w(e,h): 
        f=fn_fwhm(e,130); m=(E>=e-h*f)&(E<e+h*f); return mu[m].sum()
    print("tail %.2f rho %.3f raw window sums +-1 FWHM: Mg/Al = %.4f   (Mg win %.0f, Al win %.0f)"%(tail,rho,w(1.2536,1)/w(1.4865,1),w(1.2536,1),w(1.4865,1)))
mu=planted2(1e7,0.0,widthlaw="fano",cont="real",cont_frac=0.03)
f=fn_fwhm(1.2536,130); m=(E>=1.2536-f)&(E<1.2536+f); f2=fn_fwhm(1.4865,130); m2=(E>=1.4865-f2)&(E<1.4865+f2)
print("cont_frac 0.03, rho 0: raw Mg/Al window ratio", mu[m].sum()/mu[m2].sum())
