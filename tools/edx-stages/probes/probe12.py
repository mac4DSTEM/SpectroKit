import sys, logging, warnings; logging.disable(logging.CRITICAL); warnings.simplefilter("ignore")
sys.path.insert(0,__import__("os").path.join(__import__("os").path.dirname(__import__("os").path.abspath(__file__)), "..", "..", "..", "References", "exspy-7185a4d1"))
import numpy as np, hyperspy.api as hs
R=__import__("os").path.normpath(__import__("os").path.join(__import__("os").path.dirname(__import__("os").path.abspath(__file__)), "..", "..", ".."))
try:
    out=hs.load(R+"Tests/SpectroCoreTests/Fixtures/velox-tiny.emd", reader="EMD")
    for s in out: print(s.metadata.Signal.signal_type if "Signal" in s.metadata else None, s.data.shape, s.data.dtype, int(s.data.sum()))
except Exception as e: print("ERR",repr(e)[:300])
