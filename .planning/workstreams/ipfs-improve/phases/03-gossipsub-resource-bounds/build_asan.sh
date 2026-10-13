#!/bin/bash
# D-12 WSL ASan run (Route A): direct clang++ ASan compile of the changed
# gossip TUs + the TEST-02 bounds test TU, linked against the prebuilt
# Linux x86_64 thirdparty static-lib set. Throwaway evidence build —
# NO git commands run inside WSL (D-07/D-12).
set -x
cd ~/gsd-asan/pubsub || exit 1

B=~/gnus/GeniusNetwork/thirdparty/build/Linux/Debug/x86_64
PB=$B/libp2p/src/libp2p-build/pb/p2p_gossip_proto

CXX="clang++ -fsanitize=address -g -std=c++17 -D_DEBUG -DSPDLOG_FMT_EXTERNAL"
INC="-Iipfs-pubsub/src -Iipfs-pubsub/test -Ilibp2p/src -Ilibp2p/include \
 -I$PB -I$PB/generated \
 -isystem $B/boost/build/include \
 -isystem $B/soralog/include \
 -isystem $B/spdlog/include \
 -isystem $B/fmt/include \
 -isystem $B/yaml-cpp/include \
 -isystem $B/Boost.DI/include \
 -isystem $B/openssl/build/include \
 -isystem $B/protobuf/include \
 -isystem $B/cares/include \
 -isystem $B/tsl_hat_trie/include \
 -isystem $B/Microsoft.GSL/include \
 -isystem $B/GTest/include \
 -isystem $B/ipfs-lite-cpp/include"

mkdir -p obj

compile() { # src obj
  $CXX $INC -c "$1" -o "$2" || exit 1
}

compile libp2p/src/protocol/gossip/impl/common.cpp            obj/common.o
compile libp2p/src/protocol/gossip/impl/stream.cpp            obj/stream.o
compile libp2p/src/protocol/gossip/impl/connectivity.cpp      obj/connectivity.o
compile libp2p/src/protocol/gossip/impl/gossip_core.cpp       obj/gossip_core.o
compile libp2p/src/protocol/gossip/impl/remote_subscriptions.cpp obj/remote_subscriptions.o
compile ipfs-pubsub/src/ipfs_pubsub/gossip_pubsub.cpp         obj/gossip_pubsub.o
compile ipfs-pubsub/test/src/gossip_pubsub_bounds_test.cpp    obj/bounds_test.o
compile ipfs-pubsub/test/src/gossip_pubsub_test.cpp           obj/gossip_pubsub_test.o
compile ipfs-pubsub/test/src/gossip_pubsub_topic_test.cpp      obj/gossip_pubsub_topic_test.o

# Link: fresh ASan objects FIRST (archive members then never pulled for the
# symbols they define), then the full prebuilt set inside a start/end group.
clang++ -fsanitize=address -g obj/common.o obj/stream.o obj/connectivity.o \
  obj/gossip_core.o obj/remote_subscriptions.o obj/gossip_pubsub.o obj/bounds_test.o \
  obj/gossip_pubsub_test.o obj/gossip_pubsub_topic_test.o \
  -Wl,--start-group \
  $B/ipfs-pubsub/lib/libipfs-pubsub.a \
  $B/libp2p/lib/*.a \
  $B/ipfs-lite-cpp/lib/*.a \
  $B/GTest/lib/libgtest.a $B/GTest/lib/libgtest_main.a \
  $B/protobuf/lib/libprotobufd.a $B/protobuf/lib/libabsl_*.a $B/protobuf/lib/libutf8_*.a \
  $B/openssl/build/lib/libssl.a $B/openssl/build/lib/libcrypto.a \
  $B/cares/lib/*.a \
  $B/yaml-cpp/lib/*.a \
  $B/spdlog/lib/*.a $B/fmt/lib/*.a \
  $B/soralog/lib/soralog/*.a \
  $B/boost/build/lib/libboost_system*.a \
  $B/boost/build/lib/libboost_random*.a \
  $B/boost/build/lib/libboost_filesystem*.a \
  $B/boost/build/lib/libboost_date_time*.a \
  $B/boost/build/lib/libboost_regex*.a \
  $B/boost/build/lib/libboost_chrono*.a \
  $B/boost/build/lib/libboost_thread*.a \
  -Wl,--end-group \
  -lpthread -ldl -lrt \
  -o pubsub_asan || exit 1

echo BUILD_OK
