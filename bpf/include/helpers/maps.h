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

#define __uint(name, val) int(*name)[val]
#define __type(name, val) typeof(val) *name

#define SEC(name)                                                              \
  _Pragma("GCC diagnostic push")                                               \
      _Pragma("GCC diagnostic ignored \"-Wignored-attributes\"")               \
          __attribute__((section(name), used)) _Pragma("GCC diagnostic pop")

#define MAX_ENTRIES 65535

struct {
  __uint(type, BPF_MAP_TYPE_SOCKHASH);
  __uint(max_entries, MAX_ENTRIES);
  __type(key, struct socket_key);
  __type(value, __u32);
} sockops_redir_map SEC(".maps");

struct {
  __uint(type, BPF_MAP_TYPE_HASH);
  __uint(max_entries, 1024);
  __type(key, enum cni_config_key);
  __type(value, union cni_config_value);
} cni_config_map SEC(".maps");
