#!/bin/bash
#
# Copyright © 2022 Authors of Patu
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
set -x
shopt -s expand_aliases

KUBECONFIG_TESTS="kubeconfig_tests.conf"

GINKGO_FOCUS="\[sig-network\]"
GINKGO_SKIP_TESTS="machinery|Feature|Federation|PerformanceDNS|Disruptive|Serial|LoadBalancer|GCE|Netpol|NetworkPolicy"
GINKGO_REPORT_DIR="artifacts/reports"
GINKGO_DUMP_LOGS_ON_FAILURE=false
GINKGO_DISABLE_LOG_DUMP=true
GINKGO_PROVIDER="local"

function if_error_exit() {
    ###########################################################################
    # Description:                                                            #
    # Validate if previous command failed and show an error msg (if provided) #
    #                                                                         #
    # Arguments:                                                              #
    #   $1 - error message if not provided, it will just exit                 #
    ###########################################################################
    if [ "$?" != "0" ]; then
        if [ -n "$1" ]; then
            RED="\e[31m"
            ENDCOLOR="\e[0m"
            echo -e "[ ${RED}FAILED${ENDCOLOR} ] ${1}"
        fi
        exit 1
    fi
}

function if_error_warning() {
    ###########################################################################
    # Description:                                                            #
    # Validate if previous command failed and show an error msg (if provided) #
    #                                                                         #
    # Arguments:                                                              #
    #   $1 - error message if not provided, it will just exit                 #
    ###########################################################################
    if [ "$?" != "0" ]; then
        if [ -n "$1" ]; then
            RED="\e[31m"
            ENDCOLOR="\e[0m"
            echo -e "[ ${RED}FAILED${ENDCOLOR} ] ${1}"
        fi
    fi
}

function pass_message() {
    ###########################################################################
    # Description:                                                            #
    # show [PASSED] in green and a message as the validation passed.          #
    #                                                                         #
    # Arguments:                                                              #
    #   $1 - message to output                                                #
    ###########################################################################
    if [ -z "${1}" ]; then
        echo "pass_message() requires a message"
        exit 1
    fi
    GREEN="\e[32m"
    ENDCOLOR="\e[0m"
    echo -e "[ ${GREEN}PASSED${ENDCOLOR} ] ${1}"
}

command_exists() {
    ###########################################################################
    # Description:                                                            #
    # Checkt if a binary exists                                               #
    #                                                                         #
    # Arguments:                                                              #
    #   arg1: binary name                                                     #
    ###########################################################################
    cmd="$1"
    command -v ${cmd} >/dev/null 2>&1
}

function delete_kind_cluster() {
    ###########################################################################
    # Description:                                                            #
    # delete kind cluster                                                     #
    #                                                                         #
    # Arguments:                                                              #
    #   arg1: cluster name                                                    #
    ###########################################################################
    [ $# -eq 1 ]
    if_error_exit "Wrong number of arguments to ${FUNCNAME[0]}"

    local cluster_name="${1}"

    if kind get clusters | grep -q "${cluster_name}" &>/dev/null; then
        kind delete cluster --name "${cluster_name}" &>/dev/null
        if_error_warning "cannot delete cluster ${cluster_name}"

        pass_message "Cluster ${cluster_name} deleted."
    fi
}

function run_tests() {
    ###########################################################################
    # Description:                                                            #
    # Execute the tests with ginkgo                                           #
    #                                                                         #
    # Arguments:                                                              #
    #   arg1: e2e directory                                                   #
    #   arg2: e2e_test, path to test binary                                   #
    #   arg3: parallel ginkgo tests boolean                                   #
    ###########################################################################

    [ $# -eq 3 ]
    if_error_exit "Wrong number of arguments to ${FUNCNAME[0]}"

    local e2e_dir="${1}"
    local e2e_test="${2}"
    local parallel="${3}"

    local artifacts_directory="${e2e_dir}/artifacts"

    [ -f "${artifacts_directory}/${KUBECONFIG_TESTS}" ]
    if_error_exit "Directory \"${artifacts_directory}/${KUBECONFIG_TESTS}\" does not exist"

    [ -f "${e2e_test}" ]
    if_error_exit "File \"${e2e_test}\" does not exist"

    # ginkgo regexes
    local ginkgo_skip="${GINKGO_SKIP_TESTS:-}"
    local ginkgo_focus=${GINKGO_FOCUS:-"\\[Conformance\\]"}
    # if we set PARALLEL=true, skip serial tests set --ginkgo-parallel
    if [ "${parallel}" = "true" ]; then
        export GINKGO_PARALLEL=y
        if [ -z "${skip}" ]; then
            ginkgo_skip="\\[Serial\\]"
        else
            ginkgo_skip="\\[Serial\\]|${ginkgo_skip}"
        fi
    fi

    # setting this env prevents ginkgo e2e from trying to run provider setup
    export KUBERNETES_CONFORMANCE_TEST='y'
    export KUBE_CONTAINER_RUNTIME=remote
    export KUBE_CONTAINER_RUNTIME_ENDPOINT=unix:///run/containerd/containerd.sock
    export KUBE_CONTAINER_RUNTIME_NAME=containerd

    ${e2e_dir}/bin/ginkgo --nodes=1 \
        --focus="${ginkgo_focus}" \
        --skip="${ginkgo_skip}" \
        "${e2e_test}" \
        -- \
        --kubeconfig="${artifacts_directory}/${KUBECONFIG_TESTS}" \
        --provider="${GINKGO_PROVIDER}" \
        --dump-logs-on-failure="${GINKGO_DUMP_LOGS_ON_FAILURE}" \
        --report-dir="${GINKGO_REPORT_DIR}" \
        --disable-log-dump="${GINKGO_DISABLE_LOG_DUMP}"
}

function print_reports() {
    ###########################################################################
    # Description:                                                            #
    # create_infrastructure_and_run_tests                                     #
    #                                                                         #
    # Arguments:                                                              #
    #   arg1: ip_family                                                       #
    #   arg2: backend                                                         #
    #   arg3: e2e_directory                                                   #
    #   arg4: suffix                                                          #
    #   arg5: cluster_count                                                   #
    ###########################################################################

    [ $# -eq 5 ]
    if_error_exit "Wrong number of arguments to ${FUNCNAME[0]}"

    # setting up variables
    local ip_family="${1}"
    local backend="${2}"
    local e2e_directory="${3}"
    local suffix="${4}"
    local cluster_count="${5}"

    echo "+==========================================================================================+"
    echo -e "\t\tTest Report from running test \"-i ${ip_family} -b ${backend}\" on ${cluster_count} clusters."
    echo "+==========================================================================================+"

    local combined_output_file=$(mktemp -q)
    if_error_exit "Could not create temp file, mktemp failed"

    for i in $(seq "${cluster_count}"); do
        local test_directory="${e2e_directory}${suffix}${i}"

        if ! [ -d "${test_directory}" ]; then
            echo "directory \"${test_directory}\" not found, skipping"
            continue
        fi

        echo -e "Summary report from cluster \"${i}\" in directory: \"${test_directory}\""
        local output_file="${test_directory}/output.log"
        cat "${output_file}" >>"${combined_output_file}"

        sed -nE '/Ran[[:space:]]+[[:digit:]]+[[:space:]]+of[[:space:]]+[[:digit:]]/{N;p}' "${output_file}"
    done

    echo -e "\nOccurence\tFailure"
    awk '/Summarizing/,0' "${combined_output_file}" | awk 'ORS=/\[Fail\]/?", ":RS' | awk '/\[Fail\]/' |
        sed 's/\x1b\[90m//g' | sort | uniq -c | sort -nr | sed 's/\,/\n\t\t/g'

    rm -f "${combined_output_file}"
}

function main() {
    ###########################################################################
    # Description:                                                            #
    # Starting E2E process                                                    #
    #                                                                         #
    # Arguments:                                                              #
    #   None                                                                  #
    ###########################################################################

    [ $# -eq 11 ]
    if_error_exit "Wrong number of arguments to ${FUNCNAME[0]}"

    # setting up variables
    local ip_family="${1}"
    local backend="${2}"
    local ci_mode="${3}"
    local e2e_dir="${4}"
    local bin_dir="${5}"
    local dockerfile="${6}"
    local suffix="${7}"
    local cluster_count="${8}"
    local erase_clusters="${9}"
    local print_report="${10}"
    local devel_mode="${11}"

    [ "${cluster_count}" -ge "1" ]
    if_error_exit "cluster_count must be larger or equal to one"

    e2e_dir=${e2e_dir:="$(pwd)/temp/e2e"}
    bin_dir=${bin_dir:="${e2e_dir}/bin"}

    if ${print_report}; then
        print_reports "${ip_family}" "${backend}" "${e2e_dir}" "-${suffix}" "${cluster_count}"
        exit 1
    fi

    echo "+==================================================================+"
    echo -e "\t\tStarting Patu E2E testing"
    echo "+==================================================================+"

    # in ci this should fail
    if [ "${ci_mode}" = true ]; then
        # REMOVE THIS comment out ON THE REPO WITH A PR WHEN LOCAL TESTS ARE ALL GREEN
        # set -e
        echo "this tests can't fail now in ci"
#        set_host_network_settings "${ip_family}"
    fi

    run_tests "${e2e_dir}" "${bin_dir}/e2e.test" "false"

    if ${devel_mode}; then
        echo -e "\n+=====================================================================================+"
        echo -e "\t\tDeveloper mode no test run!"
        echo -e "+=====================================================================================+"
    elif ! ${ci_mode}; then
        delete_kind_clusters "${bin_dir}" "${ip_family}" "${backend}" "${suffix}" "${cluster_count}"
    fi
}

function help() {
    ###########################################################################
    # Description:                                                            #
    # Help function to be displayed                                           #
    #                                                                         #
    # Arguments:                                                              #
    #   None                                                                  #
    ###########################################################################
    printf "\n"
    printf "Usage: %s [-i ip_family] [-b backend]\n" "$0"
    printf "\nExample:\n\t %s -i ipv4 -b kubeproxy\n" "${0}"
    exit 1 # Exit script after printing help
}

tmp_dir=$(dirname "$0")
base_dir=$(cd "${tmp_dir}" && pwd)
ci_mode=false
devel_mode=false
e2e_dir=""
dockerfile="$(dirname "${base_dir}")/Dockerfile"
bin_dir=""
suffix=""
cluster_count="1"
erase_clusters=false
print_report=false

while getopts "i:b:B:cdD:eE:n:ps:" flag; do
    case "${flag}" in
    i) ip_family="${OPTARG}" ;;
    b) backend="${OPTARG}" ;;
    c) ci_mode=true ;;
    d) devel_mode=true ;;
    e) erase_clusters=true ;;
    n) cluster_count="${OPTARG}" ;;
    p) print_report=true ;;
    s) suffix="${OPTARG}" ;;
    B) bin_dir="${OPTARG}" ;;
    D) dockerfile="${OPTARG}" ;;
    E) e2e_dir="${OPTARG}" ;;
    ?) help ;; #Print help
    esac
done

if ! [[ "${backend}" =~ ^(kubeproxy|kpng)$ ]]; then
    echo "user must specify the supported backend"
    help
fi

if [[ -n "${ip_family}" && -n "${backend}" ]]; then
    main "${ip_family}" "${backend}" "${ci_mode}" "${e2e_dir}" "${bin_dir}" "${dockerfile}" \
        "${suffix}" "${cluster_count}" "${erase_clusters}" "${print_report}" "${devel_mode}"
else
    printf "Both of '-i' and '-b' must be specified.\n"
    help
fi
