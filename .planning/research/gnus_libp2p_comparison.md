# GNUS libp2p and IPFS Stack Comparison

**Review date:** October 12, 2026  
**Scope:** GeniusVentures/libp2p and supporting Bitswap, PubSub, and IPFS Lite libraries compared with upstream cpp-libp2p and Go libp2p/IPFS implementations.

## Executive summary

The criticism in [cpp-libp2p issue #351](https://github.com/libp2p/cpp-libp2p/issues/351) only partly applies to the GNUS fork. The GNUS C++ stack has substantial additional networking and IPFS functionality, but Go remains broader in transport support, protocol maturity, interoperability, and production validation. This review is based on source and repository inspection, not a complete build, runtime benchmark, or security audit.

## Fork status

- Fork lineage: `libp2p/cpp-libp2p` → `eigendude/libp2p` → `GeniusVentures/libp2p`.
- At review time, the GNUS master branch was reported as **415 commits ahead and 81 behind** upstream master. Commit counts do not directly measure quality.
- GNUS adds connection gating, private-network controls, AutoNAT, relay, and hole-punching code.
- Upstream C++ has QUIC and WebSocket code not present in the reviewed GNUS fork.

## Core feature comparison

| Capability | GNUS C++ | Upstream C++ | Go libp2p |
|---|---|---|---|
| TCP | Yes | Yes | Yes |
| Noise | Yes | Yes | Yes |
| Yamux | Yes | Yes | Yes |
| Kademlia DHT | Yes | Yes | Yes |
| GossipSub | Yes | Yes | Yes |
| AutoNAT | v1-era implementation | No matching module found | Yes, including v2 |
| Relay | Custom implementation | No matching module found | Circuit Relay v2 |
| Hole punching | Custom implementation | No matching module found | DCUtR |
| Connection gating | Five-stage interface | No matching module found | Yes |
| PSK private networks | Yes | No matching module found | Yes |
| QUIC | Not found | Code present | Yes |
| WebSocket/WSS | Not found | Code present | Yes |
| WebTransport | Not found | Not found | Yes |
| WebRTC Direct | Not found | Not found | Yes |
| Full resource manager | Partial controls | No comparable full manager found | Mature framework |

**Caution:** “Code present” does not necessarily mean a feature is enabled, complete, interoperable, or production-tested.

## Bitswap comparison

Repository: [GeniusVentures/ipfs-bitswap-cpp](https://github.com/GeniusVentures/ipfs-bitswap-cpp). Go reference: [IPFS Boxo Bitswap](https://github.com/ipfs/boxo/tree/main/bitswap).

| Capability | GNUS Bitswap | Go/Boxo |
|---|---|---|
| Basic block request/serve | Yes | Yes |
| UnixFS file/directory handling | Yes | Available through IPFS libraries |
| Chunked publishing | Yes, 256 KB chunks | Yes, configurable |
| Multiple providers | Application-managed | Broader session/routing support |
| Retries and timeouts | Yes | Yes |
| Persistent block storage | Yes on develop | Yes |
| Bitswap 1.0 | Yes | Yes |
| Bitswap 1.1/1.2 | Not implemented in active handler | Yes |
| CIDv1 block responses | Not supported in active v1.0 handling path | Yes |
| Want-Have/Dont-Have | Protobuf fields exist; full handling not found | Yes |
| Complete multi-peer session scheduling | Not found | Yes |
| Cross-language interoperability tests | Not established | Broad ecosystem coverage |

See the [Bitswap protocol specification](https://specs.ipfs.tech/bitswap-protocol/).

### Source-review concerns

1. **Canceled timers treated as timeouts.** In [bitswap.cpp lines 70–99](https://github.com/GeniusVentures/ipfs-bitswap-cpp/blob/develop/src/bitswap.cpp#L70-L99), the timer callback reportedly ignores the cancellation error. Boost.Asio can call canceled handlers with `operation_aborted`, potentially causing false failures. Verify against the integrated commit and add a regression test.
2. **Callbacks invoked under mutex.** `BitswapRequestContext::HandleResponse()` reportedly calls consumers while holding `mutex_`, creating a potential deadlock if callbacks reenter code requiring the lock. Move callbacks outside the critical section and test reentrancy.

These are source-level concerns, not reproduced runtime failures.

## PubSub and GossipSub

Repository: [GeniusVentures/ipfs-pubsub](https://github.com/GeniusVentures/ipfs-pubsub).

The GNUS wrapper adds discovery, subscriptions, batching, address monitoring, private-network setup, and runtime peer blocking. Its `DenyListConnectionGater` exposes `BlockPeer()` and `UnblockPeer()`.

However, the underlying GossipSub implementation defaults to `/meshsub/1.0.0`; GossipSub 1.1 behavior and signed peer records were not found as completed implementations. Peer blocking is not equivalent to behavior-based peer scoring.

The reviewed code also documents unfinished bounds for remote subscription tables and outbound buffered messages, potentially allowing excess memory use from untrusted or slow peers:

- [GossipSub configuration](https://github.com/GeniusVentures/libp2p/blob/master/include/libp2p/protocol/gossip/gossip.hpp#L87-L90)
- [Message parser](https://github.com/GeniusVentures/libp2p/blob/master/src/protocol/gossip/impl/message_parser.cpp#L98)
- [Connection denylist](https://github.com/GeniusVentures/ipfs-pubsub/blob/main/src/ipfs_pubsub/deny_list_connection_gater.hpp)
- [Remote subscription TODO](https://github.com/GeniusVentures/libp2p/blob/master/src/protocol/gossip/impl/remote_subscriptions.hpp#L75-L77)
- [Outbound stream buffer TODO](https://github.com/GeniusVentures/libp2p/blob/master/src/protocol/gossip/impl/stream.hpp#L64-L70)

## IPFS Lite and Graphsync

Repository: [GeniusVentures/ipfs-lite-cpp](https://github.com/GeniusVentures/ipfs-lite-cpp).

The combined GNUS C++ stack includes Graphsync request/response handling, IPLD/CID facilities, DHT integration, RocksDB storage, and block services. These make it much more functional than core upstream cpp-libp2p alone. They do **not** establish full compatibility with Kubo or all Go IPFS behavior without interoperability tests.

## Integrated dependency versions

The review traced GeniusNetwork through its `thirdparty` submodule references:

| Library | Integrated commit | Note |
|---|---|---|
| libp2p | `10166f9c` | Reportedly 4 commits behind master |
| ipfs-bitswap-cpp | `d2ec18af` | Matches develop, not master |
| ipfs-lite-cpp | `0b6f1a59` | Matches develop |
| ipfs-pubsub | `b9f051f8` | Older than main |

Reference: [Selected thirdparty tree](https://github.com/GeniusVentures/thirdparty/tree/54e06375d130cb359f246d96168321bd898eb5e2).

Findings from branch tips should be rechecked against these pinned commits before filing bugs or claiming a fix is deployed.

## Testing and CI

At the review date, recent GNUS libp2p GitHub Actions runs for CI, coverage, and Clang-Tidy had failed:

- [CI run](https://github.com/GeniusVentures/libp2p/actions/runs/37839718840)
- [Coverage run](https://github.com/GeniusVentures/libp2p/actions/runs/37839718977)
- [Clang-Tidy run](https://github.com/GeniusVentures/libp2p/actions/runs/37839718895)

The observed failures involved Python environment/package setup, so they are **not evidence of C++ compilation failure**. Separately, the project's [deferred-items report](https://github.com/GeniusVentures/libp2p/blob/master/.planning/phases/03-hardening-live-validation-documentation/deferred-items.md) documents outdated mocks and test-build problems. Its [verification report](https://github.com/GeniusVentures/libp2p/blob/master/.planning/phases/03-hardening-live-validation-documentation/03-VERIFICATION.md) reports passing targeted tests but not a clean comprehensive test suite.

## Recommended priorities

| Priority | Action | Reason |
|---|---|---|
| P0 | Restore CI and full test builds | Establish reproducible baseline |
| P0 | Audit/fix Bitswap cancellation and callbacks under locks | Prevent false failures and deadlocks |
| P0 | Bound GossipSub queues, subscriptions, and per-peer memory | Reduce resource-exhaustion risk |
| P1 | Test GNUS ↔ Go interoperability | Verify actual protocol compatibility |
| P1 | Test relay, NAT traversal, and reconnection in real network conditions | Validate edge-node reachability |
| P1 | Implement Bitswap 1.2, CIDv1, Want-Have/Dont-Have | Improve public IPFS interoperability |
| P2 | Evaluate selective upstream QUIC/WebSocket integration | Expand connectivity |
| P2 | Benchmark CPU, throughput, latency, and memory against Go | Quantify performance differences |

## Conclusion

**Compared with upstream C++:** GNUS has meaningful additional functionality, particularly connection gating, private networking, discovery, relay, and its supporting IPFS libraries. It is not simply the original, less-featured cpp-libp2p.

**Compared with Go:** Go remains the safer general-purpose recommendation for heterogeneous, untrusted production P2P networks due to broader transport support, protocol maturity, and ecosystem validation.

**For GNUS:** Retaining C++ is reasonable. A rewrite in Go is not justified merely by the linked issue. Prioritize demonstrable correctness, bounded resource use, cross-language interoperability, and reproducible tests. The source review alone does not establish that GNUS is faster, more stable, or more secure than Go.
