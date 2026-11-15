/* SPDX-License-Identifier: MIT */
#ifndef K114S_KUNIT_HOST_MINMAX_H
#define K114S_KUNIT_HOST_MINMAX_H
#define min(a, b) ({ __typeof__(a) mh_a = (a); __typeof__(b) mh_b = (b); mh_a < mh_b ? mh_a : mh_b; })
#define max(a, b) ({ __typeof__(a) mh_a = (a); __typeof__(b) mh_b = (b); mh_a > mh_b ? mh_a : mh_b; })
#define min_t(t, a, b) min((t)(a), (t)(b))
#define max_t(t, a, b) max((t)(a), (t)(b))
#define clamp(v, lo, hi) min(max(v, lo), hi)
#define clamp_t(t, v, lo, hi) clamp((t)(v), (t)(lo), (t)(hi))
#endif
