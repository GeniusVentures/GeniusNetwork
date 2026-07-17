# Deferred Items — Phase 01 (child-balance-query)

## child_registration_test: SegFault on process teardown (pre-existing, out of scope)

**Discovered during:** Plan 01-02, Task 2 (build/run verification)

**Symptom:** After all `TEST_F` cases in `child_registration_test.exe` complete and report
`[ PASSED ]` (zero assertion failures), the process crashes with a segmentation fault during
global teardown / static destruction — after `Global test environment tear-down` prints but
before the process exits. `ctest -R child_registration_test` reports this as `SegFault` and
marks the overall test run as failed, even though every individual `TEST_F` case passed.

**Reproduced independent of Plan 01-02's changes:** Confirmed by running only the 3
pre-existing `TEST_F` cases (`ChildRegistersWithMain`, `MainDiscoversChild`,
`InvalidRegistrationRejected`) via `--gtest_filter`, excluding the new
`MainQueriesChildBalance` case entirely — the same segfault-on-exit (exit code 139) occurs.
This proves the crash is **not** caused by this plan's new test or by `GetChildBalance`
(Plan 01-01); it is a pre-existing lifecycle/teardown issue in the shared 3-node fixture
(`SetUpTestSuite`/`TearDownTestSuite`) or in a lower-level component (likely libp2p/boost::asio
io_context threads, GossipPubSub, or a background thread pool not fully joined before process
exit).

**Scope decision:** Out of scope for Plan 01-02 (test-file-only plan, `child_registration.cpp`
is the sole file_modified). Root-causing this would require touching production lifecycle code
outside this plan's file scope — potentially an architectural change (Rule 4) rather than a
simple bug fix. Deferred for a future phase/plan focused on test-infra or node-shutdown hygiene.

**Impact on this plan's verification:** All 4 `TEST_F` cases (including the new
`MainQueriesChildBalance`) pass at the GTest assertion level — INTG-01, BALT-01, and ROADMAP
Phase 1 Success Criteria 1-3 are all satisfied. The segfault is a process-exit artifact, not a
test-logic or product-code failure. CI/ctest consumers of this target should be aware that a
"failed" ctest result for `child_registration_test` may reflect this known teardown crash
rather than an actual test regression — check the captured GTest output for
`[ PASSED ] 4 tests.` before concluding failure.

**Suggested follow-up:** A future plan should investigate `TearDownTestSuite`'s
`child_node_.reset(); main_node_.reset(); genesis_node_.reset();` sequence and the shutdown
order of `GeniusNode`'s owned components (PubSub/libp2p io_context, TransactionManager,
ProcessingService) for a thread-join-before-destruction ordering bug.
