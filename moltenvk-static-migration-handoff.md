# Handoff — MoltenVK static-build migration (macOS done, iOS pending)

**Project:** GeniusNetwork (GNUS Child Wallet)
**Written:** 2026-10-16 (work performed 2026-10-13)
**Purpose:** Resume context after relocating the dev environment to a new external disk.

---

## 1. What was done (2026-10-13)

- Updated `thirdparty/MoltenVK` submodule from v1.2.8 (`e97ec496`) to upstream **main** (`5189f8de`, v1.4.3+).
- Replaced the macOS MoltenVK build (`build.sh` + xcodebuild + `.xcframework`) with a standard **CMake ExternalProject** producing a single **universal static** `libMoltenVK.a` (x86_64 + arm64), like every other thirdparty project.
- New idempotent patch step: `thirdparty/build/OSX/MoltenVK-build/MoltenVKStatic.cmake`:
  - rewrites `add_library(MoltenVK SHARED …)` → `add_library(MoltenVK …)` so `BUILD_SHARED_LIBS=OFF` applies;
  - appends install rules that `libtool -static`-merge `MoltenVK + MoltenVK_ShaderConverter + MoltenVK_Common + spirv-cross-{core,reflect,glsl,msl} + SPIRV-Tools-static` into one self-contained archive (replaces the old Xcode "prelink" package), installs headers (`vulkan/`, `vk_video/`, `MoltenVK/`) from the CPM-fetched Vulkan-Headers source dir;
  - deletes a stale legacy `External/` tree whose old headers (1.3.280) shadowed the CPM-pinned ones via the `MoltenVK/include/vulkan` symlink.
- Consumers updated to `moltenvk/include` + `moltenvk/lib/libMoltenVK.a` (macOS branches):
  - `thirdparty/build/OSX/CMakeLists.txt` (MNN wiring)
  - `SuperGenius/build/OSX/CMakeLists.txt`
  - `SuperGenius/SGProcessingManager/cmake/CommonBuildParameters.cmake` (`Vulkan::Vulkan` imported target)
  - `GeniusSDK/cmake/CommonBuildParameters.cmake`, `GeniusWallet/cmake/CommonBuildParameters.cmake`
  - removed dead `XCFRAMEWORK_PATH` refs (`SuperGenius/src/processing/CMakeLists.txt`, `SuperGenius/example/mnn_chunkprocess/CMakeLists.txt`)
- `ignore = dirty` added for MoltenVK in `thirdparty/.gitmodules` (build patches the worktree).
- Verified: thirdparty `make -j8` (MoltenVK, MNN fat lib), SuperGenius `make -j8` (151 universal test binaries; `multi_account_test` PASSED), standalone smoke test `vkCreateInstance -> 0`.
- Doc updated: `thirdparty/ThirdParty_Libraries_Integration.md` §30.

**Commit status (as of 2026-10-16):** all nested repos are committed **and pushed** — thirdparty `ede1a1a` ("MoltenVK upgrade and cmake build usage"), SuperGenius, SGProcessingManager, GeniusSDK, GeniusWallet. The **only** outstanding item is the parent GeniusNetwork repo, which still has the four submodule pointer bumps uncommitted.

---

## 2. Critical: the move itself

### 2.1 Commit-or-copy decision

The work is safe on the remotes for every nested repo. What remains before (or right after) relocating:

- **Commit + push the parent GeniusNetwork repo** — it currently shows uncommitted submodule pointer updates: `M thirdparty`, `M SuperGenius`, `M GeniusSDK`, `M GeniusWallet`. A fresh clone without this commit checks out the **old** submodule pointers, and the build breaks (old MoltenVK checkout has no root `CMakeLists.txt`, so the new ExternalProject configure fails). Recovery is trivial either way — the pushed commits exist — but committing the parent first avoids the situation entirely.
- The `thirdparty/MoltenVK` worktree will always show local modifications (`CMakeLists.txt`, `MoltenVK/CMakeLists.txt`) — that is the build-time patch, intentionally hidden via `ignore = dirty` in `.gitmodules` and re-applied idempotently by the ExternalProject `PATCH_COMMAND`. Not something to commit.
- Do **not** commit the untracked capture artifacts in the parent (`*.cap`, `*.raw`, `.vscode/`, `caps/`) — dev scratch data.

### 2.2 Repository state inventory (verified 2026-10-16)

| Repo | State |
|---|---|
| thirdparty | committed & pushed — `ede1a1a` "MoltenVK upgrade and cmake build usage" (includes `.gitmodules`, MoltenVK pointer → `5189f8de`, `build/OSX/CMakeLists.txt`, `MoltenVKStatic.cmake`, deleted `build.sh`, doc update) |
| thirdparty/MoltenVK | detached at `5189f8de` (upstream main); worktree carries the build-time patch (by design) |
| SuperGenius | committed & pushed (build/OSX/CMakeLists.txt, src/processing, mnn_chunkprocess, SGProcessingManager pointer) |
| SuperGenius/SGProcessingManager | committed & pushed (`cmake/CommonBuildParameters.cmake`) |
| GeniusSDK / GeniusWallet | committed & pushed (macOS Vulkan paths) |
| **GeniusNetwork (parent)** | **uncommitted**: submodule pointer bumps for the four repos above (+ untracked scratch files) |

### 2.3 After the move: rebuild from scratch

CMake caches/Makefiles/stamps embed absolute paths — in-place reconfigure after relocation is unreliable. Nuke build trees and reconfigure:

```bash
# external disk assumed mounted; NEWROOT = path to GeniusNetwork copy
cd $NEWROOT/thirdparty/build/OSX/Release && rm -rf * && cmake .. && make -j8
cd $NEWROOT/SuperGenius/build/OSX/Release && rm -rf * && cmake .. && make -j8
# optional standalone trees (same treatment):
#   SuperGenius/SGProcessingManager/build/OSX/Release
#   thirdparty/build/OSX/Debug (never rebuilt after the change)
```

Notes:
- Full thirdparty rebuild = hours (Boost, protobuf, rocksdb, …). Consider installing `ccache` first (MoltenVK's CMake already uses it if present).
- MoltenVK configure needs **network**: upstream CPM fetches pinned deps (Vulkan-Headers, SPIRV-Cross/Tools/Headers, cereal) into `~/.cache/CPM` (boot-disk home — survives the move; re-fetches if cleared).
- Format the external disk **APFS, case-insensitive** to match current behavior (legacy paths elsewhere in the repo have relied on case-insensitivity; the new MoltenVK layout itself no longer does).
- Xcode/SDK used previously: Xcode toolchain with MacOSX26.5 SDK, deployment target 13.0.

### 2.4 Post-move verification checklist

```bash
TP=$NEWROOT/thirdparty/build/OSX/Release
lipo -info $TP/moltenvk/lib/libMoltenVK.a          # expect: x86_64 arm64
ls $TP/moltenvk/include                            # expect: MoltenVK vk_video vulkan
nm -arch arm64 $TP/moltenvk/lib/libMoltenVK.a | grep -c "T _vkCreateInstance"   # >= 1
lipo -info $TP/MNN/lib/libMNN.a                    # expect: x86_64 arm64
cd $NEWROOT/SuperGenius/build/OSX/Release && ./test_bin/multi_account_test --gtest_filter='MultiAccountTest.PersistedHistoricalTrustAndTransactionsRestartWithSingleManagerOwnership'
```

Smoke test used originally (optional): compile a tiny program with `-I$TP/moltenvk/include` + link `$TP/moltenvk/lib/libMoltenVK.a` and frameworks `Metal IOSurface QuartzCore Foundation CoreFoundation CoreGraphics IOKit AppKit -lobjc`; `vkCreateInstance` should return 0 on Metal.

---

## 3. Outstanding work

### 3.1 Port iOS to the CMake/static flow — DONE (2026-10-16)

Completed as planned; details for reference:

- `thirdparty/build/cmake/MoltenVKStatic.cmake` is the hoisted shared patch script (moved from `build/OSX/MoltenVK-build/`), extended with a third idempotent edit: gates upstream `Common/CMakeLists.txt`'s `find_library(APPKIT_LIBRARY AppKit REQUIRED)` behind `if(NOT CMAKE_SYSTEM_NAME MATCHES "iOS|tvOS|visionOS")` — AppKit is absent from iOS SDKs and every AppKit include in sources is `MVK_MACOS`-guarded; the undefined variable simply drops out of the link list.
- `thirdparty/build/iOS/CMakeLists.txt` now uses the same CMake ExternalProject as OSX (`PATCH_COMMAND` → shared script, `MVK_CONFIG_LOG_LEVEL=error`, `_CMAKE_COMMON_CACHE_ARGS`, byproducts `moltenvk/lib/libMoltenVK.a` + headers). `iOS/MoltenVK-build/build.sh` deleted; `!/MoltenVK-build/` whitelist entries dropped from both platform `.gitignore`s.
- Consumers updated (macOS+iOS unified to `moltenvk/include` + `moltenvk/lib/libMoltenVK.a`):
  - `thirdparty/build/iOS/CMakeLists.txt` MNN wiring
  - `SuperGenius/build/iOS/CMakeLists.txt`
  - `GeniusSDK/cmake/CommonBuildParameters.cmake` (note: the macOS-branch update listed in §1 had not actually landed in this file — both branches still pointed at the old `moltenvk/build` + xcframework paths; fixed now for both platforms)
  - `GeniusWallet/cmake/CommonBuildParameters.cmake` (same situation as GeniusSDK)
  - `SuperGenius/SGProcessingManager/cmake/CommonBuildParameters.cmake` needed no code change — its unconditional-APPLE `_MVK_LIB` is now correct for both platforms (comment updated); the AppKit/UIKit framework split was already gated by `CMAKE_SYSTEM_NAME`.
- Docs updated: `thirdparty/ThirdParty_Libraries_Integration.md` §30, `thirdparty/build/mobile/README.md`.

### 3.2 Investigate the patching (intended)

Goal: shrink/eliminate worktree patching of the MoltenVK submodule. Options, roughly in order of preference:

1. **Upstream PR** to KhronosGroup/MoltenVK (community-maintained, still merging PRs): respect `BUILD_SHARED_LIBS` for the `MoltenVK` target; fix `install(TARGETS … LIBRARY DESTINATION)` to also cover `ARCHIVE`; install headers properly (`PUBLIC_HEADER` property or `install(DIRECTORY …)`). If merged and pinned, our patch reduces to (or below) the merge rules.
2. **Fork/branch pinning**: carry the changes as a branch in a fork, `branch = …` in `.gitmodules` — no worktree mutation, but a fork to maintain.
3. **Keep the idempotent patch but shrink it**: the only upstream edit strictly required is the one-line `SHARED` removal; the libtool merge + header install could move into our ExternalProject `INSTALL_COMMAND`/`cmake -P` script that we own entirely.
4. `MoltenVKOptions.cmake` is an upstream-sanctioned injection point but cannot change the library type today.

Also: the `External/` stale-tree cleanup in the patch script is one-time hygiene — droppable once confirmed no legacy checkouts remain. Consider pinning the submodule to a release **tag** rather than main for reproducibility.

### 3.3 Smaller leftovers

- `thirdparty/build/OSX/Debug` tree: never rebuilt after the change (stale `moltenvk/build/…xcframework` artifacts still on disk; harmless, consumers no longer reference them).
- GeniusSDK / GeniusWallet macOS builds were path-updated but not exercised end-to-end.
- Long-term watch: **MoltenVK is deprecated by Khronos** (community best-effort maintenance). For Apple-Silvermac Vulkan they point at KosmicKrisp (Mesa)/SDK; MoltenVK stays recommended for Intel Macs + iOS. No action needed now; revisit if it rots.
- Benign upstream warnings on macOS ≤14 targets: `newResidencySetWithDescriptor:`/`MTLAllocation` availability (macOS 15 APIs vs deployment target 13.0) — upstream guards at runtime.

---

## 4. How the macOS build works now (reference)

```text
thirdparty/build/OSX/Release/moltenvk/
├── include/{MoltenVK,vulkan,vk_video}/   # real dirs, not symlinks
└── lib/libMoltenVK.a                     # fat, self-contained
```

- ExternalProject `MoltenVK` (PREFIX `moltenvk`) configures `thirdparty/MoltenVK` with the shared apple toolchain args (`PLATFORM=MAC_UNIVERSAL` → fat in one pass) + `BUILD_SHARED_LIBS=OFF` from `_CMAKE_COMMON_CACHE_ARGS`; `MVK_CONFIG_LOG_LEVEL=error` preserves old `build.sh` parity.
- Deps come from upstream CPM (pinned in `ExternalRevisions/`), replacing `fetchDependencies`.
- The merged archive duplicates SPIRV-Tools symbols also present in `libshaderc_combined.a` on SuperGenius link lines — already the case with the old prelinked xcframework; duplicate archives coexist fine on Darwin ld.
- `BUILD_BYPRODUCTS`: `moltenvk/lib/libMoltenVK.a`, `include/vulkan/vulkan_core.h`, `include/MoltenVK/vk_mvk_moltenvk.h`.

## 5. Key files

| File | Role |
|---|---|
| `thirdparty/build/OSX/CMakeLists.txt` | MoltenVK ExternalProject + MNN Vulkan wiring (~line 118) |
| `thirdparty/build/iOS/CMakeLists.txt` | MoltenVK ExternalProject + MNN Vulkan wiring (same flow as OSX) |
| `thirdparty/build/cmake/MoltenVKStatic.cmake` | shared idempotent patch: static type, AppKit gate (iOS), merge+install rules, legacy cleanup |
| `thirdparty/build/OSX/MoltenVK-build/build.sh` | **deleted** (old flow) |
| `thirdparty/build/iOS/MoltenVK-build/build.sh` | **deleted** (old flow) |
| `SuperGenius/build/OSX/CMakeLists.txt` | `Vulkan_INCLUDE_DIR`/`Vulkan_LIBRARY` → new layout |
| `SuperGenius/build/iOS/CMakeLists.txt` | `Vulkan_INCLUDE_DIR`/`Vulkan_LIBRARY` → new layout |
| `SuperGenius/SGProcessingManager/cmake/CommonBuildParameters.cmake` | `Vulkan::Vulkan` imported target (valid for macOS + iOS) |
| `GeniusSDK/cmake/CommonBuildParameters.cmake`, `GeniusWallet/cmake/CommonBuildParameters.cmake` | APPLE branches (macOS + iOS) → new layout |
| `thirdparty/.gitmodules` | MoltenVK `ignore = dirty` |
