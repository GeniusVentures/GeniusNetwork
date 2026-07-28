# GeniusNetwork

This is the parent composition repository for the GNUS.ai, Genius, and SuperGenius platform.

## Start here

Before adding a subsystem, SDK, application integration, token feature, cognitive module, dependency, or sample implementation, read:

- **[GNUS.ai Master Platform Architecture](MASTER_ARCHITECTURE.md)** — canonical repository ownership, subsystem map, application/game integration paths, and LLM reuse rules.
- **[Agent Instructions](AGENTS.md)** — mandatory guidance for coding agents and LLMs.
- **[Existing Codebase Architecture](.planning/codebase/ARCHITECTURE.md)** — code-grounded analysis of the pinned repository composition.
- **[Codebase Structure](.planning/codebase/STRUCTURE.md)** — detailed directory and submodule map.

The master architecture explains how `SuperGenius`, `GeniusSDK`, `GeniusWallet`, `TokenContracts`, `thirdparty`, `zkLLVM`, `GeniusCognitiveSystem`, `UnityGeniusSDK`, and `Space-Force-War` are intended to work together.

## Clone the complete platform

Clone recursively so the pinned submodule versions are used:

```bash
git clone --recurse-submodules ssh://git@github.com/GeniusVentures/GeniusNetwork.git
cd GeniusNetwork
```

To initialize or repair submodules in an existing clone:

```bash
git submodule sync --recursive
git submodule update --init --recursive
```

## Requirements

- Python 3.7 or newer
- `tqdm`
- `aiohttp`
- A case-sensitive filesystem is recommended for the native build tree

```bash
python3 -m pip install tqdm aiohttp
```

## Third-party setup

The shared native dependencies are managed through the `thirdparty` submodule. Do not independently vendor duplicate copies into applications or SDK wrappers.

```bash
cd thirdparty
python3 ../util/install_from_github.py config.txt
```

See [INSTALL.md](INSTALL.md) and [ThirdParty_Libraries_Integration.md](ThirdParty_Libraries_Integration.md) for the broader platform setup.

## Repository role

`GeniusNetwork` pins and documents a compatible platform composition. Implement changes in the repository that owns the capability, test there, and then update the appropriate parent submodule pointer.
