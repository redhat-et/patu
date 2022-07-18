/*
 * Copyright © 2022 Authors of Patu
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#pragma once

#include "common.h"

/*struct bpf_map __section("maps") sockops_redir_map = {
    .type = BPF_MAP_TYPE_SOCKHASH,
    .key_size = sizeof(struct socket_key),
    .value_size = sizeof(__u32),
    .max_elem = 65535,
};*/

#define MAX_ELEMENT 65535

struct btf_map {
  __uint(type, BPF_MAP_TYPE_SOCKHASH);
  __uint(max_elem, MAX_ELEMENT);
  __type(key, struct socket_key);
  __type(value, u32);
} sockops_redir_map SEC(".maps");