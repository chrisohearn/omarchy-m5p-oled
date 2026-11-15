/* SPDX-License-Identifier: MIT */
/*
 * Host stand-in for <kunit/test.h>: just enough to compile and run a KUnit suite that tests
 * pure functions, as a user-space program. See ../../run-dcp-backlight-host.sh.
 * Evidence class of a run: emulator/replica. It is not KUnit and not the kernel build.
 */
#ifndef K114S_KUNIT_HOST_TEST_H
#define K114S_KUNIT_HOST_TEST_H
#include <setjmp.h>
#include <stdio.h>
#include <string.h>
#include <linux/types.h>

#ifndef ARRAY_SIZE
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#endif

struct kunit {
	const char *name;
	int failed;
	jmp_buf abort;
};

struct kunit_case {
	void (*run_case)(struct kunit *test);
	const char *name;
};

struct kunit_suite {
	const char *name;
	struct kunit_case *test_cases;
};

#define KUNIT_CASE(fn) { .run_case = fn, .name = #fn }

#define KUNIT_HOST_CHECK(test, cond, text, fatal) do {				\
	if (!(cond)) {								\
		(test)->failed++;						\
		printf("    # %s:%d: %s\n", __FILE__, __LINE__, text);		\
		if (fatal)							\
			longjmp((test)->abort, 1);				\
	}									\
} while (0)

#define KUNIT_HOST_CMP(test, a, op, b, fatal) do {				\
	__typeof__(a) kh_a = (a);						\
	__typeof__(b) kh_b = (b);						\
	_Pragma("GCC diagnostic push")						\
	_Pragma("GCC diagnostic ignored \"-Wsign-compare\"")			\
	KUNIT_HOST_CHECK(test, kh_a op kh_b, #a " " #op " " #b, fatal);	\
	_Pragma("GCC diagnostic pop")						\
} while (0)

#define KUNIT_EXPECT_EQ(test, a, b) KUNIT_HOST_CMP(test, a, ==, b, 0)
#define KUNIT_EXPECT_NE(test, a, b) KUNIT_HOST_CMP(test, a, !=, b, 0)
#define KUNIT_EXPECT_LT(test, a, b) KUNIT_HOST_CMP(test, a, <, b, 0)
#define KUNIT_EXPECT_LE(test, a, b) KUNIT_HOST_CMP(test, a, <=, b, 0)
#define KUNIT_EXPECT_GT(test, a, b) KUNIT_HOST_CMP(test, a, >, b, 0)
#define KUNIT_EXPECT_GE(test, a, b) KUNIT_HOST_CMP(test, a, >=, b, 0)
#define KUNIT_EXPECT_TRUE(test, c) KUNIT_HOST_CHECK(test, !!(c), #c " is true", 0)
#define KUNIT_EXPECT_FALSE(test, c) KUNIT_HOST_CHECK(test, !(c), #c " is false", 0)
#define KUNIT_ASSERT_EQ(test, a, b) KUNIT_HOST_CMP(test, a, ==, b, 1)
#define KUNIT_ASSERT_NE(test, a, b) KUNIT_HOST_CMP(test, a, !=, b, 1)
#define KUNIT_ASSERT_LT(test, a, b) KUNIT_HOST_CMP(test, a, <, b, 1)
#define KUNIT_ASSERT_LE(test, a, b) KUNIT_HOST_CMP(test, a, <=, b, 1)
#define KUNIT_ASSERT_GT(test, a, b) KUNIT_HOST_CMP(test, a, >, b, 1)
#define KUNIT_ASSERT_GE(test, a, b) KUNIT_HOST_CMP(test, a, >=, b, 1)
#define KUNIT_ASSERT_TRUE(test, c) KUNIT_HOST_CHECK(test, !!(c), #c " is true", 1)
#define KUNIT_ASSERT_FALSE(test, c) KUNIT_HOST_CHECK(test, !(c), #c " is false", 1)

static inline int kunit_host_run(struct kunit_suite *suite, const char *only)
{
	struct kunit_case *c;
	int ran = 0, failed = 0;

	for (c = suite->test_cases; c->run_case; c++) {
		struct kunit test = { .name = c->name };

		if (only && !strstr(c->name, only))
			continue;
		if (!setjmp(test.abort))
			c->run_case(&test);
		printf("%s %s\n", test.failed ? "not ok" : "ok", c->name);
		ran++;
		failed += !!test.failed;
	}
	printf("# %s: %d case(s), %d failed\n", suite->name, ran, failed);
	return failed || !ran;
}

#define kunit_test_suite(suite)							\
	int main(int argc, char **argv)						\
	{									\
		return kunit_host_run(&suite, argc > 1 ? argv[1] : NULL);	\
	}

#endif
