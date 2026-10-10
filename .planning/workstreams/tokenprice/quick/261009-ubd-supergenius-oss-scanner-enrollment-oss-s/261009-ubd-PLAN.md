---
phase: quick-261009-ubd
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - SuperGenius/.oss-scanner/Dockerfile
  - SuperGenius/.oss-scanner/threat_model.md
  - SuperGenius/.oss-scanner/README.md
autonomous: true
requirements: [OSS-SCANNER-SUPERGENIUS-SLICE-1]
user_setup: []

estimate:
  tokens: 60000
  raw_tokens: 55000
  tasks: 3
  confidence: low

must_haves:
  truths:
    - "SuperGenius branch dev_ossscanner contains .oss-scanner/Dockerfile that an anonymous, unauthenticated Debian 12 amd64 Docker builder can execute to a successful focused ctest run within a 45-minute budget"
    - "The Dockerfile fetches only public artifacts (public submodule repos at pinned Gitlink commits, public thirdparty/zkLLVM develop-Release GitHub release assets, public ghcr.io/geniusventures/almalinux-8 base) — zero tokens, zero private deps, zero secrets"
    - "After the build phase completes, the test phase performs no network fetches of SuperGenius-controlled code (offline-capable test run)"
    - "SuperGenius/.oss-scanner/threat_model.md documents trust boundaries, untrusted inputs, security goals with severity guidance, and third-party code exclusions"
    - "The work is committed on branch dev_ossscanner in the SuperGenius submodule and pushed to origin, without touching the dirty SGProcessingManager submodule pointer"
  artifacts:
    - SuperGenius/.oss-scanner/Dockerfile
    - SuperGenius/.oss-scanner/threat_model.md
    - SuperGenius/.oss-scanner/README.md
  key_links:
    - "Dockerfile dnf dependency set == almalinux-8 CI safety-net install (vulkan-loader-devel vulkan-headers ninja-build which perl perl-IPC-Cmd)"
    - "Dockerfile thirdparty/zkLLVM asset tags == Linux-x86_64-develop-Release / Linux-x86_64-Release with THIRDPARTY_BUILD_DIR/ZKLLVM_BUILD_DIR pointing at the extracted build/Linux/x86_64/Release subdirs"
    - "Dockerfile cmake configure == CI line: cmake -S build/Linux -B build/Linux/x86_64/Release -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ plus the two *_BUILD_DIR args"
---

<objective>
Create slice 1 of the Anthropic OSS Scanner enrollment for SuperGenius (issue #10 follow-up, quick-task track per 261009-rrt evaluation): the per-project build Dockerfile at `SuperGenius/.oss-scanner/Dockerfile`, the scoped threat model at `SuperGenius/.oss-scanner/threat_model.md`, validated as far as locally possible on a Windows host whose Docker daemon may be down (degrade to structural validation + branch push), committed on branch `dev_ossscanner` in the SuperGenius submodule.

Purpose: Anthropic's scanner enrolls repos by building `.oss-scanner/Dockerfile` in an anonymous, offline-after-build Debian 12 amd64 VM (45 min / 16 CPU / 64 GB / 120 GB). This plan produces the artifact pair the scanner needs without any authenticated resource, so the maintainer-gated upstream enrollment PR (later slice) has something valid to point at.

Output: `SuperGenius/.oss-scanner/{Dockerfile,threat_model.md,README.md}` on pushed branch `dev_ossscanner`, plus a summary recording what was validated locally and what is deferred (full local docker build, `tools/validate.py`, `tools/check`, upstream PR — maintainer/CLA-gated).
</objective>

<execution_context>
@~/.copilot/gsd-core/workflows/execute-plan.md
@~/.copilot/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.planning/workstreams/tokenprice/quick/261009-rrt-evaluate-issue-10-oss-scanner-enrollment/EVALUATION.md
@SuperGenius/.github/workflows/cmake.yml
@SuperGenius/.gitmodules
@SuperGenius/build/Linux/CMakeLists.txt
@SuperGenius/build/CommonBuildParameters.cmake
</context>

<tasks>

<task type="auto">
  <name>Task 1: Author SuperGenius/.oss-scanner/Dockerfile from the verified CI recipe</name>
  <files>SuperGenius/.oss-scanner/Dockerfile</files>
  <action>
Create the directory `SuperGenius/.oss-scanner/` and write a single-stage Dockerfile (no multi-stage needed; scanner just needs a working build) that mirrors the Linux x86_64 Release CI job in `SuperGenius/.github/workflows/cmake.yml` but with EVERY authenticated step replaced by its anonymous equivalent. Use this exact skeleton (fill comments as noted):

1. `FROM ghcr.io/geniusventures/almalinux-8:latest` — verified anonymously pullable (anon token → 200). The image already ships clang, cmake, ninja, git-lfs, Vulkan headers, dbus, gnome-keyring (per CI comment lines ~359-362).
2. `dnf install -y vulkan-loader-devel vulkan-headers ninja-build which perl perl-IPC-Cmd` — the exact CI safety-net set. Use `dnf` unconditionally (no apt branch needed; base is AlmaLinux 8). Add `git ca-certificates tar gzip` only if not already present in the base image — verify by assuming the CI image has git (it checks out repos) and stating that assumption in a trailing comment.
3. Anonymous GitHub release downloads: the CI uses `gh release download` with `GNUS_TOKEN_1`; the Dockerfile MUST instead use plain `curl -fsSL --retry 3` against the public release-asset endpoints:
   - thirdparty: `https://github.com/GeniusVentures/thirdparty/releases/download/Linux-x86_64-develop-Release/Linux-x86_64-Release.tar.gz` extracted into `/opt/thirdparty`, with `THIRDPARTY_BUILD_DIR=/opt/thirdparty/build/Linux/x86_64/Release` (CI's `$BUILD_DIRECTORY` is `build/Linux/x86_64/Release` under the extract root — asset layout verified by CI lines 318-331).
   - zkLLVM: `https://github.com/GeniusVentures/zkLLVM/releases/download/Linux-x86_64-develop-Release/Linux-x86_64-Release.tar.gz` extracted into `/opt/zkLLVM` with the same four tar excludes as CI (`--exclude='*bin/assigner' --exclude='*bin/clang-zkllvm' --exclude='*bin/llvm-link-zkllvm' --exclude='*bin/transpiler'`), `ZKLLVM_BUILD_DIR=/opt/zkLLVM/build/Linux/x86_64/Release`.
   Both endpoints verified public 2026-10-10 via anonymous api.github.com. Note in a comment that the release tag moves with develop and the asset name is stable.
4. Submodule materialization, anonymous and pinned: the scanner clones the repo non-recursively, so submodules arrive as empty dirs with gitlinks. Inside the build context `COPY . /src` brings the already-cloned working tree (executor builds with context = the SuperGenius repo root; submodules will NOT be populated by the scanner, so this step is mandatory). Do NOT use `git clone` of the superproject. Instead, for each of the five build-relevant submodules (gRPCForSuperGenius, GeniusKDF, ProofSystem, SGProcessingManager, evmrelay — skip `docs`, which points at `../sg-docs` and is not in the build graph per `build/CommonBuildParameters.cmake` add_subdirectory list):
   - `RUN` a loop or explicit commands: `git clone --depth 1` is FORBIDDEN (moves with branch heads, not pinned commits). Correct pattern per submodule: read the gitlink SHA recorded in the superproject tree (`git ls-tree HEAD <path>` fails without submodules present — instead use `git submodule status` semantics), so: `git init <path>` then `git remote add origin https://github.com/GeniusVentures/<repo>.git` then `git fetch --depth 1 origin <gitlink-sha>` then `git checkout FETCH_HEAD`. Implement this as ONE `RUN` bash block that iterates a `[name]=url` associative array, extracts each gitlink SHA via `git ls-tree HEAD -- <name>` (this works in the copied tree even without .git/modules), and errors loudly (exit 1 with message) if any SHA is missing or fetch fails. All six submodule URLs resolve to `https://github.com/GeniusVentures/<repo>.git` from the relative `../<repo>` entries in `.gitmodules` (public, verified). Include a comment: git-lfs not needed for these repos at build time (`.gitattributes` LFS-covers only `*.cap` test fixtures, and the focused test subset below does not deserialize capture files).
5. Compiler pin: `ENV CC=clang CXX=clang++` plus `-DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++` on the configure line — mirrors CI's COMPILER_PIN (g++ 8.5 in Alma 8 cannot compile zkLLVM crypto3 constexpr; CI comment lines ~505-519).
6. Configure + build with the focused-target knob: `RUN cmake -S /src/build/Linux -B /src/build/Linux/x86_64/Release -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DTHIRDPARTY_BUILD_DIR=/opt/thirdparty/build/Linux/x86_64/Release -DZKLLVM_BUILD_DIR=/opt/zkLLVM/build/Linux/x86_64/Release -DSGNS_PRINT_LOGS=ON && cmake --build /src/build/Linux/x86_64/Release --target network_registry_test network_membership_filter_test crypto_test base_test -j $(nproc)` — wait: do NOT invent target names; test executables register via the project's `addtest()` helper (see `test/src/networkregistry/CMakeLists.txt` producing `network_registry_test`, `network_membership_filter_test`). Build this representative set: `network_registry_test`, `network_membership_filter_test` (network/account layer), `crypto_test` (verify the name exists in `test/src/crypto/CMakeLists.txt` first; if the helper names differ, use the first addtest() name from each of `test/src/networkregistry/` and `test/src/crypto/`), plus the aggregate library target the tests link (from CommonBuildParameters the src/ tree builds the supergenius libs — if no single aggregate target exists, building the test executables alone is sufficient since CMake pulls their dependency closure). The 45-minute budget rule: full `--build . -j` is too big; the explicit `--target` list keeps the build representative (touches src/, ProofSystem, SGProcessingManager, evmrelay dependency closure) and bounded. Add a `# Build more: replace --target list with plain `cmake --build ... -j`` comment documenting the knob. If `crypto_test` or any chosen name is not found in the tree during authoring, substitute the next addtest() target from `test/src/crypto/` and note the substitution in the README (Task 3).
7. Focused ctest, offline after build: `RUN ctest --test-dir /src/build/Linux/x86_64/Release -C Release --output-on-failure -R '^(network_registry_test|network_membership_filter_test|crypto_test)$' -LE requires_foundry` (adjust the -R alternation to the final target list; `-LE requires_foundry` mirrors CI exclusion of Foundry-dependent e2e suites). This RUN performs no network fetch: the binaries and their fixtures are already in the image. Do NOT add dbus-run-session/gnome-keyring wrapping or MNN GTEST_FILTER logic — those exist in CI only for the full suite and the aarch64-Debug Vulkan issue; the focused x86_64 Release subset chosen here avoids MNN Vulkan-instance paths (no processing_* suites selected). Keep `.oss-scanner/Dockerfile` build-context-relative: the scanner builds it from the repo root, so `COPY . /src` is correct and no ADD URLs for the superproject are used.
8. No secrets, no ARG/ENV carrying tokens, no `--mount=type=secret`, no authenticated GHCR (the base image pull is the only ghcr access and is anonymous), no private repos. Trailing comment block: enumerate the anonymous resources used (base image URL, 2 release asset URLs, 5 submodule clone URLs) with the 2026-10-10 verified-public note.

The Dockerfile lives ONLY at `SuperGenius/.oss-scanner/Dockerfile`; touch nothing else in the submodule except the other files in this plan.
  </action>
  <verify>
    <automated>cd W:/gnus/GeniusNetwork; if (Test-Path SuperGenius/.oss-scanner/Dockerfile) { $d = Get-Content SuperGenius/.oss-scanner/Dockerfile -Raw; $checks = @('FROM ghcr.io/geniusventures/almalinux-8','dnf install -y vulkan-loader-devel vulkan-headers ninja-build which perl perl-IPC-Cmd','thirdparty/releases/download/Linux-x86_64-develop-Release','zkLLVM/releases/download/Linux-x86_64-develop-Release','THIRDPARTY_BUILD_DIR=/opt/thirdparty/build/Linux/x86_64/Release','ZKLLVM_BUILD_DIR=/opt/zkLLVM/build/Linux/x86_64/Release','git fetch --depth 1','CMAKE_BUILD_TYPE=Release','-DCMAKE_C_COMPILER=clang','--exclude=*bin/assigner','ctest','requires_foundry'); $missing = $checks | Where-Object { $d -notmatch [regex]::Escape($_) }; if ($missing) { Write-Output "MISSING: $($missing -join ', ')"; exit 1 } else { Write-Output 'Dockerfile structural checks PASS' }; $banned = @('GNUS_TOKEN','github_token','GITHUB_TOKEN','--mount=type=secret','gh release download'); $found = $banned | Where-Object { $d -match [regex]::Escape($_) }; if ($found) { Write-Output "BANNED TOKEN FOUND: $($found -join ', ')"; exit 1 } else { Write-Output 'No secrets/auth patterns PASS' } } else { Write-Output 'Dockerfile missing'; exit 1 }</automated>
  </verify>
  <done>Dockerfile exists, contains the anonymous base, exact dnf set, both anonymous release-asset downloads with correct extraction dirs and zkLLVM excludes, gitlink-pinned submodule fetch loop (no --depth-1 branch clones), clang compiler pin, Release configure with both BUILD_DIR args, focused --target build, focused offline ctest with requires_foundry exclusion, and zero token/secret/auth patterns.</done>
</task>

<task type="auto">
  <name>Task 2: Author SuperGenius/.oss-scanner/threat_model.md</name>
  <files>SuperGenius/.oss-scanner/threat_model.md</files>
  <action>
Write a scoped threat model for the OSS-scanner build context (what the scanner sees and exercises), NOT a threat model of SuperGenius at runtime. Required sections:

1. **Scope statement** — this document covers the Anthropic OSS Scanner build (`/src` tree + Dockerfile) and the code surfaces it compiles and tests; it does not cover deployed-network threats. Third-party exclusion statement: `thirdparty/` and `zkLLVM/` prebuilt release artifacts, plus vendored third-party sources inside submodules (gRPC, Boost, etc. as consumed via THIRDPARTY_BUILD_DIR/ZKLLVM_BUILD_DIR), are out of scope for this model — they are separately maintained dependencies fetched as pinned public artifacts; SuperGenius first-party code under `src/`, `test/`, `node/`, and the build system is in scope.
2. **Trust boundaries** table — at minimum: (a) scanner VM → SuperGenius source tree (the scanner executes our build on Anthropic infrastructure; our build must not reach for private resources); (b) Dockerfile → network (anonymous fetches only: base image, two GitHub release assets, five public submodule repos — each already enumerated in the Dockerfile's trailing comment); (c) build-time code execution (CMake scripts, codegen, proto compilers execute with build privileges — standard supply-chain surface); (d) test execution → host (tests run inside the container; the focused subset performs no outbound network calls and no capture-file deserialization).
3. **Untrusted inputs** — enumerate what crosses into the scanned code: gitlink-pinned submodule commits (pinned by SHA in the superproject tree — a branch-head drift cannot silently change what is built), release-asset tarballs (pinned by tag name `Linux-x86_64-develop-Release`, which is mutable-by-release — note this as accepted residual risk with severity medium and rationale: tags are org-controlled, artifacts are non-executable-at-download, and checksums can be added later), test fixtures compiled into the tree, and compiler/toolchain from the base image (org-controlled).
4. **Security goals** — anonymous reproducibility (no credential is required or referenced), offline-after-build test execution, pinned dependency graph (no floating branch clones), bounded build (45 min), no secret exfiltration surface (no ENV/ARG carrying tokens; nothing in the image writes outside /src and /opt).
5. **Severity guidance** — table mapping each boundary to impact if violated (e.g., release-asset tag mutation → supply-chain compromise of the scanner build → high; submodule gitlink tamper → requires superproject commit access → mitigated by repo permissions; Dockerfile itself carries no secrets → info). Reference the issue #10 checklist line "scoped threat model" this artifact satisfies.
  </action>
  <verify>
    <automated>cd W:/gnus/GeniusNetwork; if (Test-Path SuperGenius/.oss-scanner/threat_model.md) { $t = Get-Content SuperGenius/.oss-scanner/threat_model.md -Raw; foreach ($s in @('Trust boundaries','Untrusted inputs','Security goals','Severity','Third-party','gitlink','offline')) { if ($t -notmatch $s) { Write-Output "MISSING SECTION/TOKEN: $s"; exit 1 } }; Write-Output 'threat_model structural checks PASS' } else { Write-Output 'threat_model missing'; exit 1 }</automated>
  </verify>
  <done>threat_model.md exists with scope + third-party exclusion statement, trust-boundaries table covering the four boundaries, untrusted-inputs enumeration including the tag-mutability accepted risk at medium severity, security goals, and severity guidance table.</done>
</task>

<task type="auto">
  <name>Task 3: Validate (docker or degraded), add README, commit on dev_ossscanner, push</name>
  <files>SuperGenius/.oss-scanner/README.md</files>
  <action>
First try real validation: (a) attempt `docker version --format '{{.Server.Version}}'` once; if the daemon is down, run `Start-Process 'C:\Program Files\Docker\Docker\Docker Desktop.exe'`, poll `docker version` every 10s for up to 90s. (b) If the daemon comes up: `docker build -f SuperGenius/.oss-scanner/Dockerfile -t sg-oss-scanner-probe SuperGenius` — expect the FULL build to take long on this host; cap the observation at 15 minutes (async + read_powershell polling); if it exceeds that, stop it and record partial-log evidence that the anonymous fetch phases (base pull, release downloads, submodule gitlink fetches) succeeded, marking the compile+ctest phases as deferred-to-scanner. (c) If the daemon never comes up OR `hadolint` is unavailable (`hadolint --version` check): degraded validation = the Task 1 structural gate + a manual line-by-line pass recorded in the README ("validated: structure, anonymous-fetch correctness, pinning; deferred: full docker build — Docker Desktop daemon unavailable this session; exact commands for later: docker build -f .oss-scanner/Dockerfile -t sg-oss-scanner . && docker run --rm sg-oss-scanner ctest --test-dir /src/build/Linux/x86_64/Release -R '^network_' --output-on-failure").

Second, write `SuperGenius/.oss-scanner/README.md` (~40 lines): what this directory is (Anthropic OSS Scanner enrollment artifacts, issue #10), how the Dockerfile satisfies the scanner constraints (anonymous, pinned, offline-after-build, 45-min-focused), the deferred-validation state with exact reproduce commands, the upstream steps NOT done here (validate.py, tools/check, enrollment PR — maintainer/CLA-gated per issue #10), and any target-name substitutions made in Task 1.

Third, commit in the SUBMODULE only: `Set-Location SuperGenius`; assert `git status --short` shows ONLY `?? .oss-scanner/` new (the `? SGProcessingManager` dirty pointer must NOT be staged — use explicit pathspec `git add .oss-scanner` and verify `git status --short --cached` before committing, never `git add -A`); commit message `ci(oss-scanner): add .oss-scanner Dockerfile + threat model for Anthropic OSS Scanner enrollment (issue 10, slice 1)`; push `git push -u origin dev_ossscanner`. Then back in the ROOT repo do NOT stage anything (the submodule pointer bump is intentionally left uncommitted for the maintainer flow) — but DO record in the summary that the root repo still shows the pre-existing `? SGProcessingManager` plus a now-modified SuperGenius pointer, both deliberately unstaged.
  </action>
  <verify>
    <automated>cd W:/gnus/GeniusNetwork/SuperGenius; $out = git --no-pager log -1 --format='%H %s' ; Write-Output "HEAD: $out"; if ($out -notmatch 'oss-scanner') { Write-Output 'FAIL: HEAD commit is not the oss-scanner commit'; exit 1 }; $tracked = git --no-pager show --stat --format= --name-only HEAD; foreach ($f in @('.oss-scanner/Dockerfile','.oss-scanner/threat_model.md','.oss-scanner/README.md')) { if ($tracked -notmatch [regex]::Escape($f)) { Write-Output "FAIL: $f not in HEAD commit"; exit 1 } }; if ($tracked -match 'SGProcessingManager') { Write-Output 'FAIL: dirty submodule pointer was staged'; exit 1 }; $branch = git rev-parse --abbrev-ref HEAD; if ($branch -ne 'dev_ossscanner') { Write-Output "FAIL: wrong branch $branch"; exit 1 }; git fetch origin dev_ossscanner 2>$null; $local = git rev-parse HEAD; $remote = git rev-parse origin/dev_ossscanner 2>$null; if ($remote -and ($local -eq $remote)) { Write-Output 'PUSHED: origin/dev_ossscanner matches HEAD' } else { Write-Output "WARN: remote not in sync (local=$local remote=$remote) — check push output"; exit 1 }; Write-Output 'commit+push checks PASS'</automated>
  </verify>
  <done>HEAD of SuperGenius is the oss-scanner commit on branch dev_ossscanner containing exactly the three .oss-scanner files (SGProcessingManager pointer untouched), origin/dev_ossscanner matches HEAD, README records the validation level achieved (full/partial/structural) and the deferred commands, and the summary notes the deliberately unstaged root-repo pointers.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| scanner VM → build context | Anthropic infrastructure executes our Dockerfile on a non-recursive clone; the build must not reference private resources |
| Dockerfile → network | anonymous fetches only: ghcr base image, 2 public release assets, 5 public submodule repos |
| build-time code execution | CMake/codegen/proto tooling runs with build privileges inside the container |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-Q261009UBD-01 | Tampering | release-asset tags (thirdparty/zkLLVM) | medium | accept | Tags are org-controlled and assets are consumed as data; gitlink-SHA pinning covers source; checksum pinning noted as future hardening in threat_model.md |
| T-Q261009UBD-02 | Information disclosure | Dockerfile contents | low | mitigate | Structural gate asserts zero token/secret patterns (GNUS_TOKEN, GITHUB_TOKEN, --mount=type=secret, gh release download) in Task 1 verify |
| T-Q261009UBD-03 | Tampering | submodule fetch | medium | mitigate | Fetch by gitlink SHA recorded in superproject tree with loud exit-1 on missing SHA; branch-head clones forbidden |
| T-Q261009UBD-04 | DoS | 45-min scanner budget | low | mitigate | Focused --target build + focused -R ctest subset with documented knob to expand |
</threat_model>

<verification>
- Task 1 structural gate: required fragments present, banned auth patterns absent (PowerShell, exit 1 on failure)
- Task 2 structural gate: threat-model sections present
- Task 3 git gate: HEAD commit content, branch, untouched SGProcessingManager pointer, origin sync
- Best-effort `docker build` (degrades to structural validation when the daemon is unavailable — recorded in README)
</verification>

<success_criteria>
- `SuperGenius/.oss-scanner/Dockerfile` anonymous + pinned + offline-test-capable, structurally verified
- `SuperGenius/.oss-scanner/threat_model.md` scoped and structurally verified
- `SuperGenius/.oss-scanner/README.md` records validation level and deferred commands
- Committed on `dev_ossscanner`, pushed to origin, dirty pointer untouched
- NOT done (deliberately, recorded in summary): upstream enrollment PR, validate.py/tools/check runs, root-repo submodule pointer staging
</success_criteria>

<output>
Create `.planning/workstreams/tokenprice/quick/261009-ubd-supergenius-oss-scanner-enrollment-oss-s/261009-ubd-SUMMARY.md` when done
</output>
