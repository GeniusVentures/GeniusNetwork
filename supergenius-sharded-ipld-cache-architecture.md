# SuperGenius Sharded IPLD Cache and Object-Storage Architecture

**Status:** Proposed architecture for planning  
**Date:** October 19, 2026  
**Author:** Justin Church / GNUS.AI working notes  

## Executive summary

The proposed archive should not be integrated into RocksDB as a remote filesystem, SST archive, or storage-engine extension. It should instead be implemented as an application-level, IPFS-like sharded cache for SuperGenius CRDT/IPLD data.

SuperGenius already has the important protocol and data-model pieces:

- IPLD content identifiers (CIDs);
- CRDT convergence and history semantics;
- Graphsync block retrieval;
- libp2p peer networking;
- hierarchical keys whose paths identify accounts and related data.

The missing component is a tiered, content-addressed block store that combines:

1. local caching;
2. peer retrieval;
3. durable object storage through a pluggable backend;
4. path-based shard assignment and discovery;
5. CID verification on every retrieved block.

Sia `s3d` is the recommended first storage backend. SuperGenius can communicate with it using an existing C++ S3 client, initially the MinIO C++ SDK. Other S3-compatible providers should be runtime alternatives, not protocol dependencies.

S5 is a close architectural reference because it separates immutable blobs, mutable signed names, peer networking, and pluggable S3/Sia stores. SuperGenius should study and borrow these design patterns without replacing its existing IPLD identities, CRDT model, Graphsync implementation, or libp2p network.

## Core architectural decision

> Build an IPLD-native, path-sharded block cache using SuperGenius's existing CIDs, Graphsync, libp2p, and CRDT semantics, with S3-compatible durable storage behind a small C++ interface.

This is not a new distributed database. It is a content-addressed storage and retrieval layer.

RocksDB remains useful for hot state, local indexes, cache metadata, and current application state. It is not the remote-storage integration point.

## System model

```text
CRDT / IPLD consumers
        |
        v
+----------------------------+
| SuperGenius BlockService   |
| Get(CID), Put(Block)       |
+-------------+--------------+
              |
              v
+----------------------------+
| Path and shard resolver    |
| path -> CID                |
| path -> responsible nodes  |
+-------------+--------------+
              |
              v
+---------------------------------------------+
| Tiered BlockStore                           |
|                                             |
| 1. memory cache                             |
| 2. persistent local cache/block store       |
| 3. peer retrieval via Graphsync/libp2p      |
| 4. object-storage backend                   |
+----------+-------------------+--------------+
           |                   |
           v                   v
   SuperGenius peers      S3BlockStore
                               |
                    configurable S3 endpoint
                               |
             +-----------------+----------------+
             |                 |                |
             v                 v                v
          Sia s3d       Backblaze B2      Cloudflare R2
```

The object-storage layer should know about CIDs and bytes. It should not know about CRDT merges, account semantics, RocksDB columns, or Graphsync protocols.

## Two identities: path and CID

Each stored item has two relevant identities.

### Logical path

The existing logical path determines namespace, account association, shard ownership, discovery, and mutable naming.

Examples:

```text
/accounts/<account-id>/heads/current
/accounts/<account-id>/objects/<object-id>
/accounts/<account-id>/checkpoints/<sequence>
/accounts/<account-id>/tombstones/<object-id>
/genesis/<network-id>/...
```

### Content identifier

The CID identifies and verifies immutable bytes.

```text
path -> CID -> bytes
```

The two operations should remain separate:

```cpp
Resolve(path) -> CID
Get(CID)      -> bytes
```

A mutable path may point to a new CID over time. The referenced block remains immutable.

## Path-based sharding

Paths already provide a natural shard boundary. Account-related objects can be assigned together by using the stable account portion of the path.

```text
/accounts/<account-id>/**
```

Possible ownership calculation:

```text
owners = RendezvousHash(accountPath, activeCacheNodes, replicationFactor)
```

Rendezvous hashing is preferred over simple modulo hashing because it limits movement when nodes join or leave.

Shard ownership determines:

- which cache nodes are expected to retain or serve an account's data;
- which peers are queried first;
- which nodes maintain path indexes or manifests;
- where repair and rebalancing work is assigned.

Shard ownership does not change the CID. Any node that obtains and verifies a block can cache and serve it.

Genesis, account-discovery data, current heads, and current manifests should be replicated or pinned more aggressively than cold historical blocks.

## Namespace and immutable storage

The namespace and block store are separate layers.

### Namespace layer

Responsible for:

- path-to-CID mappings;
- mutable signed pointers;
- revision ordering;
- account paths;
- shard manifests;
- prefix listing;
- access control and authorization;
- CRDT heads, checkpoints, and tombstone metadata.

### Block layer

Responsible for:

- immutable CID-to-bytes storage;
- CID verification;
- local caching;
- peer retrieval;
- object-store retrieval;
- deduplication;
- durability state.

This is similar to S5's separation of mutable registries and immutable blobs, while retaining SuperGenius's IPLD and networking stack.

## Object-storage key layout

Physical object keys should be derived from CIDs, not application paths.

Example:

```text
v1/blocks/<multicodec>/<prefix>/<cid>
```

Prefix fan-out can help with operational listing, auditing, lifecycle rules, and storage services with partition-sensitive namespaces.

Mutable and aggregate metadata should use separate prefixes:

```text
v1/paths/<shard>/<path-hash>/<revision>
v1/shards/<shard-id>/manifests/<manifest-cid>
v1/registries/<identity>/<sequence>
v1/cars/<car-cid>
v1/car-indexes/<car-cid>
```

The exact S3 key is not authoritative. The CID is authoritative. All retrieved bytes must verify against the requested CID.

## Proposed C++ interfaces

The lowest-level block-store interface should remain small and independent of a particular S3 SDK.

```cpp
struct Block {
  CID cid;
  std::vector<std::byte> bytes;
};

enum class BlockStatus {
  Found,
  NotFound,
  TemporarilyUnavailable,
  Corrupt,
  Unauthorized
};

struct GetBlockResult {
  BlockStatus status;
  std::optional<Block> block;
  std::string diagnostic;
};

class BlockStore {
 public:
  virtual ~BlockStore() = default;

  virtual GetBlockResult Get(
      const CID& cid,
      const ReadOptions& options) = 0;

  virtual bool Has(const CID& cid) = 0;

  virtual PutResult Put(
      const CID& cid,
      std::span<const std::byte> bytes,
      const WriteOptions& options) = 0;

  virtual DeleteResult Remove(const CID& cid) = 0;
};
```

Expected implementations:

```text
MemoryBlockStore
LocalBlockStore
PeerBlockStore
S3BlockStore
TieredBlockStore
CarBlockStore       # possible later optimization
```

The S3 SDK should also sit behind an internal adapter so its types do not leak into the block-store API:

```cpp
class S3Client {
 public:
  virtual PutObjectResult PutObject(...) = 0;
  virtual GetObjectResult GetObject(...) = 0;
  virtual HeadObjectResult HeadObject(...) = 0;
  virtual DeleteObjectResult DeleteObject(...) = 0;
};
```

This makes it possible to change from the MinIO SDK to the AWS SDK for C++, another S3 client, or a native Sia implementation without changing the rest of the cache.

## Read path

A block lookup should follow a configurable tiered policy.

```text
GetBlock(cid, deadline):
    1. Check memory cache.
    2. Check persistent local block cache.
    3. Coalesce concurrent requests for the same CID.
    4. Query selected peers and/or object storage.
    5. Accept the first successful, CID-verified result.
    6. Reject and report corrupt results.
    7. Atomically insert verified bytes into local cache.
    8. Return the block.
```

A useful default may be a staggered race:

```text
t = 0 ms      query the best peer
t = 100 ms    begin object-store request if no peer result
first verified result wins
```

The policy should adapt to observed latency and reliability. Peer-first versus object-store-first should be configurable.

The cache must distinguish among:

- authoritative `NotFound`;
- timeout;
- authentication failure;
- backend outage;
- peer disconnection;
- corrupt content.

Only authoritative absence should be negative-cached, and then only briefly. Transport failures must not become cached `NotFound` results.

## Write and durability path

A normal immutable block write should proceed as follows:

```text
1. Receive bytes and expected CID.
2. Verify that the bytes match the CID.
3. Commit the block to the local persistent store.
4. Queue or begin object-store upload.
5. Optionally announce availability to shard peers.
6. Confirm the required remote durability level.
7. Update the block's durability state.
8. Permit local eviction only after policy is satisfied.
```

The API should distinguish acknowledgment levels:

```cpp
enum class DurabilityLevel {
  LocalCommitted,
  PeerReplicated,
  ObjectStoreAccepted,
  ObjectStoreDurable
};
```

The distinction between `ObjectStoreAccepted` and `ObjectStoreDurable` is important for Sia `s3d`. An acknowledged S3 upload may initially reside in durable local staging before background transfer to Sia. SuperGenius must define which state is sufficient before its own local copy can be evicted.

Core invariant:

> Local bytes must not be evicted until the configured durability policy has been satisfied and recorded.

## Local cache behavior

The local cache should be content-addressed and bounded.

Recommended behaviors:

- separate memory and disk limits;
- high and low watermarks;
- LRU, segmented LRU, or 2Q eviction;
- pinning rules for critical paths and current heads;
- request coalescing for duplicate CID fetches;
- temporary files followed by atomic rename;
- hash verification before publishing a downloaded block;
- asynchronous account or shard prefetch;
- deadline and cancellation support;
- metrics for hit rate, fetch latency, corruption, and eviction.

Example policy:

```text
PIN  /genesis/**
PIN  /accounts/*/heads/**
PIN  /accounts/*/@latest
LRU  /accounts/*/objects/**
TTL  /accounts/*/derived/**
```

Eviction removes only local cached bytes. It does not delete the object from Sia, remove the path-to-CID mapping, or imply a CRDT deletion.

## CRDT correctness requirements

Archiving and cache eviction must not change CRDT semantics.

In particular:

- local eviction is not a logical delete;
- an archived block remains known and retrievable;
- a cache miss must not be interpreted as an absent or unprocessed CRDT operation;
- tombstones cannot be purged merely because they are old;
- current heads must retain access to their required causal history;
- restoration must not resurrect values hidden by later tombstones;
- garbage collection requires a formally defined causal-stability and reachability policy.

Initial versions should avoid permanent deletion of archived CRDT history. Archive garbage collection can be added only after reachability, retention, and tombstone stability are explicitly specified.

## Sia `s3d` as the first backend

Sia `s3d` is a lightweight S3-compatible renter built on the Sia Storage SDK. It is a strong first backend because it already provides:

- an S3-compatible API;
- client-side encryption through the storage SDK;
- background transfer to Sia;
- local upload staging;
- small-object bin packing into Sia slabs;
- erasure coding;
- conditional S3 operations;
- multipart uploads;
- local SQLite metadata;
- upload-pipeline metrics and administrative controls.

Operational implications:

- pending uploads consume local disk;
- the local staging directory is part of the durability path;
- SQLite metadata must be recoverable;
- credentials and configuration must be backed up securely;
- disk-full and low-balance conditions must inhibit eviction;
- SuperGenius must know when an object has merely been staged versus fully transferred;
- crash recovery and loss of the `s3d` machine require explicit tests.

Sia itself should be treated as an actively maintained storage service, not passive offline tape. Its health, repairs, contracts, funding, and local operational state require monitoring.

## C++ S3 client recommendation

Use the MinIO C++ SDK for the initial `S3Client` adapter.

Reasons:

- C++17 support;
- Apache 2.0 licensing for the SDK;
- configurable S3 endpoints;
- ordinary object and multipart operations;
- compatibility with S3-like providers;
- active SDK development as of October 2026.

The status of the MinIO community server is separate from the status of the MinIO C++ client repository. SuperGenius would use only the client SDK.

Alternative:

- AWS SDK for C++ with a configurable endpoint.

Future possibility:

- Apache OpenDAL if its C++ binding becomes production-ready.

## S5 as an architectural reference

S5 is unusually close to the desired design. It provides:

- immutable content-addressed blobs;
- mutable signed registries;
- versioned content-addressed directories;
- peer blob exchange;
- local, memory, S3, and Sia storage backends;
- a storage abstraction that treats external stores as first-class backends.

SuperGenius should inspect S5 for:

- store interfaces;
- separation of mutable names from immutable data;
- signed registry/version behavior;
- backend composition;
- peer and backend fallback behavior;
- location metadata;
- recovery and verification patterns.

SuperGenius should not adopt S5 wholesale because it already has equivalent protocol foundations. S5 uses BLAKE3-based blob identities and Iroh/QUIC networking, whereas SuperGenius already uses IPLD CIDs, Graphsync, libp2p, and its existing CRDT protocol.

The intended approach is:

> Borrow S5's separation of immutable blobs, mutable names, peer transport, and pluggable storage. Do not replace SuperGenius's identities, network stack, or CRDT semantics.

## CARv2 packing

The first implementation should store one IPLD block per S3 object:

```text
one CID block -> one S3 object
```

Sia `s3d` already packs small uploads into storage slabs. Adding another packing layer before measuring the system would increase complexity without proving a need.

Measure first:

- PUT throughput;
- GET and HEAD latency;
- SQLite metadata growth;
- object-count behavior;
- pending-upload disk usage;
- provider request costs;
- recovery after loss or restart;
- byte-range performance;
- time between S3 acknowledgment and durable Sia transfer.

If per-CID objects create excessive metadata or request overhead, add IPLD CARv2 as a later optimization. CARv2 provides an optional index for random CID-level access.

A CAR locator would resemble:

```text
CID -> {
    car_object_key,
    offset,
    length,
    codec
}
```

CAR compaction should be asynchronous. Individual CID objects should remain available until the CAR file and its index have been committed and verified.

Sia's slab packing and CARv2 solve different problems:

- Sia packing reduces wasted storage inside slabs;
- CARv2 can reduce S3 object count, request count, and metadata overhead.

Benchmarks should determine whether both are needed.

## Example runtime configuration

```yaml
archive:
  enabled: true

  object_store:
    type: s3
    endpoint: https://s3d.internal.example
    region: us-east-1
    bucket: supergenius-archive
    key_prefix: v1/
    path_style: true
    tls_verify: true

  retrieval:
    peer_enabled: true
    peer_head_start_ms: 100
    object_store_enabled: true
    request_timeout_ms: 30000
    verify_cid: true
    coalesce_requests: true

  cache:
    memory_mb: 512
    disk_path: /var/lib/supergenius/block-cache
    disk_size_gb: 30
    high_watermark: 0.85
    low_watermark: 0.70

  durability:
    remote_required_before_eviction: true
    minimum_peer_replicas: 0

  packing:
    mode: individual       # individual | carv2
    target_car_size_mb: 128
```

Credentials should come from environment variables, protected secret files, or an external secret manager rather than the main configuration file.

## Ops runbook: cold-journal backup posture (M3, decided Phase 7 v1.1)

**Decision origin:** rocksdb-backup workstream Phase 7 decisions D-09/D-10
(2026-10-23). The Phase-11 planner inherits this section as the locked
posture.

**The cold journal is rebuildable and is NOT backed up.** The spill journal
(Phase 8) is a pending-upload worklist, not a source of truth: S3 is the
system of record for cold data, and the journal can always be reconstructed
from a CID-verified comparison of what the hot store holds against what the
remote listing says is already durably stored. Keeping it out of the backup
set adds zero backup-engine surface (consistent with this milestone's
out-of-scope boundary on the GlobalDB backup path).

**Recovery sequence, in order:**

1. **Re-drain the journal as-is first.** Where the journal survived intact
   alongside a restored GlobalDB, the ordinary drain loop replays it — no
   rebuild needed.
2. **Where divergence is suspected** (a restored GlobalDB older than the
   journal, or a journal gap): rebuild via a **CID-verified diff** of
   hot-store CIDs vs the S3 remote listing (HEAD per object), then re-put
   the missing objects using the library's idempotent create-only Put.
3. **Re-journal the diff** so the normal drain loop resumes from a
   consistent state.

This relies on the sgns-blockstore library's idempotent `createOnly` +
CID-verify contracts. **The rebuild tooling itself lands in Phase 11**
(with GC, which is its consumer); no code ships in Phase 7 — this section
is the recorded posture.

**Credential handling for server deployments:** source
`SGNS_BLOCKSTORE_S3_ACCESS_KEY` / `SGNS_BLOCKSTORE_S3_SECRET_KEY` from the
environment (secret injection) rather than writing them into
`crdt_config.json`. Environment values override the file's credential
values but never activate the integration — the `blockstore` config section
is the only activation switch (blank or absent section = cold storage
disabled, behavior identical to today).

## Recommended implementation phases

### Phase 1: block-store abstraction

- Identify the current SuperGenius block retrieval and insertion boundaries.
- Define `BlockStore`, `ReadOptions`, `WriteOptions`, and result/error types.
- Wrap the existing local block store.
- Add CID verification tests.
- Add a memory-backed implementation for deterministic tests.

### Phase 2: S3 backend

- Implement the internal `S3Client` adapter using the MinIO C++ SDK.
- Implement `S3BlockStore` with direct CID-to-object mapping.
- Test against a local S3-compatible test service and Sia `s3d`.
- Add conditional writes or idempotent object handling.
- Add metrics, deadlines, retries, and structured errors.

### Phase 3: tiered retrieval and caching

- Implement `TieredBlockStore`.
- Integrate the existing Graphsync/libp2p retrieval path as `PeerBlockStore`.
- Add persistent read-through caching.
- Add request coalescing.
- Add configurable peer-first, S3-first, and staggered-race policies.
- Verify all fetched bytes before caching or returning them.

### Phase 4: path sharding

- Define the canonical normalized account path used for ownership.
- Implement rendezvous shard assignment.
- Define replication and pinning rules.
- Add shard manifests or signed path registries.
- Add rebalancing, repair, and account prefetch.

### Phase 5: durability and safe eviction

- Model local, peer, staged-object, and durable-object states.
- Determine the exact `s3d` durability acknowledgment mechanism.
- Prevent eviction until policy is satisfied.
- Add failure injection for crashes during upload and state transitions.
- Add audit and repair jobs.

### Phase 6: performance optimization

- Benchmark realistic CRDT object sizes and daily object volumes.
- Measure Sia `s3d` metadata and upload-pipeline behavior.
- Measure byte-range reads.
- Add CARv2 packing only if measurements justify it.
- Tune cache size, shard replication, and fetch racing.

## Initial acceptance criteria

The first production-capable version should demonstrate that:

1. A block written locally can be persisted through the S3 backend.
2. The local copy can be removed only after the required durability state is confirmed.
3. A fresh node can retrieve the block by CID from Sia `s3d`.
4. Retrieved bytes are verified against the CID.
5. Concurrent requests for the same CID produce one backend fetch.
6. Backend timeouts do not become `NotFound` results.
7. Corrupt responses are rejected and attributed to their source.
8. Existing Graphsync retrieval continues to function.
9. Path resolution and CRDT semantics remain unchanged.
10. Loss and restart of SuperGenius and `s3d` components have documented recovery behavior.

## Key risks

### Durability-state ambiguity

An S3 PUT acknowledged by `s3d` may represent local staging rather than completed Sia transfer. Eviction policy must not assume more durability than `s3d` actually guarantees.

### Small-object metadata scale

Tens of millions of CID objects may stress SQLite metadata, listing operations, request costs, or recovery time even if Sia packs their bytes efficiently.

### CRDT history deletion

Treating old or locally evicted blocks as deleted could break convergence, Graphsync serving, causal reconstruction, or tombstone semantics.

### Mutable namespace consistency

Path-to-CID updates require signed revisions, monotonic ordering, and conflict handling. Object immutability alone does not solve mutable-name consistency.

### Peer/backend retry storms

A failed backend or unavailable shard could cause many simultaneous retries. Request coalescing, backoff, circuit breakers, and bounded concurrency are required.

### Operational dependency on Sia services

The Sia renter, local metadata, staging disk, credentials, contracts, funding, and repair processes all become part of the operational system.

## Open design questions

1. What existing SuperGenius class currently owns `CID -> bytes` retrieval?
2. Which exact portion of a logical key path is stable enough to define shard ownership?
3. Are paths already signed or versioned, or is a new mutable-registry record required?
4. Should peer retrieval race S3 immediately, use a delay, or follow observed source quality?
5. What `s3d` signal proves that staged data has been durably transferred to Sia?
6. What replication level is required before local eviction?
7. Which paths must always be pinned locally?
8. How are access controls applied when physical object keys are CID-derived?
9. Does the existing Graphsync layer already support serving blocks restored from a fallback block store?
10. What are the expected block-size distribution, blocks per day, and read-recurrence distribution?
11. Is prefix listing required for normal operation, or can all enumeration come from manifests?
12. How will manifests, path registries, and durability metadata be backed up and reconstructed?
13. What formal condition eventually permits permanent CRDT-history garbage collection?

## Planning recommendation

Begin with the smallest end-to-end vertical slice:

```text
existing SuperGenius block API
        -> BlockStore abstraction
        -> local cache
        -> MinIO C++ S3 adapter
        -> Sia s3d
        -> retrieve by CID
        -> verify CID
```

Do not begin with RocksDB filesystem integration, a new distributed database, CAR packing, or permanent history deletion.

Once the direct CID path is reliable, add Graphsync fallback/racing, path-based shard assignment, signed manifests, durability accounting, and safe eviction.

## Relevant references

- S5 Rust implementation: <https://github.com/s5-dev/s5-rs>
- Sia `s3d`: <https://github.com/SiaFoundation/s3d>
- Sia `renterd`: <https://github.com/SiaFoundation/renterd>
- Sia API documentation: <https://api.sia.tech/>
- MinIO C++ SDK: <https://github.com/minio/minio-cpp>
- AWS SDK for C++: <https://github.com/aws/aws-sdk-cpp>
- Apache OpenDAL: <https://opendal.apache.org/>
- IPLD CARv2 specification: <https://ipld.io/specs/transport/car/carv2/>
- IPFS Cluster: <https://github.com/ipfs-cluster/ipfs-cluster>

## One-sentence architecture

> SuperGenius will retain its current CRDT, IPLD, Graphsync, and libp2p architecture while adding a path-sharded, tiered CID block cache whose durable layer is a pluggable S3-compatible object store, initially Sia `s3d` accessed through a small C++ adapter.
