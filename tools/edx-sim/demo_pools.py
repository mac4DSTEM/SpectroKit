"""Pooled spectra of the public synthetic AlMgSi demo set, with their planted truth, for `DemoEDXPoolTests`.

The demo set is mac4DSTEM's `demo-edx` (generator `tools/demo-edx/sim_edx.py` v2.0, seed 42, ladder seed 52). Its truth is the
simulation recipe, not a measurement. Read-only on the demo folder.

    python -I -B tools/edx-sim/demo_pools.py <demo-edx folder> Tests/SpectroEDXTests/Fixtures/edx-demo-pools.json

Needs numpy and h5py. Each pool: the Poisson counts summed over its pixels, the generator's noise-free expected spectrum of the
same pixels (`expected`, counts, 4 decimals), and the generator's planted component areas (`planted`, counts).
"""
import json
import sys

import h5py
import numpy as np

D = sys.argv[1].rstrip('/') + '/'
OUT = sys.argv[2]
T = json.load(open(D + 'truth_edx.json'))
TA = np.load(D + 'truth_edx_arrays.npz')
L = json.load(open(D + 'truth_edx_ladder.json'))
LA = np.load(D + 'truth_edx_ladder_arrays.npz')
comps = T['component_names']
kc = T['forward_model']['line_model']['true_k']['counts_per_atom_nm2_per_family_(Gp*s*eps)']
true_axis = dict(offset=-0.478, scale=0.005)
keys = ['Al_Ka', 'Mg_Ka', 'Si_Ka', 'Si_Ka_internal', 'O_Ka', 'Al_Ka_tail', 'Cu_Ka_stray', 'Cu_Ka']


def metals(af):
    m = {k: v for k, v in af.items() if k != 'O'}
    s = sum(m.values())
    return {k: round(100 * v / s, 10) for k, v in m.items()}


def spectrum(x):
    return [round(float(v), 4) for v in x]


pools = []
recipes_af = {k: v['atom_fraction_incl_oxide'] for k, v in T['recipes'].items()}
recipes_af['beta_pure'] = {'Mg': 5 / 11, 'Si': 6 / 11}

with h5py.File(D + 'AlMgSi_edx_ladder.hspy', 'r') as f:
    lad = f['Experiments/__unnamed__/data'][()]          # (16, 128, 4096)
for ri in (5, 6, 7):
    r = L['regions'][ri]
    c0, c1 = r['columns']
    block = lad[:, c0:c1 + 1, :].astype(np.int64)
    c = r['components_expected_total_counts']
    pools.append(dict(name='L%d_%s' % (ri, r['recipe']), source='ladder', npix=int(block.shape[0] * block.shape[1]),
                      thickness_nm=r['thickness_nm'], truth_at=metals(recipes_af[r['recipe']]), axis_true=true_axis,
                      counts=block.sum(axis=(0, 1)).tolist(), expected=spectrum(LA['expected_spectrum_sum_by_region'][ri]),
                      planted={k: round(float(c.get(k, 0.0)), 4) for k in keys}))

with h5py.File(D + 'AlMgSi_4D_EDX_EDS.hspy', 'r') as f:
    m = f['Experiments/__unnamed__/data'][()].astype(np.int64)   # (48, 64, 4096), the file axis carries a planted error
rm = np.array(T['recipe_map'])
order = T['recipe_names_in_map_order']
thick = TA['thickness_nm']
cexp = TA['component_expected_counts']
for name, idx in (('M_A', [0]), ('M_matrix', [0, 1, 2, 3, 4, 5, 6])):
    mask = np.isin(rm, idx)
    w = TA['expected_total_counts_per_pixel'][mask]
    pools.append(dict(name=name, source='map', npix=int(mask.sum()),
                      thickness_nm=round(float((thick[mask] * w).sum() / w.sum()), 6), truth_at=metals(recipes_af[order[idx[0]]]),
                      axis_true=true_axis, counts=m[mask].sum(axis=0).tolist(),
                      expected=spectrum(sum(TA['expected_spectrum_sum_by_recipe'][i] for i in idx)),
                      planted={k: round(float(cexp[comps.index(k)][mask].sum()), 4) for k in keys}))

out = dict(generator='mac4DSTEM demo-edx, tools/demo-edx/sim_edx.py v2.0 (seed 42, ladder seed 52); truth is the simulation recipe',
           true_k_counts_per_atom_nm2={k: kc[k + '_K'] for k in ('Al', 'Mg', 'Si')},
           atomic_mass={'Al': 26.9815, 'Mg': 24.305, 'Si': 28.0855}, pools=pools)
with open(OUT, 'w') as fh:
    json.dump(out, fh, separators=(',', ':'), sort_keys=True)
    fh.write('\n')
