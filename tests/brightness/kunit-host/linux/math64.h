/* SPDX-License-Identifier: MIT */
#ifndef K114S_KUNIT_HOST_MATH64_H
#define K114S_KUNIT_HOST_MATH64_H
#include <linux/types.h>
static inline u64 div_u64(u64 dividend, u32 divisor) { return dividend / divisor; }
static inline u64 div64_u64(u64 dividend, u64 divisor) { return dividend / divisor; }
static inline u64 mul_u32_u32(u32 a, u32 b) { return (u64)a * b; }
static inline u64 mul_u64_u64_shr(u64 a, u64 b, unsigned int shift)
{
	return (u64)(((unsigned __int128)a * b) >> shift);
}
#endif
