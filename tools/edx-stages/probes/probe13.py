import sys, logging, warnings; logging.disable(logging.CRITICAL); warnings.simplefilter("ignore")
sys.path.insert(0,__import__("os").path.join(__import__("os").path.dirname(__import__("os").path.abspath(__file__)), "..", "..", "..", "References", "exspy-7185a4d1"))
import numpy as np, hyperspy.api as hs
f=sys.argv[1]
for sumdet in (True,False):
    try:
        out=hs.load(f, reader="EMD", sum_EDS_detectors=sumdet)
        print("sum_EDS_detectors",sumdet,[ (s.data.shape, int(s.data.sum())) for s in out if len(s.data.shape)==3 and s.data.shape[-1]>1000])
    except Exception as e: print("ERR",repr(e)[:200])
