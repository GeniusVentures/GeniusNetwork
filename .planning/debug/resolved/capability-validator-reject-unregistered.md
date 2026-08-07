---
status: resolved
trigger: "CapabilityValidatorTest.RejectUnregisteredPassType fails in SGProcessingManager."
created: 2026-08-07T02:04:54.000Z
updated: 2026-08-07T03:32:05.000Z
---

## Current Focus

hypothesis: CONFIRMED — test asserts a stale numeric assumption about PassType::INFERENCE's underlying int value that no longer matches the current (alphabetically quicktype-generated) PassType enum, and the implementation's rejection message never embeds the human-readable name, so neither disjunct of the OR-assertion can be satisfied.
test: Ran capability_validator_test.exe directly with --gtest_filter, and traced CanExecute()'s message construction against the generated PassType enum values.
expecting: N/A — root cause confirmed, this is a find_root_cause_only session.
next_action: Return ROOT CAUSE FOUND to caller. No fix applied (out of scope for this session).

reasoning_checkpoint:
  hypothesis: "CapabilityValidatorTest.RejectUnregisteredPassType (capability_validator_test.cpp:126-127) asserts result.unmet[0].detail contains 'INFERENCE' OR '1', assuming PassType::INFERENCE == 1. The actual generated PassType enum (COMPUTE=0, DATA_TRANSFORM=1, INFERENCE=2, RENDER=3, RETRAIN=4) makes PassType::INFERENCE == 2, and CapabilityValidator::CanExecute() only embeds the raw int (not the name) in its PASS_TYPE rejection message, so the assertion fails."
  confirming_evidence:
    - "Direct execution of capability_validator_test.exe --gtest_filter=CapabilityValidatorTest.RejectUnregisteredPassType reproduces the exact failure: 'Value of: result.unmet[0].detail.find(\"INFERENCE\") != std::string::npos || result.unmet[0].detail.find(\"1\") != std::string::npos / Actual: false / Expected: true' at capability_validator_test.cpp:127."
    - "Read generated/PassType.hpp: enum class PassType : int { COMPUTE, DATA_TRANSFORM, INFERENCE, RENDER, RETRAIN } — alphabetical order, so INFERENCE=2, not 1."
    - "Read capability_validator.cpp lines 305-312: PASS_TYPE rejection message is built purely from std::to_string(static_cast<int>(passType)) and ListAvailablePassTypes() (also raw ints) — the literal string 'INFERENCE' never appears anywhere in the message. With mock snapshot having only RENDER(3) registered, actual message is 'No executor registered for PassType 2. Available: [3]' — contains neither 'INFERENCE' nor the digit '1'."
    - "git blame confirms the assertion was authored 2026-08-04 (commit 01d727db) — same era the schema's PassType enum (COMPUTE, DATA_TRANSFORM, INFERENCE, RENDER, RETRAIN, alphabetized by quicktype from gnus-processing-schema.json) was already in its current shape, so the '1' assumption was a test-authoring error, not a later regression from a code change."
    - "All other assertions in the same test (unmet.size()==1, category==PASS_TYPE, detail contains 'Available', executorId.empty()) pass — confirming CapabilityValidator's actual rejection LOGIC is correct; only this one OR-assertion's numeric assumption is wrong."
  falsification_test: "If the message had instead contained 'INFERENCE' or the literal digit '1' anywhere, the assertion would pass and this hypothesis would be refuted. Directly observed gtest output shows Actual: false, confirming neither substring is present."
  fix_rationale: "N/A for this session (find_root_cause_only) — fix would either correct the test's expected substring to match the real enum value, or (more robustly) make CanExecute()'s message embed the human-readable PassType name so the test's 'INFERENCE' branch is satisfied and future enum-value churn doesn't silently break tests again."
  blind_spots: "Did not check whether other tests/call sites elsewhere in the codebase rely on the same 'PassType int value == N' assumption (a broader audit was out of scope for root-cause diagnosis). Did not verify whether SuperGenius/develop's submodule-consumption build would hit the same failure, since capability_validator_test is not wired into that build tree at all (see Evidence) — it can only fail in the standalone build, exactly as UAT reported."

## Symptoms

expected: |
  ctest passes with the same results in both the standalone SGProcessingManager
  build and the SuperGenius/develop submodule-consumption build, per roadmap
  Success Criterion 1 (TEST-01) for phase 09 (processor-pass-graph-conformance-suites).
  This includes the CapabilityValidatorTest.RejectUnregisteredPassType test case
  passing.
actual: |
  CapabilityValidatorTest.RejectUnregisteredPassType fails in SGProcessingManager.
errors: "Confirmed via direct execution (see Evidence) — gtest EXPECT_TRUE failure at capability_validator_test.cpp:127, Actual: false, Expected: true."
reproduction: |
  cd SuperGenius/SGProcessingManager/build/Windows/Release/test/capability/Release
  ./capability_validator_test.exe --gtest_filter=CapabilityValidatorTest.RejectUnregisteredPassType
  Fails 100% of the time (deterministic, not flaky) — reproduced once in this session.
started: "Discovered during UAT for phase 09 (this is the first time the standalone SGProcessingManager build's ctest suite has ever actually been run — see Evidence re: TEST-01 deferral)."

## Eliminated

(none — first hypothesis formed was confirmed directly)

## Evidence

- timestamp: 2026-08-07T02:00:00.000Z
  checked: SuperGenius/SGProcessingManager/test/capability/capability_validator_test.cpp (full file, 362 lines)
  found: |
    TEST_F(CapabilityValidatorTest, RejectUnregisteredPassType) sets pass.set_type(PassType::INFERENCE)
    against a mock snapshot that only registers a RENDER executor. Assertion at lines 126-127:
    EXPECT_TRUE(result.unmet[0].detail.find("INFERENCE") != npos || result.unmet[0].detail.find("1") != npos)
  implication: Test assumes the rejection message contains either the literal name "INFERENCE" or the digit "1" (implying PassType::INFERENCE's int value is 1).

- timestamp: 2026-08-07T02:00:30.000Z
  checked: SuperGenius/SGProcessingManager/include/capability/capability_validator.hpp and src/capability/capability_validator.cpp (full files)
  found: |
    CanExecute()'s Step 1 (PASS_TYPE check, lines 303-317) builds the unmet-requirement detail purely from
    numeric values: "No executor registered for PassType " + std::to_string(static_cast<int>(passType))
    + ". Available: [" + ListAvailablePassTypes(...) + "]" — ListAvailablePassTypes also emits raw ints
    via std::to_string(static_cast<int>(cap.passType)). The literal string "INFERENCE" is never constructed
    anywhere in this code path.
  implication: The message can only ever satisfy the test's "INFERENCE" branch by coincidence if some other
    numeric value's digit sequence happens to contain "INFERENCE" (impossible) — so the test's pass/fail hinges
    entirely on whether the "1" branch matches, i.e. on PassType::INFERENCE's underlying int value.

- timestamp: 2026-08-07T02:01:00.000Z
  checked: SuperGenius/SGProcessingManager/generated/PassType.hpp (untracked/generated file, produced from gnus-processing-schema.json's `"type": {"enum": ["inference","retrain","compute","render","data_transform"]}` via quicktype)
  found: "enum class PassType : int { COMPUTE, DATA_TRANSFORM, INFERENCE, RENDER, RETRAIN };" — alphabetically sorted by quicktype's C++ generator, NOT in JSON declaration order.
  implication: |
    PassType::COMPUTE=0, DATA_TRANSFORM=1, INFERENCE=2, RENDER=3, RETRAIN=4.
    PassType::INFERENCE == 2, not 1. The mock snapshot's only registered executor is RENDER (=3), so
    ListAvailablePassTypes() emits "3". Full expected message: "No executor registered for PassType 2. Available: [3]" — contains neither "INFERENCE" nor "1".

- timestamp: 2026-08-07T02:02:00.000Z
  checked: Direct execution — `capability_validator_test.exe --gtest_filter=CapabilityValidatorTest.RejectUnregisteredPassType` (binary at SuperGenius/SGProcessingManager/build/Windows/Release/test/capability/Release/, built Aug 6 21:34, newer than both capability_validator_test.cpp [Aug 5] and capability_validator.cpp [Aug 6 16:14] sources — binary is fresh, not stale)
  found: |
    [ RUN      ] CapabilityValidatorTest.RejectUnregisteredPassType
    capability_validator_test.cpp(127): error: Value of: result.unmet[0].detail.find( "INFERENCE" ) != std::string::npos || result.unmet[0].detail.find( "1" ) != std::string::npos
      Actual: false
      Expected: true
    [  FAILED  ] CapabilityValidatorTest.RejectUnregisteredPassType (0 ms)
  implication: Directly confirms the hypothesis — reproduces exactly, deterministically, with the exact line number predicted by source analysis.

- timestamp: 2026-08-07T02:02:30.000Z
  checked: git blame SuperGenius/SGProcessingManager/test/capability/capability_validator_test.cpp lines 109-130; git log -p SuperGenius/SGProcessingManager/gnus-processing-schema.json (run inside the nested SGProcessingManager submodule, not SuperGenius — SGProcessingManager is itself a nested git submodule per .gitmodules)
  found: |
    Test authored 2026-08-04 (commit 01d727db). The schema's PassType enum list ["inference","retrain","compute","render","data_transform"]
    traces back via `git log -p` to the very first commit (83f3bcf, "Initial schema conversions") — data_transform has existed in the
    enum since inception, it was not a later addition that shifted values. So the "1" assumption in the test was wrong from the moment
    it was written, not broken by a subsequent schema change.
  implication: This is a test-authoring defect (incorrect assumption about quicktype's alphabetical enum ordering), not a regression caused by later code changes.

- timestamp: 2026-08-07T02:03:00.000Z
  checked: SuperGenius/SGProcessingManager/CMakeLists.txt (top-level, no test/ subdirectory added) vs SuperGenius/SGProcessingManager/build/Windows/CMakeLists.txt (standalone wrapper, line 269: add_subdirectory(${PROJECT_ROOT}/test ${CMAKE_BINARY_DIR}/test)); also grepped SuperGenius/test and SuperGenius/CMakeLists.txt for any reference to capability_validator_test — none found.
  found: |
    capability_validator_test is ONLY built when SGProcessingManager is configured via its own standalone
    per-platform wrapper (build/Windows/CMakeLists.txt et al.), which explicitly adds test/. The plain root
    CMakeLists.txt (used when SuperGenius consumes SGProcessingManager as a submodule dependency) never adds
    test/ at all. SuperGenius's own build instead builds a *different* file, test/src/processing_conformance_capability/capability_conformance_test.cpp
    (an integration-style suite calling ProcessingManager::CanExecute(), reported 9/9 pass in 09-VERIFICATION.md).
  implication: |
    This explains why the bug was never caught by any prior phase-09 verification round: capability_validator_test
    literally cannot run inside the SuperGenius-embedded build. It can only be exercised via the standalone
    SGProcessingManager build topology — exactly the topology that TEST-01 (roadmap Success Criterion 1) flagged
    as "deferred" and never executed until this UAT round (09-07-SUMMARY.md: "Build verification deferred").
    This is the first real execution of this test, ever.

- timestamp: 2026-08-07T02:03:30.000Z
  checked: git status on SuperGenius (submodule) and SuperGenius/SGProcessingManager (nested submodule)
  found: |
    SuperGenius: clean except untracked scratch files (first_patch_input.raw, first_patch_output.raw, stitched_logits.raw, test/src/processing_datatypes/.gitignore).
    SGProcessingManager (nested submodule, checked out at bc74bc0 on heads/dev_rendering): clean, no uncommitted changes.
  implication: No submodule inconsistency (dirty state, detached-from-expected-commit, etc.) contributing to this bug — both are in a normal, clean state at their recorded commits.

## Resolution

root_cause: |
  `CapabilityValidatorTest.RejectUnregisteredPassType` (SuperGenius/SGProcessingManager/test/capability/capability_validator_test.cpp:126-127)
  asserts that CanExecute()'s PASS_TYPE rejection detail string contains either the substring "INFERENCE" or the
  digit "1", assuming `PassType::INFERENCE`'s underlying int value is 1. The actual generated enum
  (SuperGenius/SGProcessingManager/generated/PassType.hpp, produced by quicktype from gnus-processing-schema.json's
  `enum: ["inference","retrain","compute","render","data_transform"]`, which quicktype alphabetizes for C++) is
  `COMPUTE=0, DATA_TRANSFORM=1, INFERENCE=2, RENDER=3, RETRAIN=4` — so `PassType::INFERENCE == 2`, not 1.
  Additionally, `CapabilityValidator::CanExecute()` (src/capability/capability_validator.cpp:305-312) builds its
  PASS_TYPE rejection message using only raw numeric PassType values (never the human-readable name), so the
  message is literally "No executor registered for PassType 2. Available: [3]" — satisfying neither disjunct of
  the test's OR-assertion. This is a test-authoring defect present since the test was written (2026-08-04,
  commit 01d727db) — the underlying enum layout was already in its current shape at that time, so this is not a
  regression from a later code/schema change. It was never caught by any CI/verification round because
  `capability_validator_test` only builds under SGProcessingManager's standalone per-platform CMake wrapper
  (build/Windows/CMakeLists.txt etc.), a build topology roadmap Success Criterion TEST-01 explicitly deferred and
  which this UAT round is the first to actually execute. The CapabilityValidator's actual rejection LOGIC is
  correct (verified: PASS_TYPE category, unmet.size()==1, "Available" present, executorId empty all pass) —
  only this one numeric assumption in the test assertion is wrong.
fix: ""
verification: ""
files_changed: []
