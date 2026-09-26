#!/usr/bin/env python3
# RMS of jt12 (after system.sv's x22.25) vs Nuked adapter output, per test case.
import sys, math, collections
for fn in sys.argv[1:]:
    d = collections.defaultdict(list)
    for ln in open(fn):
        c, jl, nl, jr, nr = map(int, ln.split())
        d[c].append((jl, nl))
    print(fn)
    for c in sorted(d):
        v = d[c]
        def rms(k):
            m = sum(x[k] for x in v) / len(v)
            return math.sqrt(sum((x[k]-m)**2 for x in v) / len(v)), m
        (rj, mj), (rn, mn) = rms(0), rms(1)
        pj = max(abs(x[0]) for x in v); pn = max(abs(x[1]) for x in v)
        def zc(k, m):
            return sum(1 for a, b in zip(v, v[1:]) if (a[k]-m) < 0 <= (b[k]-m))
        zj, zn = zc(0, mj), zc(1, mn)
        print(f"  case {c}: zero-crossings jt12={zj} nuked={zn}")
        print(f"  case {c}: n={len(v)} jt12 rms={rj:8.1f} peak={pj:6d} dc={mj:8.1f} | nuked rms={rn:7.1f} peak={pn:6d} dc={mn:7.1f} | ratio jt/nk={rj/max(rn,1e-9):6.3f} ({20*math.log10(max(rj,1e-9)/max(rn,1e-9)):+.2f} dB)")
