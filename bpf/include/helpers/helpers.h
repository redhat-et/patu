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

#ifndef BPF_FUNC
#define BPF_FUNC(NAME, ...) (*NAME)(__VA_ARGS__) = (void *)BPF_FUNC_##NAME
#endif

struct socket_key {
  __u32 src_ip;
  __u32 dst_ip;
  __u16 src_port;
  __u16 dst_port;
};

struct bpf_map {
  __u32 id;
  __u32 type;
  __u32 key_size;
  __u32 value_size;
  __u32 max_elem;
  __u32 flags;
  __u32 pinning;
};

static __u64 BPF_FUNC(get_current_pid_tgid);
static void BPF_FUNC(trace_printk, const char *fmt, int fmt_size, ...);
static int BPF_FUNC(sock_hash_update, struct bpf_sock_ops *skops,
                    struct bpf_map *map, void *key, __u64 flags);
static long BPF_FUNC(sk_redirect_hash, struct __sk_buff *skb,
                     struct bpf_map *map, void *key, __u64 flag);

void logMetadata(char *prog, int pid, struct bpf_sock_addr *ctx) {
  print_info("%s called by %d", prog, pid);
  print_info("%s, ip : %s,  port %s", prog, ctx->user_ip4,
             bpf_htons(ctx->user_port));
}
