//
//  CSpectroLAPACK.h
//  Plain-C wrappers over the Accelerate LAPACK routines SpectroCore calls: the four of `FitLinearAlgebra` (SpectroKit S3,
//  mac4DSTEM ADR 064 amendment a), `dgelsd_` (SciPy's least squares, for the Savitzky-Golay port) and `dgbsv_` (SciPy's
//  interpolating spline, EELS slice 2). This header includes no Accelerate: Swift sees only `int` and `double *`, so the
//  library needs neither `import Accelerate` nor the `-DACCELERATE_NEW_LAPACK` unsafe flag. The define lives in
//  lapack_shim.c, the only file that sees Accelerate's LAPACK declarations.
//
//  Each wrapper forwards its arguments unchanged to the routine of the same name (Fortran calling convention: every
//  argument by address) and returns LAPACK's `info`. `__LAPACK_int` is 32-bit `int` without ILP64; lapack_shim.c
//  asserts it at compile time, so the signatures are exact.
//

#ifndef CSPECTROLAPACK_H
#define CSPECTROLAPACK_H

/// `dgelsy_`: minimum-norm least squares by complete orthogonal factorisation with column pivoting.
int sk_dgelsy(int m, int n, int nrhs, double *a, int lda, double *b, int ldb, int *jpvt, double rcond, int *rank,
              double *work, int lwork);

/// `dgeqrf_`: QR factorisation (Householder reflectors below the diagonal, R on and above it).
int sk_dgeqrf(int m, int n, double *a, int lda, double *tau, double *work, int lwork);

/// `dorgqr_`: the explicit m x n Q from `dgeqrf_`'s first k reflectors.
int sk_dorgqr(int m, int n, int k, double *a, int lda, const double *tau, double *work, int lwork);

/// `dtrtri_`: inverse of a triangular matrix in place. `uplo` is 'U' or 'L', `diag` 'N' or 'U'.
int sk_dtrtri(char uplo, char diag, int n, double *a, int lda);

/// `dgelsd_`: minimum-norm least squares by the SVD (divide and conquer). SciPy's `scipy.linalg.lstsq` default driver.
/// `s` receives the singular values (min(m, n) of them); `iwork` is the integer workspace (`liwork` from LAPACK's formula).
int sk_dgelsd(int m, int n, int nrhs, double *a, int lda, double *b, int ldb, double *s, double rcond, int *rank,
              double *work, int lwork, int *iwork);

/// `dgbsv_`: solves a general banded system by LU with partial pivoting. `ab` in LAPACK band storage with `2 kl + ku + 1`
/// rows (the extra `kl` for fill-in), column-major; `b` is overwritten with the solution.
int sk_dgbsv(int n, int kl, int ku, int nrhs, double *ab, int ldab, int *ipiv, double *b, int ldb);

#endif
