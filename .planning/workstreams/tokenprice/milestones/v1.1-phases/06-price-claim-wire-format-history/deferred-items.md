# Deferred Items — Phase 06 (tokenprice)

## Out-of-scope discoveries (not fixed per executor scope boundary)

- **[2026-10-05, Plan 06-01 Task 1]** `LocalPriceManagerTest.ConcurrentGetQuotesAcrossThreadsAllResolve` (SuperGenius/test/src/price_manager/price_manager_test.cpp) is flaky under full-binary runs on this Windows host: ~2 failures in 8 full-suite runs, 0 failures in 9 isolated `--gtest_filter=*ConcurrentGetQuotes*` runs. Failure body: one of the 8 caller threads' `GetQuotes` returns `false`. Unrelated to the 06-01 history change (that test uses synthetic non-genius-ai ids `id-0..id-7`, which `RecordObservations` filters out with a string compare; no control-flow change on that path). Suspect: thread-start scheduling on the loaded host. Recommend dedicated flake investigation (repeated-run harness) outside this plan.
- **[2026-10-05, Plan 06-01 close-out]** `genius_node` target fails to compile on this host at `src/account/GeniusNode.cpp:2307` (`C2039: '__this': is not a member of 'sgns::GeniusNode'`, UPnP `OpenPort` block). Pre-existing: the file was last modified by merge `f44199411` (2026-10-05, before this plan's base `60ecfae`→ plan diff touches only coinprices + its test); the failing line is in code this plan never edited. LocalPriceManager ctor call-site compatibility (`GeniusNode.cpp:3545`) is separately proven by the price_manager_test binary compiling and running the fully-defaulted 2-arg construction path. Out of scope for 06-01; flag for the 06-02 executor / build owner.
  status: acknowledged

## 06-02 executor (2026-10-05)

- processing_multi_test.cpp (~291, ~361) still calls GetProcessCost with a std::string and lacks .minions: never built (registered in no CMakeLists) and already uncompilable before this plan. Fix only if the target is ever revived.
- Repo-wide GetProcessCost grep residual hits are prose in GeniusSDK/.planning docs (CONCERNS.md:205, 02-REVIEW.md:147), not code.
- SetPayoutAddress hermetic pricing now goes through the loopback stub (~33s vs instant cache seed); acceptable within its 300s timeout.
  status: acknowledged
