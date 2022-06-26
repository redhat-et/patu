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

#include <linux/bpf.h>

#include "include/helpers/helpers.h"

__section("cgroup/sendmsg4") int patu_sendmsg4(struct bpf_sock_addr *ctx) {
  int pid = get_current_pid_tgid() >> 32;
  print_info("sendmsg4 is called by %d", pid);
  print_info("sendmsg4 ip : >>%X<<  port %d", bpf_htonl(ctx->user_ip4),
             bpf_htons(ctx->user_port));
  return 1;
}

char ____license[] __section("license") = "GPL";
int _version __section("version") = 1;
