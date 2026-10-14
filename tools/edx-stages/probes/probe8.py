import sys; sys.argv=[sys.argv[0]]
exec(open("probe4.py").read().split("\n"+"if __name__"+"==")[0])
rng=np.random.default_rng(5)
res=[]
for dE in (0.0,0.008,-0.012):
    for R in (130.0,):
        y=rng.poisson(planted2(1e6,0.05,widthlaw="fano",cont="real",dE=dE)).astype(float)
        s=make_spec(y,R)
        s.set_elements(["Mg","Al","Si"]); s.set_lines(["Mg_Ka","Al_Ka","Si_Ka"])
        s.crop(-1, None) if False else None
        s=s.isig[0.3:3.0]
        m=s.create_model(auto_background=True,auto_add_lines=True)
        off0=s.axes_manager.signal_axes[0].offset; 
        m.fit(); 
        try:
            m.calibrate_energy_axis("offset",xray_lines=["Mg_Ka","Al_Ka","Si_Ka"])
            off1=s.axes_manager.signal_axes[0].offset
            print("planted line shift %+.0f eV: exSpy calibrate_energy_axis('offset') changed offset %.5f -> %.5f keV (delta %+.1f eV)"%(dE*1000,off0,off1,(off1-off0)*1000))
        except Exception as e: print("dE",dE,"error",repr(e)[:200])
