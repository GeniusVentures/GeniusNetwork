# GNUS.ai Repository Agent Instructions

Before planning or changing code in this repository or any submodule, read:

1. `MASTER_ARCHITECTURE.md`
2. `.gitmodules` on the active branch
3. `.planning/codebase/ARCHITECTURE.md`
4. `.planning/codebase/STRUCTURE.md`
5. `.planning/codebase/INTEGRATIONS.md`
6. `.planning/codebase/CONVENTIONS.md`
7. `.planning/codebase/TESTING.md`
8. `.planning/codebase/CONCERNS.md`

## Mandatory ownership rules

- `GeniusNetwork` composes and pins the platform; it is not the default implementation location.
- Put node, networking, ledger, CRDT, storage, processing, and runtime changes in `SuperGenius` or its owning nested submodule.
- Put public native application APIs in `GeniusSDK`.
- Put Unity bindings and reusable Unity components in `UnityGeniusSDK`.
- Treat `Space-Force-War` as a sample game, not a replacement SDK.
- Treat `GeniusWallet` as the reference Flutter wallet/application, not the owner of native runtime behavior.
- Put trustless token, bridge, lifecycle, settlement, and economic rules in `TokenContracts`.
- Consult `GeniusCognitiveSystem` before creating cognitive routing, memory, agent, tool, verification, EIS, consensus, or ELM infrastructure.
- Put shared native dependency versions and platform builds in `thirdparty`.
- Use `zkLLVM` and `ProofSystem` for their existing proof/compiler responsibilities.

## Before creating anything new

Search the owner repository and its submodules for existing APIs, schemas, classes, tests, examples, plans, and unfinished implementations. State what existing component will be extended.

Do not create a parallel SDK, node network, wallet cryptography layer, token accounting system, Unity wrapper, AI memory format, agent capability system, proof compiler, or dependency bundle merely because the existing implementation is incomplete or inconvenient.

## Submodule workflow

Implement and test in the child repository first. Then update the parent submodule pointer and run integration tests. Never point a parent at an unreviewed or incompatible child commit.

Samples may lag the current ABI. Public headers, protobuf schemas, contract ABIs, pinned commits, and tests are authoritative.
