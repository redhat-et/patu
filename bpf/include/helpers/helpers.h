/*
Copyright © 2022 Authors of Patu

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

#pragma once

#include "maps.h"
#include <linux/bpf.h>
#include <linux/swab.h>

#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#define bpf_htons(x) __builtin_bswap16(x)
#define bpf_htonl(x) __builtin_bswap32(x)
#elif __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
#define bpf_htons(x) (x)
#define bpf_htonl(x) (x)
#else
#error "__BYTE_ORDER__ error"
#endif

#ifndef __section
#define __section(NAME) __attribute__((section(NAME), used))
#endif

#undef print_info
#define print_info(fmt, ...)                                                   \
  ({                                                                           \
    char ____fmt[] = fmt;                                                      \
    trace_printk(____fmt, sizeof(____fmt), ##__VA_ARGS__);                     \
  })

#undef print_dbg
#define print_dbg(fmt, ...)                                                    \
  ({                                                                           \
    char ____fmt[] = "[dbg] " fmt;                                             \
    trace_printk(____fmt, sizeof(____fmt), ##__VA_ARGS__);                     \
  })

#ifndef FORCE_READ
#define FORCE_READ(X) (*(volatile typeof(X)*)&X)
#endif

#ifndef BPF_FUNC
#define BPF_FUNC(NAME, ...) (*NAME)(__VA_ARGS__) = (void *)BPF_FUNC_##NAME
#endif

struct socket_key {
  __u32 src_ip;
  __u32 dst_ip;
  __u32 src_port;
  __u32 dst_port;
} __attribute__((packed));

enum cni_config_key { SUBNET_IP, CIDR, DEBUG };

union cni_config_value {
  struct {
    __u32 pad1;
    __u32 pad2;
    __u32 pad3;
    __u32 ipv4;
  };
  struct {
    __u32 ipv6p1;
    __u32 ipv6p2;
    __u32 ipv6p3;
    __u32 ipv6p4;
  };
  struct {
    __u32 nil1;
    __u32 nil2;
    __u32 nil3;
    __u32 debug;
  };
};

static __u64 BPF_FUNC(get_current_pid_tgid);
static __u64 BPF_FUNC(get_current_uid_gid);
static void BPF_FUNC(trace_printk, const char *fmt, int fmt_size, ...);
static void *BPF_FUNC(map_lookup_elem, void *map, const void *key);
static int BPF_FUNC(sock_hash_update, struct bpf_sock_ops *skops, void *map,
                    void *key, __u64 flags);
static long BPF_FUNC(sk_redirect_hash, struct __sk_buff *skb, void *map,
                     void *key, __u64 flag);
static long BPF_FUNC(msg_redirect_hash, struct sk_msg_md *msg, void *map,
                     void *key, __u64 flags);
