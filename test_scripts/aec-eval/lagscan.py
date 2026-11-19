import sys, numpy as np, soundfile as sf
from scipy.signal import correlate
SR=16000
base=sys.argv[1]
mic,_=sf.read(base+".mic.wav",dtype="float32"); ref,_=sf.read(base+".system.wav",dtype="float32")
n=min(len(mic),len(ref)); mic=mic[:n]; ref=ref[:n]
def db(x): return 10*np.log10(np.mean(x.astype(np.float64)**2)+1e-12)
for start in range(0,int(n/SR)-20,20):
    a=mic[start*SR:(start+20)*SR].astype(np.float64); b=ref[start*SR:(start+20)*SR].astype(np.float64)
    c=correlate(a-a.mean(),b-b.mean(),mode="full"); mid=len(b)-1; m=3*SR
    w=c[mid-m:mid+m+1]; k=int(np.argmax(np.abs(w)))
    print(f"t={start:4d}s mic {db(a):6.1f} sys {db(b):6.1f}  lag {(k-m)*1000/SR:+7.0f} ms  corr {abs(w[k])/(np.linalg.norm(a)*np.linalg.norm(b)+1e-12):.3f}")
