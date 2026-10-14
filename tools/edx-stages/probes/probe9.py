import sys; sys.argv=[sys.argv[0]]
exec(open("probe1.py").read().split("\n"+"if __name__"+"==")[0])
rng=np.random.default_rng(2)
d=rng.poisson(0.5,size=(4,5,64)).astype(np.uint16); d[0,0,3]=65535; d[1,1,3]=65535
s=EDSTEMSpectrum(d); s.set_microscope_parameters(beam_energy=200.,live_time=2.0,energy_resolution_MnKa=130.)
t=s.sum(); print("nav-sum dtype",t.data.dtype,"equal to numpy uint64 sum:",np.array_equal(t.data,d.sum(axis=(0,1),dtype=np.uint64)),"max",t.data.max(),"live_time",t.metadata.Acquisition_instrument.TEM.Detector.EDS.live_time)
print("numpy default sum dtype of uint16:",d.sum(axis=(0,1)).dtype)
