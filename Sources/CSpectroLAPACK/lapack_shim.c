//
//  lapack_shim.c
//  The only file that sees Accelerate's LAPACK: the current (non-deprecated) `__LAPACK_int` interface, selected by
//  ACCELERATE_NEW_LAPACK. The define comes from the target's `cSettings` (Package.swift), not from a `#define` here: with
//  clang modules Accelerate is a precompiled module, built from the target's command-line macros, so a `#define` before the
//  `#include` is not seen by it (tried in S3: `__LAPACK_int` undeclared, the deprecated CLAPACK prototypes instead).
//  See CSpectroLAPACK.h.
//

#ifndef ACCELERATE_NEW_LAPACK
#error "CSpectroLAPACK needs ACCELERATE_NEW_LAPACK from its cSettings"
#endif
#include <Accelerate/Accelerate.h>
#include "CSpectroLAPACK.h"

_Static_assert(sizeof(__LAPACK_int) == sizeof(int), "CSpectroLAPACK assumes LP64 LAPACK (32-bit __LAPACK_int), not ILP64");

int sk_dgelsy(int m, int n, int nrhs, double *a, int lda, double *b, int ldb, int *jpvt, double rcond, int *rank,
              double *work, int lwork) {
    int info = 0;
    dgelsy_(&m, &n, &nrhs, a, &lda, b, &ldb, jpvt, &rcond, rank, work, &lwork, &info);
    return info;
}

int sk_dgeqrf(int m, int n, double *a, int lda, double *tau, double *work, int lwork) {
    int info = 0;
    dgeqrf_(&m, &n, a, &lda, tau, work, &lwork, &info);
    return info;
}

int sk_dorgqr(int m, int n, int k, double *a, int lda, const double *tau, double *work, int lwork) {
    int info = 0;
    dorgqr_(&m, &n, &k, a, &lda, tau, work, &lwork, &info);
    return info;
}

int sk_dtrtri(char uplo, char diag, int n, double *a, int lda) {
    int info = 0;
    dtrtri_(&uplo, &diag, &n, a, &lda, &info);
    return info;
}

int sk_dgelsd(int m, int n, int nrhs, double *a, int lda, double *b, int ldb, double *s, double rcond, int *rank,
              double *work, int lwork, int *iwork) {
    int info = 0;
    dgelsd_(&m, &n, &nrhs, a, &lda, b, &ldb, s, &rcond, rank, work, &lwork, iwork, &info);
    return info;
}

int sk_dgbsv(int n, int kl, int ku, int nrhs, double *ab, int ldab, int *ipiv, double *b, int ldb) {
    int info = 0;
    dgbsv_(&n, &kl, &ku, &nrhs, ab, &ldab, ipiv, b, &ldb, &info);
    return info;
}
