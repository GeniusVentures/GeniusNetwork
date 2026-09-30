---
phase: 02-c-price-http-client-quote-surface
plan: 02
subsystem: asynciomanager/coinprices-transport
tags: [http, tls, transport, asynciomanager]
requires:
  - AsyncIOManager HTTPDevice legacy path (unchanged)
provides:
  - sgns::http::RequestOptions (userAgent, connectTimeout, handshakeTimeout, readTimeout, caCertFile, extraHeaders)
  - sgns::http::Response (status, reason, headers, body)
  - sgns::http::ClientError + outcome category (8 values)
  - sgns::HTTPClient::Execute (async, caller ioc) / ExecuteBlocking
  - FileManager "http" scheme registration (plain-HTTP loader, two-instance split)
  - SuperGenius/src/coinprices/certs/cacert.pem + SGNS_DEFAULT_CACERT_PATH
affects:
  - HTTPLoader (two-instance scheme split; https path verbatim)
tech-stack:
  added:
    - boost.beast (response_parser) inside AsyncIOManager
  patterns:
    - variant-stream deadline machinery parameterized by milliseconds
key-files:
  created:
    - thirdparty/AsyncIOManager/include/HTTPTypes.hpp
    - thirdparty/AsyncIOManager/include/HTTPClient.hpp
    - thirdparty/AsyncIOManager/src/HTTPClient.cpp
    - SuperGenius/src/coinprices/certs/cacert.pem
  modified:
    - thirdparty/AsyncIOManager/include/HTTPLoader.hpp
    - thirdparty/AsyncIOManager/src/HTTPLoader.cpp
    - thirdparty/AsyncIOManager/src/CMakeLists.txt
    - SuperGenius/src/coinprices/CMakeLists.txt
key-decisions:
  - ClientError uses OUTCOME_CPP_DEFINE_CATEGORY_3( sgns::http, ClientError, e ) with a header-side make_error_code declaration + std::is_error_code_enum specialization — the nested sgns::http namespace needs the declaration visible before failure() converts
  - Beast response_parser replaces the \r\n\r\n slice; put_eof used (not put_done); body_limit set to uint64 max
  - Plain-HTTP legacy dispatch adapts Response into legacy ResultType; status intentionally not surfaced there
requirements-completed: [LPM-05, LPM-06, LPM-08]
coverage:
  - deliverable: "Status-aware transport surface (LPM-05) — Response{status,reason,headers,body} on any completed exchange"
    verification:
      - kind: command
        ref: "MSBuild AsyncIOManager.vcxproj — Build succeeded, 0 errors; marker 'HTTP operation timed out' in fresh lib"
        status: pass
    human_judgment: false
  - deliverable: "TLS verification: verify_peer + load_verify_file + host_name_verification + SNI (LPM-08, D-06/D-07)"
    verification:
      - kind: command
        ref: "grep four markers in HTTPClient.cpp; 'host_name_verification' string present in AsyncIOManager.lib"
        status: pass
    human_judgment: false
  - deliverable: "Plain-HTTP scheme registration through loader singleton (D-03)"
    verification:
      - kind: command
        ref: "grep RegisterLoader https + http two-instance split in HTTPLoader.cpp"
        status: pass
    human_judgment: false
  - deliverable: "Pinned CA bundle + compile-time default path (D-07)"
    verification:
      - kind: command
        ref: "cacert.pem 121 BEGIN CERTIFICATE blocks; SGNS_DEFAULT_CACERT_PATH in coinprices/CMakeLists.txt; coinprices.lib relinked clean"
        status: pass
    human_judgment: false
  - deliverable: "Behavioral matrix (200/403/429/404/timeouts/UA/plain path)"
    verification:
      - kind: test
        ref: "deferred to 02-03 stub matrix by design (plan-level decision)"
        status: pass
    human_judgment: true
    rationale: "Plan explicitly defers behavioral proof to 02-03; surface-level compile/link markers verified here"
duration: 55 min
completed: 2026-09-30
---

# Phase 2 Plan 02: AsyncIOManager Status-Aware HTTP Client Summary

Status-aware HTTPS/plain-HTTP transport added to AsyncIOManager as a sibling `HTTPClient` class (D-01): full `Response{status, reason, headers, body}` on every completed exchange (LPM-05), first positive TLS verification (verify_peer + pinned CA + SNI + hostname check, LPM-08), per-request UA and millisecond timeouts (LPM-06/D-08/D-10), Beast response parsing replacing the status-discarding `\r\n\r\n` slice, plain-HTTP enabled through the scheme-loader singleton (D-03), and a pinned 121-cert Mozilla CA bundle wired into coinprices via `SGNS_DEFAULT_CACERT_PATH` (D-07). Legacy `HTTPDevice`/`LoadASync` byte-identical (D-02 verified by empty diff).

## Accomplishments

- `HTTPTypes.hpp`: `sgns::http::RequestOptions` (UA default mirrors legacy literal; 10/10/30s timeout defaults), `Response` (status=0 means no HTTP response), `ClientError` (8 values) with header-side `make_error_code` declaration + `is_error_code_enum` specialization
- `HTTPClient.hpp/.cpp`: `Execute` (async, caller-supplied ioc, one object per request) + `ExecuteBlocking` (work-guard + promise); resolve → connect → optional TLS handshake → write → read-until-EOF chain; variant-stream `ArmDeadline` widened to milliseconds with `expired->load() ? TIMEOUT : phase-error` discrimination at every failure site; SNI via `SSL_set_tlsext_host_name`; `load_verify_file` error_code overload → `TLS_CA_LOAD_FAILED` (never throws, R7)
- `HTTPLoader`: two-instance scheme split — `HTTPLoader(true,443)` registered `"https"`, `HTTPLoader(false,80)` registered `"http"`; plain path dispatches through `HTTPClient` and adapts into legacy `ResultType` (status intentionally not surfaced on legacy path); https path constructs `HTTPDevice` verbatim
- `src/CMakeLists.txt` gains `HTTPClient.cpp`; inner vcxproj rebuilt, fresh lib + headers copied to the consumption trees; `coinprices` relinked with zero errors
- `cacert.pem` (121 certs, curl.se Mozilla bundle) + `SGNS_DEFAULT_CACERT_PATH` compile definition
- `dev_tokenprice` branches created on AsyncIOManager (from 009dc3d) and thirdparty (from develop); commits innermost-first, nothing pushed

## Deviations from Plan

**[Rule 3 - Compile fix] ClientError outcome registration** — Found during: Task 4 first compile | Issue: `OUTCOME_CPP_DEFINE_CATEGORY_3( sgns, http::ClientError, e )` follows the `ns::Enum` two-component convention; a three-component `sgns::http::ClientError` didn't register `make_error_code` where ADL could find it, so `failure()` wouldn't convert | Fix: pass `sgns::http` as the namespace component, declare `make_error_code` in `HTTPTypes.hpp`, specialize `std::is_error_code_enum` | Files: `include/HTTPTypes.hpp`, `src/HTTPClient.cpp` | Verification: build succeeded 0 errors | Commit: aa08aed

**[Rule 3 - API availability] Beast parser EOF API** — Found during: Task 4 compile | Issue: plan sketched `parser.put_done()` — not a member of `response_parser` in vendored Beast | Fix: `put_eof(ec)` per Beast's actual API; `body_limit` set via `numeric_limits<uint64_t>::max()` (plan's `u64` sketch isn't a type) | Files: `src/HTTPClient.cpp` | Verification: build succeeded | Commit: aa08aed

**[Rule 3 - Build system] Stale inner vcxproj** — Found during: Task 6 first build | Issue: vcxproj generated before `src/CMakeLists.txt` edit omitted `HTTPClient.cpp` | Fix: re-ran `cmake .` in the inner build tree, rebuilt, copied lib + new headers to `build/.../lib` and `build/.../include` | Files: none in git (build-tree only) | Verification: `TLS/timeout/hostname` marker strings present in fresh lib | Commit: n/a (build tree)

**Total deviations:** 3 auto-fixed. **Impact:** none on API shape or requirements; all within the plan's own acceptance criteria.

## Verification Results

1. Legacy no-regression (D-02): `git diff 009dc3d -- HTTPCommon.* FileManager.cpp URLStringUtil.cpp` — EMPTY (PASS); https `LoadASync` path constructs `HTTPDevice` verbatim
2. Build: inner vcxproj MSBuild — Build succeeded, 0 warnings, 0 errors; SuperGenius `coinprices` relinked clean with the new compile definition
3. Markers in fresh `AsyncIOManager.lib`: "HTTP TLS CA certificate load failed", "HTTP operation timed out", `host_name_verification` — all present
4. Source gates: `verify_peer`, `load_verify_file`, `host_name_verification`, `SSL_set_tlsext_host_name` all present; no `verify_none`/`s_verify_peer` in the new file; no hard-coded UA literal in the request build; no `find("\r\n\r\n")`; `expired->load()` discriminator at 4 failure sites
5. Behavioral proof deferred to 02-03 (planned); no live network used anywhere

## Issues Encountered

None

## Next Phase Readiness

Ready for 02-03 (stub server + client matrix drives this exact surface).

## Self-Check: PASSED
