/* SPDX-License-Identifier: MIT */
#ifndef K114S_KUNIT_HOST_LIMITS_H
#define K114S_KUNIT_HOST_LIMITS_H
#include <limits.h>
#include <linux/types.h>
#define U8_MAX ((u8)~0U)
#define U16_MAX ((u16)~0U)
#define U32_MAX ((u32)~0U)
#define S32_MAX ((s32)(U32_MAX >> 1))
#define U64_MAX ((u64)~0ULL)
#define S64_MAX ((s64)(U64_MAX >> 1))
#endif
