# Phase 3: GossipSub Resource Bounds - Pattern Map

**Mapped:** 2026-10-13
**Files analyzed:** 14 (12 modified, 2 created)
**Analogs found:** 14 / 14 (13 exact/in-file precedents, 1 partial — the raw gossip-speaking fixture)

**Tracked-source gate (#3645):** every analog below verified via `git ls-files` inside its submodule (libp2p @ `28f6a629`, ipfs-pubsub @ `b6eb6268`, ipfs-bitswap-cpp @ HEAD `f899393` of `dev_timer_correctness`, SuperGenius). All printed as tracked. One caveat: `thirdparty/ipfs-bitswap-cpp/test/bitswap_request_timer_race_test.cpp` is tracked at HEAD but **deleted from the working tree** (pre-Phase-3 anomaly, RESEARCH Pitfall 7) — excerpts below were pulled via `git show HEAD:` and are for convention reference only; do not attempt to read it from disk.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `thirdparty/libp2p/include/libp2p/protocol/gossip/gossip.hpp` — Config knobs (D-01/D-02) + `setViolationHandler` (D-08) | config + interface | n/a (defaults) / callback registration | itself: existing `Config` fields L86-93; `Validator`/`MessageIdFn` typedef+setter pairs L137-148 | exact (in-file) |
| `thirdparty/libp2p/src/protocol/gossip/impl/common.hpp` — `Error::PENDING_OVERFLOW` (new enum value) | utility | n/a (error codes) | same file: `Error` enum L17-29 | exact (in-file) |
| `thirdparty/libp2p/src/protocol/gossip/impl/common.cpp` — category case for new error | utility | n/a | same file: `OUTCOME_CPP_DEFINE_CATEGORY` switch L11-38 | exact (in-file) |
| `thirdparty/libp2p/src/protocol/gossip/impl/remote_subscriptions.cpp` — per-peer cap in `onPeerSubscribed` (D-03) + D-04 marker | service (protocol state table) | event-driven (ingress callbacks) | same file: dedup early-return L41-59; sweep L165-178 | exact (in-file) |
| `thirdparty/libp2p/src/protocol/gossip/impl/stream.hpp` — admission members + `SubLogger&` | component (egress writer) | streaming (byte queue) | same file: `pending_bytes_` TODO L64-70; ctor config-copy in stream.cpp L20-33 | exact (in-file) |
| `thirdparty/libp2p/src/protocol/gossip/impl/stream.cpp` — admission check + K-counter + close (D-05/D-06/D-07) | component (egress writer) | streaming | same file: `write()` L128-149; `onLengthRead` size precedent L74-77; `asyncPostError` L212-219 | exact (in-file) |
| `thirdparty/libp2p/src/protocol/gossip/impl/connectivity.hpp` — violation-handler storage/forward | controller (connection orchestration) | event-driven | same file: `ConnectionStatusFeedback`/`connected_cb_` ctor-injected callback L41-48, L104 | exact (in-file) |
| `thirdparty/libp2p/src/protocol/gossip/impl/connectivity.cpp` — emission in `onStreamEvent`; Stream ctor wiring | controller | event-driven | same file: `onStreamEvent` + v1.1 TODO L414-428; 2 Stream construction sites (below) | exact (in-file) |
| `thirdparty/libp2p/src/protocol/gossip/impl/gossip_core.hpp` — handler member + override | service (protocol core; implements `Gossip`) | pub-sub | same file: `MessageIdFn create_message_id_` member L127 area | exact (in-file) |
| `thirdparty/libp2p/src/protocol/gossip/impl/gossip_core.cpp` — store handler; forward to `Connectivity` at `start()` | service | pub-sub | same file: `setMessageIdFn` impl L169-172; `start()` Connectivity creation L126-136 | exact (in-file) |
| `thirdparty/ipfs-pubsub/src/ipfs_pubsub/gossip_pubsub.hpp` — registration + close-counter members | service (app wiring) | event-driven | same file: BlockPeer family decls L106-131 | exact (in-file) |
| `thirdparty/ipfs-pubsub/src/ipfs_pubsub/gossip_pubsub.cpp` — register handler after gossip create (D-08); Nth-close → `BlockPeer()` (D-09/D-10) | service | event-driven | same file: gossip create L301-307; BlockPeer family L237-263 | exact (in-file) |
| `thirdparty/ipfs-pubsub/test/src/gossip_pubsub_bounds_test.cpp` (NEW — name discretionary) | test | pub-sub + request-response | `test/src/gossip_pubsub_test.cpp` (fixture, config-via-ctor, distinct ports, bounded waits) + `SuperGenius/test/src/pubsub_counts/pubsub_counts.cpp` (raw-host/ephemeral-port/`ASSERT_WAIT_FOR_CONDITION`) | exact for (a)/(c); partial for (b) raw fixture |
| `thirdparty/ipfs-pubsub/test/src/CMakeLists.txt` — register new test source | config (build) | n/a | same file: existing `addtest(...)` entry L1-4 | exact (in-file) |

Line anchors: libp2p gossip.hpp/common.* anchors counted from full-file reads this session; `remote_subscriptions`/`stream`/`connectivity`/`gossip_core` anchors cross-checked against 03-RESEARCH.md's verified reads at the pinned SHAs; ipfs-pubsub anchors verified against RESEARCH + fresh reads. Treat all anchors as `≈` — navigate by symbol when editing.

## Pattern Assignments

### 1. `thirdparty/libp2p/include/libp2p/protocol/gossip/gossip.hpp` (config + interface)

**Analog:** the same file — existing scalar-with-doc-comment `Config` fields, and the typedef-then-virtual-setter pairs on `Gossip`.

**Config knob pattern** (L86-93 — new knobs follow this style verbatim; insert adjacent to `max_message_size` since D-02 derives its default from it):
```cpp
    /// Max RPC message size
    size_t max_message_size = 1 << 24;

    /// Protocol version
    std::string protocol_version = "/meshsub/1.0.0";

    /// Sign published messages
    bool sign_messages = false;
```
Add (D-01/D-02): `size_t max_remote_subscriptions_per_peer = ...;`, `size_t max_pending_bytes_per_stream = 1 << 24;` (mirrors `max_message_size` default per D-02), `size_t overflow_close_threshold = 8;` (K; A1 in RESEARCH). Same `size_t` + `///` doc + default style. Note existing naming: suffix conventions `_num` (`max_connections_num`), `_msec`, `_limit` (`seen_cache_limit`) — the D-01 knob names are locked by decision; no rename.

**Setter-on-interface pattern** (L137-148 — `setViolationHandler` copies this shape: typedef above the class, setter below, `std::function` payload):
```cpp
    /// Validator of messages arriving from the wire
    using Validator = std::function<bool(const ByteArray &from, const ByteArray &data)>;

    /// Sets message validator for topic
    virtual void setValidator(const TopicId &topic, Validator validator) = 0;

    /// Creates unique message ID out of message fields
    using MessageIdFn = std::function<ByteArray(
        const ByteArray &from, const ByteArray &seq, const ByteArray &data)>;

    /// Sets message ID funtion that differs from default (from+sec_no)
    virtual void setMessageIdFn(MessageIdFn fn) = 0;
```
RESEARCH recommends `using ViolationHandler = std::function<void(const peer::PeerId &, ViolationType)>;` + `virtual void setViolationHandler(ViolationHandler) ` — pure virtual is in-convention (every method here is pure; `GossipCore` is the only implementer in-tree per RESEARCH verification). Place the `ViolationType` enum (or nest inside `Gossip`) next to the typedef. **Style:** 2-space indent, no space inside parens, trailing-underscore members — libp2p local style, NOT the ipfs-pubsub style.

---

### 2/3. `thirdparty/libp2p/src/protocol/gossip/impl/common.hpp` + `common.cpp` (error enum)

**Analog:** same files — the `Error` enum and its outcome category. One new value, one new case; RESEARCH verified no other switch over `Error` exists and the category switch is `default:`-guarded, so the addition is compile-safe.

**Enum** (common.hpp L17-29):
```cpp
  /// Error codes
  enum class Error {
    MESSAGE_PARSE_ERROR = 1,
    MESSAGE_SIZE_ERROR,
    MESSAGE_SERIALIZE_ERROR,
    MESSAGE_WRITE_ERROR,
    READER_DISCONNECTED,
    WRITER_DISCONNECTED,
    READER_TIMEOUT,
    WRITER_TIMEOUT,
    CANNOT_CONNECT,
    VALIDATION_FAILED
  };
```
Append `PENDING_OVERFLOW` (naming discretionary; must read as "sustained outbound overflow" — it is what the violation dispatch checks in `onStreamEvent`).

**Category case** (common.cpp L11-38 — add one `case E::PENDING_OVERFLOW: return "...";` before `default:`):
```cpp
OUTCOME_CPP_DEFINE_CATEGORY(libp2p::protocol::gossip, Error, e) {
  using E = libp2p::protocol::gossip::Error;
  switch (e) {
    ...
    case E::VALIDATION_FAILED:
      return "validation failed";
    default:
      break;
  }
  return "unknown error";
}
```
(Pre-existing wart, do not fix: `WRITER_TIMEOUT` already returns the wrong string `"stream writer disconnected"`.)

---

### 4. `thirdparty/libp2p/src/protocol/gossip/impl/remote_subscriptions.cpp` (subscription cap, D-03 + D-04 marker)

**Analog:** same file — `onPeerSubscribed`'s existing dedup early-return is the exact shape of the new cap early-return (log + `return` before any table mutation, under `table_mutex_` discipline).

**Core pattern — the choke point** (L41-59; RESEARCH Pattern 1):
```cpp
  void RemoteSubscriptions::onPeerSubscribed(const PeerContextPtr &peer,
                                             const TopicId &topic) {
    if (!peer->subscribed_to.insert(topic).second) {
      // request from wire, already subscribed, ignoring double subscription
      log_.debug("peer {} already subscribed to {}", peer->str, topic);
      return;
    }
    log_.debug("peer {} subscribing to {}", peer->str, topic);
    // ← CAP CHECK (D-03). RESEARCH resolves the ordering: check
    //    `peer->subscribed_to.size() >= config_.max_remote_subscriptions_per_peer`
    //    BEFORE the dedup insert (check-then-insert), so the count reflects
    //    admitted subscriptions only. On violation: log_.warn(peer, topic,
    //    count, cap) GOSS-04 + return — never mutate the table.
    std::lock_guard<std::mutex> lock(table_mutex_);
    auto res = getItem(topic, true);
    ...
```
Counting placement is resolved (RESEARCH): computed via `peer->subscribed_to.size()` — it is a `std::set<TopicId>` (`peer_context.hpp` ~L31-32); do NOT add a parallel counter (drift bug). `config_` member already exists in this class (ctor stores it) — zero new wiring.

**D-04 sweep — marker only, no new code** (L165-178 already implements it):
```cpp
  void RemoteSubscriptions::onHeartbeat() {
    std::lock_guard<std::mutex> lock(table_mutex_);
    auto now = scheduler_.now();
    for (auto it = table_.begin(); it != table_.end();) {
      it->second.onHeartbeat(now);
      if (it->second.empty()) {
        // fanout interval expired - clean up
        log_.debug("deleted entry for topic {}", it->first);
        it = table_.erase(it);
      } else { ++it; }
    }
  }
```
`TopicSubscriptions::empty()` (~topic_subscriptions.cpp L43-47) already encodes D-04's safety condition ("not self-subscribed, no fanout, no subscribed peers, no mesh peers"). A capped-out subscription never inserts into `subscribed_to`/`subscribed_peers_`, so the topic stays empty and is collected. Action: replace the stale in-file TODO at `remote_subscriptions.hpp` L75-77 (`// TODO(artem): bound table size (which may grow!)`) with a `GOSS-01` marker comment documenting cap+sweep composition. Graft-safety evidence: `topic_subscriptions.cpp` L198-210 (`onGraft` only promotes peers already in `subscribed_peers_` or first admits them as subscribers).

**Logging pattern (GOSS-04):** copy the existing fmt discipline — values as data, `{}` placeholders only (log-injection mitigation per RESEARCH security table):
```cpp
log_.debug("peer {} already subscribed to {}", peer->str, topic);
```

---

### 5/6. `thirdparty/libp2p/src/protocol/gossip/impl/stream.hpp` + `stream.cpp` (admission cap + K-drops close)

**Analog:** same files — three in-file precedents: (a) the ingress size bound in `onLengthRead`, (b) the early-return ladder at the top of `write()`, (c) `asyncPostError`'s scheduler+`weak_from_this` dispatch.

**(a) Bounds-check precedent** (stream.cpp ~L74-77 — the existing V5 "input validation" pattern; the new egress check is its mirror):
```cpp
    if (msg_len > max_message_size_) {
      feedback_(peer_, Error::MESSAGE_SIZE_ERROR);
      return;
    }
```

**(b) Admission slot** (stream.cpp L128-149 — RESEARCH Pattern 2; check goes after the empty-buffer guard, before the pending/beginWrite fork):
```cpp
  void Stream::write(outcome::result<SharedBuffer> serialization_res) {
    if (closed_) { return; }
    if (stream_->isClosedForWrite()) { asyncPostError(Error::WRITER_DISCONNECTED); return; }
    if (!serialization_res) { asyncPostError(Error::MESSAGE_SERIALIZE_ERROR); return; }
    auto &buffer = serialization_res.value();
    if (buffer->empty()) { return; }
    // ← ADMISSION CHECK (D-05/D-07): if (pending_bytes_ + buffer->size()
    //    > max_pending_bytes_) → log (peer, bytes, pending, cap) GOSS-04,
    //    consecutive_overflow_drops_++, if >= K → close() then
    //    asyncPostError(Error::PENDING_OVERFLOW); return (drop-new-only).
    if (writing_bytes_ > 0) {
      pending_bytes_ += buffer->size();
      pending_buffers_.emplace_back(std::move(buffer));
    } else {
      beginWrite(std::move(buffer));
    }
  }
```

**(c) Async close/error dispatch** (stream.cpp L212-219 — the K-th-drop error MUST go through this, never inline `feedback_` from `write()`):
```cpp
  void Stream::asyncPostError(Error error) {
    scheduler_.schedule([this, self_wptr = weak_from_this(), error] {
      if (self_wptr.expired() || closed_) {
        return;
      }
      feedback_(peer_, error);
    });
  }
```
Ordering note: `close()` first (sets `closed_`, `endWrite()`, `stream_->reset()`), then post — or the `closed_` guard above swallows the error. Executor must reconcile this explicitly (assert in test will catch it).

**Counter-reset site (D-06 "resets on drain")** — stream.cpp L204-210; add an `else` branch where the queue is found drained:
```cpp
    if (!pending_buffers_.empty()) {
      SharedBuffer &buffer = pending_buffers_.front();
      pending_bytes_ -= buffer->size();
      beginWrite(std::move(buffer));
      pending_buffers_.pop_front();
    }
    // ← else { consecutive_overflow_drops_ = 0; }  — full drain resets (D-06);
    //   do NOT reset on mere admission (would break a still-overflowing streak).
```
Accounting fact the check relies on (verified): `pending_bytes_` counts only queued bytes (decremented at pop, L206); in-flight bytes live in `writing_bytes_` (zeroed by `endWrite()`, L224-227). So `pending_bytes_ + incoming > cap` is exactly "queued backlog would exceed cap".

**Header members** (stream.hpp — replace the TODO at L64-70, keep its spirit in the doc comment):
```cpp
    // TODO(artem): limit pending bytes and close slow streams that way   ← replace
    size_t pending_bytes_ = 0;
```
becomes `pending_bytes_` + `const size_t max_pending_bytes_;` + `size_t consecutive_overflow_drops_ = 0;` + `log::SubLogger &log_;`.

**Ctor config-copy pattern** (stream.cpp L20-33 — new fields flow exactly like `max_message_size_`):
```cpp
      : stream_id_(stream_id),
        timeout_(config.rw_timeout_msec),
        scheduler_(scheduler),
        max_message_size_(config.max_message_size),
        // ← add: max_pending_bytes_(config.max_pending_bytes_per_stream),
        feedback_(feedback),
        ...
```
GOSS-04 gap (RESEARCH): `Stream` has NO logger member today (TRACE-only via `libp2p/common/trace.hpp`). Add `log::SubLogger &log_` ctor param — reference-passed like `RemoteSubscriptions`' `log_` (deps-by-ref is this class's documented design, see ctor comment in stream.hpp). **Both** construction sites must be updated — see connectivity below.

---

### 7/8. `thirdparty/libp2p/src/protocol/gossip/impl/connectivity.hpp` + `connectivity.cpp` (violation emission + Stream wiring)

**Analog:** same files — the error funnel `onStreamEvent → banOrForget` (with the in-file TODO that anticipated exactly this work), and the two `Stream` construction sites.

**Emission site** (connectivity.cpp L414-428 — RESEARCH Pattern 3):
```cpp
  void Connectivity::onStreamEvent(const PeerContextPtr &from,
                                   outcome::result<Success> event) {
    if (!started_) { return; }
    if (event) { return; }
    // TODO(artem): ban incoming peers for protocol violations etc. - v.1.1
    banOrForget(from);
    // ← VIOLATION EMISSION (D-08): if handler set && event.error() ==
    //    Error::PENDING_OVERFLOW → invoke handler(from->peer_id, type).
    //    Order vs banOrForget: handler after banOrForget keeps cleanup
    //    unconditional; handler must be exception-safe and cheap.
  }
```
`banOrForget` (L362-395) already does the full teardown (closes streams, erases connected/connectable sets, `connected_cb_(false, ctx)` → `onPeerDisconnected` → subscription-table cleanup) — do not add teardown in `Stream`.

**Callback-storage precedent on this class** (connectivity.hpp L41-48, L104 — violation handler follows `ConnectionStatusFeedback`'s shape; either ctor arg or a small setter called from `GossipCore::start()`, RESEARCH Pattern 4):
```cpp
    using ConnectionStatusFeedback =
        std::function<void(bool connected, const PeerContextPtr &ctx)>;
    ...
    ConnectionStatusFeedback connected_cb_;
    Stream::Feedback on_stream_event_;
```

**Stream construction sites — both must gain the `log_` arg** (identical `make_shared` shape; `log_` member already exists on `Connectivity`, created in its ctor L47-49):
```cpp
    // outbound site, in onNewStream (~L335-342):
    auto gossip_stream = std::make_shared<Stream>(stream_id,
                                                  config_,
                                                  *scheduler_,
                                                  on_stream_event_,
                                                  *msg_receiver_,
                                                  std::move(stream),
                                                  ctx);
    // inbound site, in handle() (~L213-220): byte-identical shape, same args
```
(Note both sites also call `stream->adjustWindowSize(64 * 1024 * 1024, ...)` — context for RESEARCH Pitfall 4; no change needed.)

**Sole-caller fact:** `Connectivity::flush(ctx)` (~L154-176) is the only caller of `Stream::write` — the admission check has no other entry path:
```cpp
    // N.B. errors, if any, will be passed later in async manner
    auto serialized = ctx->message_builder->serialize();
    ctx->outbound_stream->write(std::move(serialized));
```

---

### 9/10. `thirdparty/libp2p/src/protocol/gossip/impl/gossip_core.hpp` + `gossip_core.cpp` (handler storage + forward)

**Analog:** same files — `setMessageIdFn` is the exact store-a-`std::function`-from-the-interface pattern; `start()` is where `Connectivity` is created and can receive the handler.

**Storage pattern** (gossip_core.cpp L169-172 + member `MessageIdFn create_message_id_;` in the hpp):
```cpp
  void GossipCore::setMessageIdFn(MessageIdFn fn) {
    assert(fn);
    create_message_id_ = std::move(fn);
  }
```
`setViolationHandler` override = same body storing into a `ViolationHandler violation_handler_;` member. If interface method is pure virtual, add `override` here (GossipCore's other overrides at hpp L50-66 show the `private: // Gossip overrides` section to place it in).

**Forward-to-Connectivity site** (gossip_core.cpp L126-136):
```cpp
    connectivity_ = std::make_shared<Connectivity>(
        config_,
        scheduler_,
        host_,
        shared_from_this(),
        [this](bool connected, const PeerContextPtr &ctx) {
          onPeerConnection(connected, ctx);
        }
    );
```
Either extend the ctor arg list (handler lives in `config_`-adjacent storage before `start()` runs — note `GossipPubSub` registers before `Start()`, so ordering is safe) or call a setter right after this block. Also relevant: `RemoteSubscriptions` is created here with `log_` passed by ref (L141-142: `std::make_shared<RemoteSubscriptions>(config_, *connectivity_, *scheduler_, log_)`) — the precedent for `Stream` receiving `Connectivity::log_` by ref.

---

### 11/12. `thirdparty/ipfs-pubsub/src/ipfs_pubsub/gossip_pubsub.hpp` + `gossip_pubsub.cpp` (registration + escalation)

**Analog:** same files — gossip-creation site (where registration goes), BlockPeer family (what the handler calls), and the gater's mutex discipline (for the close counter).

**Registration site** (gossip_pubsub.cpp L301-307, inside `InitHostFromInjector`; `m_connection_gater` already created in `Init()` at L269 — before the injector ran, so both objects exist):
```cpp
        // Create gossip node
        m_gossip = libp2p::protocol::gossip::create(
            injector.template create<std::shared_ptr<libp2p::basic::Scheduler>>(),
            m_host,
            injector.template create<std::shared_ptr<libp2p::peer::IdentityManager>>(),
            injector.template create<std::shared_ptr<libp2p::crypto::CryptoProvider>>(),
            injector.template create<std::shared_ptr<libp2p::crypto::marshaller::KeyMarshaller>>(),
            config_ );
        // ← register here (D-08): m_gossip->setViolationHandler(...) — handler
        //   keeps a per-peer sustained-overflow close counter (D-09) and on the
        //   K_close-th close calls BlockPeer(peerId).
```

**Handler body calls the existing BlockPeer chain** (gossip_pubsub.cpp L237-263 — existing, unchanged; log-first style is the file's convention):
```cpp
    void GossipPubSub::BlockPeer( const libp2p::peer::PeerId &peerId )
    {
        m_logger->info( "Connection gater: blocking peer {}", peerId.toBase58() );
        m_connection_gater->BlockPeer( peerId );
    }
    ...
    bool GossipPubSub::IsPeerBlocked( const libp2p::peer::PeerId &peerId ) const
    {
        return m_connection_gater->IsPeerBlocked( peerId );
    }
```

**Close-counter concurrency pattern** (analog: `deny_list_connection_gater.hpp` L29-53 — mutex-guarded peer-keyed state, header-only inline):
```cpp
        void BlockPeer( const libp2p::peer::PeerId &peer )
        {
            std::lock_guard<std::mutex> lock( m_mutex );
            m_denied_peers.insert( peer );
        }
```
The D-09 counter (`std::unordered_map<libp2p::peer::PeerId, size_t>` + threshold) follows this exact discipline — the violation handler may fire on the gossip/scheduler strand (A6), so guard it. Dispatch-context note (RESEARCH A6): if the handler does anything heavier than counter+BlockPeer, marshal via scheduler; counter+gater is accepted as safe.

**Block semantics — TEST-02 assert basis** (gossip_pubsub.hpp L106-111 doc + gater intercepts): blocks reject NEW connections only; live connections are NOT terminated. Assert escalation via `IsPeerBlocked`, never via connection death. `DenyListConnectionGater` (`src/ipfs_pubsub/deny_list_connection_gater.hpp`, whole file is the reference) needs no changes (D-10).

**STYLE WARNING for the planner/executor:** this file's local style differs from libp2p's — 4-space indent, spaces inside parens `BlockPeer( const ... )`, `m_` member prefix, PascalCase methods, Allman-ish braces. Follow the file you are editing (AGENTS.md C++ conventions note both lineages).

---

### 13. `thirdparty/ipfs-pubsub/test/src/gossip_pubsub_bounds_test.cpp` (NEW — TEST-02 a/b/c + raw fixture; name discretionary)

**Analog A (primary): `thirdparty/ipfs-pubsub/test/src/gossip_pubsub_test.cpp`** — fixture, config-via-ctor, two-node shape, bounded waits.

Fixture + config-via-ctor (top of file ~L1-60):
```cpp
namespace
{
    libp2p::protocol::gossip::Config MakeEchoConfig()
    {
        libp2p::protocol::gossip::Config config;
        config.echo_forward_mode = true;
        return config;
    }
} // namespace

class GossipPubSubTest : public ::testing::Test
{
public:
    virtual void SetUp() override
    {
        auto logging_system = std::make_shared<soralog::LoggingSystem>(...);
        logging_system->configure();
        libp2p::log::setLoggingSystem( logging_system );
        ...
    }
};
```
The new file needs its own `Make*Config()` (this is where `max_remote_subscriptions_per_peer`, tiny `max_pending_bytes_per_stream`, small `overflow_close_threshold`, tiny `heartbeat_interval_msec`, and LARGE `rw_timeout_msec` per RESEARCH Pitfall 4 get set). Copy the logger YAML block verbatim (sinks/groups), rename the group.

Two-node shape — **distinct ports, mandatory** (passing test `MutipleGossipSubObjectsOnDifferentChannels` ~L335-344; the same-port variant is the one pre-existing failure, Pitfall 1):
```cpp
    GossipPubSub             pubs1( MakeEchoConfig() );
    ASSERT_FALSE( pubs1.Start( 40001, {} ).get() );
    GossipPubSub pubs2( MakeEchoConfig() );
    ASSERT_FALSE( pubs2.Start( 40002, {} ).get() );
```
TEST-02(a) shape: B subscribes `cap+1` topics via public `Subscribe()`; assert A's table bounded via `getAllPeers()`/`getPeerCount()` on excess topics (delegating wrappers verified at gossip_pubsub.cpp L703-711).

**Bounded idempotent wait** (~L420-432 — the suite's existing pattern; D-11's determinism comes from this shape, not mock-scheduler stepping):
```cpp
    bool peer_seen = false;
    for ( int i = 0; i < 100 && !peer_seen; ++i )
    {
        peer_seen = pubs2.getPeerCount( "topic1" ) > 0;
        if ( !peer_seen )
        {
            std::this_thread::sleep_for( std::chrono::milliseconds( 50 ) );
        }
    }
    ASSERT_TRUE( peer_seen ) << "pubs2 never learned of pubs1's subscription";
```
Critical pacing constraint (Pitfall 2): publishes flush at heartbeat/onMessageEnd/new-peer connect — NOT on `Publish()`. TEST-02(b) must be heartbeat-paced: one oversized publish → bounded wait for the cycle's observable → repeat K times. Never assert an exact drop count after a burst.

**Analog B (raw-host patterns): `SuperGenius/test/src/pubsub_counts/pubsub_counts.cpp`** — Windows-proven in this workspace; the raw fixture's host/identity/wait toolkit:
```cpp
    /// Generates a fresh Ed25519 key pair so every node has a distinct identity.
    libp2p::crypto::KeyPair GenerateKeyPair()
    {
        libp2p::crypto::ed25519::Ed25519ProviderImpl provider;
        auto keypair = provider.generate().value();
        ...
    }
    // ephemeral ports + explicit peer exchange + condition-macro wait (~L86-110):
        auto future = pubs1->Start( 0, {} );
        ...
        pubs1->AddPeers( { pubs2->GetInterfaceAddress() } );
        pubs2->AddPeers( { pubs1->GetInterfaceAddress() } );
        ...
        ASSERT_WAIT_FOR_CONDITION(
            [&]() { return resultChannel.getPeerCount() == resultChannel2.getPeerCount(); },
            std::chrono::milliseconds( 9000 ),
            "Peer counts did not converge within timeout",
            nullptr );
```
(If `ASSERT_WAIT_FOR_CONDITION` from SuperGenius's `testutil/wait_condition.hpp` is not reachable from ipfs-pubsub's test tree, the `peer_seen` loop from Analog A is the in-suite equivalent — planner picks per include availability; do NOT add a SuperGenius dependency.)

**Analog C (fixture wire format): `thirdparty/libp2p/src/protocol/gossip/impl/message_builder.cpp` ~L82-95** — the length-prefix convention the hand-encoded subscribe RPC must reproduce (varint prefix + protobuf payload; fixture uses public `libp2p::multi::UVarint` — `rpc.pb.h` is NOT installed, Pitfall 5):
```cpp
    auto varint_len = multi::UVarint{msg_sz};
    auto varint_vec = varint_len.toVector();
    size_t prefix_sz = varint_vec.size();
    auto buffer = std::make_shared<ByteArray>();
    buffer->resize(prefix_sz + msg_sz);
    memcpy(buffer->data(), varint_vec.data(), prefix_sz);
```
Wire format for the fixture's subscribe RPC: `UVarint(total_len) || bytes of RPC{ subscriptions: [ SubOpts{ subscribe: true, topicid: T } ] }` — SubOpts fields `subscribe=1 (bool)`, `topicid=2 (string)`; ~15 lines, hand-encoded.

**Analog D (test-file conventions): `thirdparty/ipfs-bitswap-cpp/test/bitswap_request_timer_race_test.cpp` @ HEAD `f899393`** (tracked; NOT on disk — working tree reverted, pull with `git show HEAD:test/...`):
- Opening contract-comment block (~L1-35) enumerating every case, its decision refs, and the determinism contract — replicate with GOSS-01..04/D-03..D-12 refs and the D-11 documented deviation (config-determinism, not mock-scheduler; conscious deviation from Phase 1-2 no-sleeps).
- `@given/@when/@then` doc comment per TEST (both suites already do this).
- Case naming: behavior-descriptive (`LateRegistrationOnTimedOutReplaysRequestTimeout` style) → e.g. `SubscribeCapBoundsRemoteSubscriptions`, `SustainedOverflowClosesStreamAndBlocksPeer`.

**Test CMake registration** (`thirdparty/ipfs-pubsub/test/src/CMakeLists.txt` L1-4 — one-line addition to the existing `addtest`):
```cmake
addtest(ipfs-pubsub-test
    gossip_pubsub_test.cpp
    gossip_pubsub_topic_test.cpp
    gossip_pubsub_bounds_test.cpp   # ← add
    )
```
No other build wiring needed (harness configure/build/run commands verified in 03-RESEARCH.md §Verified harness commands; baseline 11 pass / 1 pre-existing fail / 1 disabled — do not regress the 11, do not "fix" the failing one).

---

## Shared Patterns

### 1. Bounds-check early-return + SubLogger (GOSS-04)
**Source:** `stream.cpp` L74-77 (`msg_len > max_message_size_`), `remote_subscriptions.cpp` L41-47 (dedup return)
**Apply to:** every new check (D-03 cap, D-05/D-07 admission). Log BEFORE return; `{}` placeholders only; peer/topic/bytes as data values (log-injection mitigation). Cap drops in `RemoteSubscriptions` log at `warn` via existing `log_`; drops in `Stream` need the new `SubLogger&` member (only class in the fix without one).

### 2. Async dispatch = scheduler + `weak_from_this`/`shared_from_this`
**Source:** `stream.cpp` L212-219 (`asyncPostError`); `connectivity.cpp` start() lambda (`weak_from_this` guard, ~L57-62)
**Apply to:** K-th-drop error post (must be async, after `close()`), and any heavier violation-handler marshaling (RESEARCH A6). This is the lifetime discipline D-12's ASan run watches.

### 3. Additive config flows via ctor copy
**Source:** `stream.cpp` L20-33 (`max_message_size_(config.max_message_size)`); `RemoteSubscriptions` ctor stores `config_`
**Apply to:** `max_pending_bytes_` in `Stream`; `config_.max_remote_subscriptions_per_peer` read directly from `RemoteSubscriptions::config_`. Existing SuperGenius/GeniusSDK builds untouched (defaults) — compatibility constraint honored.

### 4. Requirement-ID markers + branch/commit conventions (Phase 4 content-probe chain)
**Source:** ipfs-bitswap-cpp `dev_timer_correctness` @ HEAD: source markers `src/bitswap.cpp` L438 (`// BSTP-04: registration strictly OUTSIDE the mutex...`), L83/L99/L129; commits `feat(02-01): close BSTP-04 — ... (D-01..D-03)` / `test(02-01): extend race suite ...`
**Apply to:** Phase 3 uses `GOSS-01..04` (+ `TEST-02`) as greppable markers at each decision site in libp2p AND ipfs-pubsub source (D-11 consequence: libp2p carries code-marker probes only). Commits: `feat(03-01): ... (D-xx)` / `test(03-01): ...`. Branches: libp2p `dev_gossip_bounds` cut from `master@28f6a629` (never pushed); ipfs-pubsub continue `dev_ipfs_fix` @ `b6eb6268` (Phase 1/2 precedent).

### 5. Bounded idempotent waits, distinct ports, heartbeat pacing
**Source:** `gossip_pubsub_test.cpp` L335-344 (distinct ports), L420-432 (`peer_seen` loop); `pubsub_counts.cpp` L86-110 (`Start(0)`/`AddPeers`/`ASSERT_WAIT_FOR_CONDITION`)
**Apply to:** all TEST-02 tests. Never both nodes on one fixed port (Pitfall 1); never burst-then-count (Pitfall 2); `rw_timeout_msec` large in test config (Pitfall 4); test node subscribes to the topic so mesh grafting delivers full-size RPCs to the raw peer (Pitfall 3).

### 6. Escalation state = mutex-guarded peer-keyed container
**Source:** `deny_list_connection_gater.hpp` L29-53
**Apply to:** `GossipPubSub`'s per-peer close counter (D-09). Reuse `BlockPeer()`/`IsPeerBlocked` as-is (D-10: no new policy machinery).

### 7. Per-submodule local style
libp2p: 2-space, `member_` trailing underscore, no space in parens, `log::SubLogger log_`. ipfs-pubsub: 4-space, `m_` prefix, `Method( arg )` spacing, `m_logger->info`. Match the file being edited; do not restyle touched lines beyond the change.

## No Analog Found

| File / Sub-shape | Role | Data Flow | Reason |
|------|------|-----------|--------|
| Raw gossip-speaking peer fixture (part of the new test file, TEST-02(b)) | test fixture | pub-sub | No tracked test in either repo speaks `/meshsub` without `GossipPubSub`/`GossipCore`. Compose from: pubsub_counts host/identity patterns (Analog B) + `UVarint` length-prefix convention (Analog C, message_builder.cpp L82-95) + RESEARCH Pitfall 5 wire format. Planner treats the encoder as new code — it is the phase's only genuinely novel component |
| `ViolationType` enum (part of gossip.hpp) | config | n/a | New type, but trivially modeled on `Error` enum style (common.hpp L17-29); no outcome category needed (not an error code). RESEARCH recommends leaving room for future values; only `SustainedWriteOverflow` is emitted this phase |

## Metadata

**Analog search scope:** `thirdparty/libp2p/{include/libp2p/protocol/gossip, src/protocol/gossip/impl}`, `thirdparty/ipfs-pubsub/{src/ipfs_pubsub, test/src, test/CMakeLists.txt, cmake}`, `SuperGenius/test/src/pubsub_counts`, `thirdparty/ipfs-bitswap-cpp` (via `git show HEAD:` — working tree dirty per RESEARCH Pitfall 7)
**Files scanned:** 20 (14 target + 6 analog-only)
**Tracked-source verification:** all 15 named analog paths printed via `git ls-files` in their submodules (executed 2026-10-13); no gitignored/mirror paths emitted
**Pattern extraction date:** 2026-10-13
