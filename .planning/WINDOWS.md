---
schema_version: 1
open_count: 4
waived_count: 0
fixed_count: 0
total_count: 4
last_updated: 2026-10-21T23:08:41.058Z
---

# Broken Windows Ledger

> Cross-phase defect register. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 6 | deviation | SuperGenius/test/src/processing_multi/processing_multi_test.cpp | 291 | stale never-built test still references uint64_t GetProcessCost semantics; intentionally not edited per plan | open |  | 2026-10-06T01:48:54.227Z |  |
| 2 | 6 | unrun-verify | GeniusSDK/src/GeniusSDK.cpp |  | GeniusSDK/GeniusWallet builds not runnable in this environment; repo-wide grep is the plan-specified verification | open |  | 2026-10-06T01:48:54.604Z |  |
| 3 | 07 | deviation | SuperGenius/test/src/price_validator/price_validator_test.cpp | 12 | Task 3 reused existing testutil/ScopedEnvVar instead of authoring a new RAII env guard (plan prescribed new guard; existing asset has identical CRT semantics) | open |  | 2026-10-06T20:32:14.433Z |  |
| 4 | 3 | unmet-truth | thirdparty/sgns-blockstore/test/MinioServerHarness.cpp |  | G-3-1 half-open: EnvGatedTlsOnSmoke still cannot execute live - MinIO serves TLS-only, plaintext WaitUntilHealthy probe blocks Start(tls=true) (03-04 watch-for #3; replan options in 03-04-SUMMARY.md) | open |  | 2026-10-21T23:08:41.058Z |  |

````json
[
  {
    "id": 1,
    "kind": "deviation",
    "phase": "6",
    "file": "SuperGenius/test/src/processing_multi/processing_multi_test.cpp",
    "line": 291,
    "description": "stale never-built test still references uint64_t GetProcessCost semantics; intentionally not edited per plan",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-10-06T01:48:54.227Z",
    "resolved_at": null,
    "milestone": "v2.0"
  },
  {
    "id": 2,
    "kind": "unrun-verify",
    "phase": "6",
    "file": "GeniusSDK/src/GeniusSDK.cpp",
    "line": null,
    "description": "GeniusSDK/GeniusWallet builds not runnable in this environment; repo-wide grep is the plan-specified verification",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-10-06T01:48:54.604Z",
    "resolved_at": null,
    "milestone": "v2.0"
  },
  {
    "id": 3,
    "kind": "deviation",
    "phase": "07",
    "file": "SuperGenius/test/src/price_validator/price_validator_test.cpp",
    "line": 12,
    "description": "Task 3 reused existing testutil/ScopedEnvVar instead of authoring a new RAII env guard (plan prescribed new guard; existing asset has identical CRT semantics)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-10-06T20:32:14.433Z",
    "resolved_at": null,
    "milestone": "v2.0"
  },
  {
    "id": 4,
    "kind": "unmet-truth",
    "phase": "3",
    "file": "thirdparty/sgns-blockstore/test/MinioServerHarness.cpp",
    "line": null,
    "description": "G-3-1 half-open: EnvGatedTlsOnSmoke still cannot execute live - MinIO serves TLS-only, plaintext WaitUntilHealthy probe blocks Start(tls=true) (03-04 watch-for #3; replan options in 03-04-SUMMARY.md)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-10-21T23:08:41.058Z",
    "resolved_at": null,
    "milestone": "v2.0"
  }
]
````
