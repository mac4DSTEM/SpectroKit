#!/bin/zsh
# setup.sh: the Python reference every tools/*/ script runs in, and the upstream sources they read, under References/ (gitignored).
# Safe to re-run: what exists and checks out is kept.
#
#   tools/reference/setup.sh            venv References/python from requirements.txt, plus the checkouts and GOSH files below
#   PY=python3.14 tools/reference/setup.sh   the interpreter for the venv (default: python3.14; 3.13 or later is needed for math.fma)
#
# Then run any generator from the repo root as  References/python/bin/python -I -B tools/<dir>/<script>.py
# Scripts that need exSpy at commit 7185a4d1 rather than the 0.3.2 wheel take --exspy References/exspy-7185a4d1 (their default)
# or say PYTHONPATH=References/exspy-7185a4d1 in their header.
set -eu
repo="${0:A:h:h:h}"
refs="$repo/References"
PY="${PY:-$(command -v python3.14 || true)}"
[[ -n $PY ]] || { print -u2 "setup.sh: no python3.14 on PATH; set PY=/path/to/python3.13-or-later"; exit 1; }
mkdir -p "$refs"

# The venv.
venv="$refs/python"
if [[ ! -x $venv/bin/python ]]; then
  print "== venv $venv ($($PY -V))"
  "$PY" -m venv "$venv"
  "$venv/bin/python" -m pip install -q --upgrade pip
fi
"$venv/bin/python" -m pip install -q -r "$repo/tools/reference/requirements.txt"
print "== venv: $("$venv/bin/python" -c 'import numpy, scipy, hyperspy, exspy, skimage; print("numpy", numpy.__version__, "scipy", scipy.__version__, "hyperspy", hyperspy.__version__, "exspy", exspy.__version__, "skimage", skimage.__version__)')"

# Git checkouts at the commits the pins name.
checkout() {   # dir url commit
  local dir="$refs/$1"
  if [[ ! -d $dir/.git ]]; then
    print "== clone $2 into References/$1"
    git clone -q --filter=blob:none "$2" "$dir"
  fi
  git -C "$dir" checkout -q "$3" 2>/dev/null || { git -C "$dir" fetch -q origin "$3" && git -C "$dir" checkout -q "$3"; }
  print "== References/$1 at $(git -C "$dir" rev-parse --short=8 HEAD)"
}
checkout exspy-7185a4d1  https://github.com/hyperspy/exspy.git            7185a4d13d7d5c550b7bb8d1e9bd62af9cc4203e
checkout pyEELSMODEL-pin https://github.com/joverbee/pyEELSMODEL.git      eed9f0721d5b47788c00c8f81509f0e3006df6f4
checkout rosettasciio    https://github.com/hyperspy/rosettasciio.git     049e7d7070e84779b499adaf3295beee9facb004

# The GOSH files exSpy fetches with pooch, md5 checked; pyEELSMODEL reads the dft file from a directory.
fetch() {   # file url md5
  local f="$refs/$1"
  if [[ ! -f $f || $(md5 -q "$f") != "$3" ]]; then
    print "== download $2"
    curl -fsSL -o "$f.part" "$2" && mv "$f.part" "$f"
  fi
  [[ $(md5 -q "$f") == "$3" ]] || { print -u2 "setup.sh: $1 md5 is not $3"; exit 1; }
  print "== References/$1 md5 ok"
}
fetch gos-dft-1.5.0.gosh https://zenodo.org/records/7645765/files/Segger_Guzzinati_Kohl_1.5.0.gosh 7fee8891c147a4f769668403b54c529b
fetch gos-dirac.gosh     https://zenodo.org/records/12800856/files/Dirac_GOS_compact.gosh          01a855d3750d2c063955248358dbee8d
mkdir -p "$refs/gosh-dir"
[[ -e $refs/gosh-dir/Segger_Guzzinati_Kohl_1.5.0.gosh ]] || cp "$refs/gos-dft-1.5.0.gosh" "$refs/gosh-dir/Segger_Guzzinati_Kohl_1.5.0.gosh"
print "done: $refs"
