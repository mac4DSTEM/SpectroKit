"""NumPy transcription of mac4DSTEM c809679c MaskTransport + PoolBuilder (GPL-3.0).
Not an exSpy oracle. Pixel clipping, tie policy and operation order follow the app.
Run with the pinned pymatgen venv's Python -I -B under suite tools/memcap.sh.
No downloads. Output deterministic; synthetic inputs are included in the fixture.
"""
from pathlib import Path
import json
import platform
import numpy as np
assert np.__version__ == '2.5.4'

def clip_area(poly, u, v):
    p=poly
    for axis,bound,greater in [(0,u-.5,True),(0,u+.5,False),(1,v-.5,True),(1,v+.5,False)]:
        out=[]
        for i,a in enumerate(p):
            b=p[(i+1)%len(p)]
            ia=a[axis]>=bound if greater else a[axis]<=bound
            ib=b[axis]>=bound if greater else b[axis]<=bound
            if ia: out.append(a)
            if ia!=ib:
                t=(bound-a[axis])/(b[axis]-a[axis])
                out.append((a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])))
        p=out
        if not p: return 0.
    s=0.
    for i,a in enumerate(p):
        b=p[(i+1)%len(p)]; s+=a[0]*b[1]-b[0]*a[1]
    return abs(s)/2

def pin(name,m,sw,sh,w,h,labels,classes):
    overlap=np.zeros((classes,w*h)); inside=np.zeros(w*h)
    total=np.zeros(classes); outside=np.zeros(classes)
    pixelArea=abs(m[0]*m[4]-m[1]*m[3])
    for y in range(sh):
        for x in range(sw):
            c=labels[y*sw+x]
            poly=[]
            for dx,dy in [(-.5,-.5),(.5,-.5),(.5,.5),(-.5,.5)]:
                px=x+dx; py=y+dy
                poly.append((m[0]*px+m[1]*py+m[2],m[3]*px+m[4]*py+m[5]))
            landed=0.
            # Same bounding box as Swift (extra zero-area pixels are harmless).
            u0=max(np.floor(min(p[0] for p in poly)+.5),0)
            u1=min(np.ceil(max(p[0] for p in poly)+.5),w-1)
            v0=max(np.floor(min(p[1] for p in poly)+.5),0)
            v1=min(np.ceil(max(p[1] for p in poly)+.5),h-1)
            for v in range(int(v0),int(v1)+1):
                for u in range(int(u0),int(u1)+1):
                    a=clip_area(poly,u,v)
                    if a<=0: continue
                    landed+=a; inside[v*w+u]+=a
                    if c>=0: overlap[c,v*w+u]+=a
            if c>=0:
                total[c]+=pixelArea; outside[c]+=max(pixelArea-landed,0)
    overlap=np.minimum(overlap,1); inside=np.minimum(inside,1)
    out=[-1]*(w*h); tied=[False]*(w*h)
    for p in range(w*h):
        best=-1; area=0.
        for c in range(classes):
            if overlap[c,p]>area+1e-6: best=c; area=overlap[c,p]
        if best<0 or area<.5-1e-6: continue
        rivals=[c for c in range(classes) if c!=best and overlap[c,p]>=area-1e-6]
        if rivals: tied[p]=True
        else: out[p]=best
    counts=np.arange(1,w*h*3+1,dtype=np.uint32).reshape(w*h,3)
    pools=[]
    reports=[]
    regions=[]
    for c in range(classes):
        mask=np.array(out)==c
        retained=sum(float(overlap[c,p]) for p in range(w*h) if mask[p])
        area=sum(float(a) for a in overlap[c]); n=int(sum(mask))
        independent=overlap[c]>=.5-1e-6
        ir=sum(float(overlap[c,p]) for p in range(w*h) if independent[p])
        ni=int(sum(independent))
        regions.append(dict(pixelsIncluded=ni,
                            partialIncluded=sum(bool(independent[p] and overlap[c,p]<1-1e-6) for p in range(w*h)),
                            edgeIncluded=sum(bool(independent[p] and inside[p]<1-1e-6) for p in range(w*h)),
                            touchedExcluded=sum(bool(not independent[p] and overlap[c,p]>1e-6) for p in range(w*h)),
                            regionArea=area,retainedFraction=ir/area if area>0 else 0.,
                            outsideFraction=float(outside[c]/total[c]) if total[c]>0 else 0.,
                            footprintArea=float(total[c]),purity=ir/ni if ni else 0.))
        pools.append(counts[mask].sum(axis=0,dtype=np.uint64).tolist())
        reports.append(dict(pixels=n,partial=sum(bool(mask[p] and overlap[c,p]<1-1e-6) for p in range(w*h)),
                            edge=sum(bool(mask[p] and inside[p]<1-1e-6) for p in range(w*h)),
                            outsideFraction=float(outside[c]/total[c]) if total[c]>0 else 0.,
                            footprintArea=float(total[c]),retainedFraction=retained/area if area>0 else 0.,
                            purity=retained/n if n else 0.))
    return dict(name=name,matrix=m,sw=sw,sh=sh,w=w,h=h,inputLabels=labels,classCount=classes,
                overlap=overlap.tolist(),inside=inside.tolist(),footprint=total.tolist(),outside=outside.tolist(),
                labels=out,tied=tied,counts=counts.flatten().tolist(),pools=pools,reports=reports,regions=regions)

cases=[]
def add(name,m,sw=3,sh=2,w=4,h=3,labels=[0,0,1,0,-1,1],classes=3):
    cases.append(pin(name,m,sw,sh,w,h,labels,classes))
add('identity',[1,0,0,0,1,0])
add('half-area-ties',[.5,0,.25,0,1,0],4,2,3,2,[0,1,1,0,1,0,0,1],2)
add('mirror',[-1,0,2,0,1,0])
add('rotation-shear',[.8,-.3,.1,.4,.9,-.2])
add('cropped',[1,0,-.7,0,1,.35])
add('far-away',[1,0,1e8,0,1,-1e8])
add('near-half-boundary',[.5,0,.2500001,0,1,0],4,2,3,2,[0,1,1,0,1,0,0,1],2)
add('empty-class',[1,0,0,0,1,0],2,1,2,1,[-1,-1],2)
add('shear-reflection',[-1.2,.23,2.4,.18,.77,-.1])
path=Path(__file__).resolve().parents[2]/'Tests/SpectroCoreTests/Fixtures/registration-pins.json'
path.write_text(json.dumps(dict(reference='NumPy transcription of mac4DSTEM c809679c',python=platform.python_version(),numpy=np.__version__,cases=cases),indent=2,sort_keys=True)+'\n')
print(f'{len(cases)} cases: {path}')
