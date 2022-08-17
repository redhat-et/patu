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

: "${E2E_GO_VERSION:="1.17.3"}"
: "${KIND_VERSION:="v0.11.1"}"
: "${E2E_K8S_VERSION:="v1.23.3"}"
: "${E2E_TIMEOUT_MINUTES:=100}"
: "${KINDEST_NODE_IMAGE:="kindest/node"}"
## Ensure that CLUSTER_CIDR and SERVICE_CLUSTER_IP_RANGE don't overlap
: "${CLUSTER_CIDR:="10.1.0.0/16"}"
: "${SERVICE_CLUSTER_IP_RANGE:="10.2.0.0/16"}"

OS=$(uname | tr '[:upper:]' '[:lower:]')
CONTAINER_ENGINE="docker"
KUBECONFIG_TESTS="kubeconfig_tests.conf"
BIN_DIRECTORY="bin"

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

function setup_kubectl() {
    ###########################################################################
    # Description:                                                            #
    # setup kubectl if not available in the system                            #
    #                                                                         #
    # Arguments:                                                              #
    #   arg1: installation directory, path to where kubectl will be installed  #
    ###########################################################################

    [ $# -eq 1 ]
    if_error_exit "Wrong number of arguments to ${FUNCNAME[0]}"

    local install_directory=$1

    [ -d "${install_directory}" ]
    if_error_exit "Directory \"${install_directory}\" does not exist"

    if ! [ -f "${install_directory}"/kubectl ]; then
        echo -e "\nDownloading kubectl ..."

        local tmp_file=$(mktemp -q)
        if_error_exit "Could not create temp file, mktemp failed"

        curl -L https://dl.k8s.io/"${E2E_K8S_VERSION}"/bin/"${OS}"/amd64/kubectl -o "${tmp_file}"
        if_error_exit "cannot download kubectl"

        sudo mv "${tmp_file}" "${install_directory}"/kubectl
        sudo chmod +rx "${install_directory}"/kubectl
        sudo chown root.root "${install_directory}"/kubectl
    fi

    pass_message "The kubectl tool is set."
}

function add_to_path() {
    ###########################################################################
    # Description:                                                            #
    # Add directory to path                                                   #
    #                                                                         #
    # Arguments:                                                              #
    #   arg1:  directory                                                      #
    ###########################################################################
    [ $# -eq 1 ]
    if_error_exit "Wrong number of arguments to ${FUNCNAME[0]}"

    local directory="${1}"

    [ -d "${directory}" ]
    if_error_exit "Directory \"${directory}\" does not exist"

    case ":${PATH:-}:" in
    *:${directory}:*) ;;
    *) PATH="${directory}${PATH:+:$PATH}" ;;
    esac
}

function set_e2e_dir() {
    ###########################################################################
    # Description:                                                            #
    # Set E2E directory                                                       #
    #                                                                         #
    # Arguments:                                                              #
    #   arg1: Path for E2E installation directory                             #
    #   arg2: binary directory, path to where ginko will be installed         #
    ###########################################################################

    [ $# -eq 2 ]
    if_error_exit "Wrong number of arguments to ${FUNCNAME[0]}"

    local e2e_dir="${1}"
    local bin_dir="${2}"

    [ -d "${bin_dir}" ]
    if_error_exit "Directory \"${bin_dir}\" does not exist"

    pushd "${0%/*}" >/dev/null || exit
    mkdir -p "${e2e_dir}"
    mkdir -p "${e2e_dir}/artifacts"
    popd >/dev/null || exit
}

function setup_ginkgo() {
    ###########################################################################
    # Description:                                                            #
    # setup ginkgo and e2e.test                                               #
    #                                                                         #
    # # Arguments:                                                            #
    #   arg1: binary directory, path to where ginko will be installed         #
    #   arg2: Kubernetes version                                              #
    #   arg3: OS, name of the operating system                                #
    ###########################################################################

    [ $# -eq 3 ]
    if_error_exit "Wrong number of arguments to ${FUNCNAME[0]}"

    local bin_directory=${1}
    local k8s_version=${2}
    local os=${3}
    local temp_directory=$(mktemp -qd)

    if ! [ -f "${bin_directory}"/ginkgo ] || ! [ -f "${bin_directory}"/e2e.test ]; then
        echo -e "\nDownloading ginkgo and e2e.test ..."
        curl -L https://dl.k8s.io/"${k8s_version}"/kubernetes-test-"${os}"-amd64.tar.gz \
            -o "${temp_directory}"/kubernetes-test-"${os}"-amd64.tar.gz
        if_error_exit "cannot download kubernetes-test package"

        tar xvzf "${temp_directory}"/kubernetes-test-"${os}"-amd64.tar.gz \
            --directory "${bin_directory}" \
            --strip-components=3 kubernetes/test/bin/ginkgo kubernetes/test/bin/e2e.test &>/dev/null

        rm -rf "${temp_directory}"
        sudo chmod +rx "${bin_directory}/ginkgo"
        sudo chmod +rx "${bin_directory}/e2e.test"
    fi

    pass_message "The tools ginko and e2e.test have been set up."
}

function setup_j2() {
    ###########################################################################
    # Description:                                                            #
    # Install j2 binary                                                       #
    ###########################################################################
    export PATH=~/.local/bin:$PATH
    if ! command_exists j2; then
        if ! command_exists pip; then
            echo "Dependency not met: attempting to install pip with python -m ensurepip --upgrade"
            curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
            python3 get-pip.py
            export PATH=~/.local/bin:$PATH
        fi

        echo "'j2' not found, installing with 'pip'"
        pip install wheel --user
        pip freeze | grep j2cli || pip install j2cli[yaml] --user
        if_error_exit "cannot download j2"
    fi
    pass_message "The tool j2 is installed."
}

function setup_kind() {
    ###########################################################################
    # Description:                                                            #
    # setup kind if not available in the system                               #
    #                                                                         #
    # Arguments:                                                              #
    #   arg1: installation directory, path to where kind will be installed     #
    ###########################################################################
    [ $# -eq 1 ]
    if_error_exit "Wrong number of arguments to ${FUNCNAME[0]}"

    local install_directory=$1

    [ -d "${install_directory}" ]
    if_error_exit "Directory \"${install_directory}\" does not exist"

    if ! [ -f "${install_directory}"/kind ]; then
        echo -e "\nDownloading kind ..."

        local tmp_file=$(mktemp -q)
        if_error_exit "Could not create temp file, mktemp failed"

        curl -L https://kind.sigs.k8s.io/dl/"${KIND_VERSION}"/kind-"${OS}"-amd64 -o "${tmp_file}"
        if_error_exit "cannot download kind"

        sudo mv "${tmp_file}" "${install_directory}"/kind
        sudo chmod +rx "${install_directory}"/kind
        sudo chown root.root "${install_directory}"/kind
    fi

    pass_message "The kind tool is set."
}

function install_binaries() {
    ###########################################################################
    # Description:                                                            #
    # Copy binaries from the net to binaries directory                        #
    #                                                                         #
    # Arguments:                                                              #
    #   arg1: binary directory, path to where ginko will be installed         #
    #   arg2: Kubernetes version                                              #
    #   arg3: OS, name of the operating system                                #
    ###########################################################################

    [ $# -eq 3 ]
    if_error_exit "Wrong number of arguments to ${FUNCNAME[0]}"

    local bin_directory="${1}"
    local k8s_version="${2}"
    local os="${3}"

    pushd "${0%/*}" >/dev/null || exit
    mkdir -p "${bin_directory}"
    popd >/dev/null || exit

    add_to_path "${bin_directory}"
    setup_kind "${bin_directory}"
    setup_kubectl "${bin_directory}"
    setup_ginkgo "${bin_directory}" "${k8s_version}" "${os}"
    setup_j2
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

function verify_host_network_settings() {
    ###########################################################################
    # Description:                                                            #
    # Verify hosts network settings                                           #
    #                                                                         #
    # Arguments:                                                              #
    #   arg1: ip_family                                                       #
    ###########################################################################
    [ $# -eq 1 ]
    if_error_exit "Wrong number of arguments to ${FUNCNAME[0]}"
    local ip_family="${1}"

    verify_sysctl_setting net.ipv4.ip_forward 1
    if [ "${ip_family}" = "ipv6" ]; then
        verify_sysctl_setting net.ipv6.conf.all.forwarding 1
        verify_sysctl_setting net.bridge.bridge-nf-call-arptables 0
        verify_sysctl_setting net.bridge.bridge-nf-call-ip6tables 0
        verify_sysctl_setting net.bridge.bridge-nf-call-iptables 0
    fi
}

function set_host_network_settings() {
    ###########################################################################
    # Description:                                                            #
    # prepare hosts network settings                                          #
    #                                                                         #
    # Arguments:                                                              #
    #   arg1: ip_family                                                       #
    ###########################################################################
    [ $# -eq 1 ]
    if_error_exit "Wrong number of arguments to ${FUNCNAME[0]}"
    local ip_family="${1}"
    set_sysctl net.ipv4.conf.all.forwarding 1
    set_sysctl net.ipv6.conf.all.forwarding 1
    if [ "${ip_family}" = "ipv6" ]; then
        set_sysctl net.ipv4.ip_forward 1
        set_sysctl net.bridge.bridge-nf-call-arptables 0
        set_sysctl net.bridge.bridge-nf-call-ip6tables 0
        set_sysctl net.bridge.bridge-nf-call-iptables 0
    fi
}

function set_sysctl() {
    ###########################################################################
    # Description:                                                            #
    # Set a sysctl attribute to value                                         #
    #                                                                         #
    # Arguments:                                                              #
    #   arg1: attribute                                                       #
    #   arg2: value                                                           #
    ###########################################################################
    [ $# -eq 2 ]
    if_error_exit "Wrong number of arguments to ${FUNCNAME[0]}"
    local attribute="${1}"
    local value="${2}"
    local result=$(sysctl -n "${attribute}")
    if_error_exit "\"sysctl -n ${attribute}\" failed"

    if [ ! "${value}" -eq "${result}" ]; then
        echo "Setting: \"sysctl -w ${attribute}=${value}\""
        sudo sysctl -w "${attribute}"="${value}"
        if_error_exit "\"sudo sysctl -w  ${attribute} = ${value}\" failed"
    fi
}

function verify_sysctl_setting() {
    ###########################################################################
    # Description:                                                            #
    # Verify that a sysctl attribute setting has a value                      #
    #                                                                         #
    # Arguments:                                                              #
    #   arg1: attribute                                                       #
    #   arg2: value                                                           #
    ###########################################################################
    [ $# -eq 2 ]
    if_error_exit "Wrong number of arguments to ${FUNCNAME[0]}"
    local attribute="${1}"
    local value="${2}"
    local result=$(sysctl -n "${attribute}")
    if_error_exit "\"sysctl -n ${attribute}\" failed}"

    if [ ! "${value}" -eq "${result}" ]; then
        echo "Failure: \"sysctl -n ${attribute}\" returned \"${result}\", not \"${value}\" as expected."
        exit
    fi
}

function create_cluster() {
    ###########################################################################
    # Description:                                                            #
    # Create kind cluster                                                     #
    #                                                                         #
    # Arguments:                                                              #
    #   arg1: cluster name                                                    #
    #   arg2: IP family                                                       #
    #   arg3: artifacts directory                                             #
    #   arg4: ci_mode                                                         #
    #   arg5: backend                                                         #
    ###########################################################################
    #    [ $# -eq 4 ]
    #    if_error_exit "Wrong number of arguments to ${FUNCNAME[0]}"

    local cluster_name=${1}
    local ip_family=${2}
    local artifacts_directory=${3}
    local ci_mode=${4}
    local backend=${5}

    # Get rid of any old cluster with the same name.
    if kind get clusters | grep -q "${cluster_name}" &>/dev/null; then
        kind delete cluster --name "${cluster_name}" &>/dev/null
        if_error_exit "cannot delete cluster ${cluster_name}"

        pass_message "Previous cluster ${cluster_name} deleted."
    fi

    # Default Log level for all components in test clusters
    local kind_cluster_log_level=${KIND_CLUSTER_LOG_LEVEL:-4}
    local kind_log_level="-v3"
    if [ "${ci_mode}" = true ]; then
        kind_log_level="-v7"
    fi

    # potentially enable --logging-format
    local scheduler_extra_args="      \"v\": \"${kind_cluster_log_level}\""
    local controllerManager_extra_args="      \"v\": \"${kind_cluster_log_level}\""
    local apiServer_extra_args="      \"v\": \"${kind_cluster_log_level}\""

    if [ -n "$CLUSTER_LOG_FORMAT" ]; then
        scheduler_extra_args="${scheduler_extra_args}\"logging-format\": \"${CLUSTER_LOG_FORMAT}\""
        controllerManager_extra_args="${controllerManager_extra_args}\"logging-format\": \"${CLUSTER_LOG_FORMAT}\""
        apiServer_extra_args="${apiServer_extra_args}\"logging-format\": \"${CLUSTER_LOG_FORMAT}\""
    fi

    echo -e "\nPreparing to setup ${cluster_name}"

    # Adjust the kind config based on the backend matrix
    if [ "${backend}" == "kubeproxy" ]; then
        echo -e "\nSetting up the cluster with a backend of ${backend}"
        cat <<EOF >"${artifacts_directory}/kind-config.yaml"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  ipFamily: ipv4
  apiServerAddress: "0.0.0.0"
EOF
      fi

    # Adjust the kind config based on the backend matrix
    if [ "${backend}" == "kpng" ]; then
        echo -e "\nSetting up the cluster with a backend of ${backend}"
        cat <<EOF >"${artifacts_directory}/kind-config.yaml"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: patu
networking:
  ipFamily: ipv4
  kubeProxyMode: "none"
  apiServerAddress: "0.0.0.0"
  disableDefaultCNI: true
  podSubnet: 10.200.0.0/16
  #serviceSubnet: 10.300.0.0/16
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "kube-proxy=kpng"
            authorization-mode: "AlwaysAllow"
EOF
    fi

    # TODO: add an ENV option for deploying with the configuration file(s) locations
    # Copy installer script and deployment files for installer
    mkdir -p patu/deploy/
    cp $HOME/work/patu/patu/deploy/* patu/deploy/
    cp $HOME/work/patu/patu/scripts/installer/patu-installer ${bin_dir}
    # Copy installer script and deployment files for installer in e2e
    mkdir -p $HOME/work/patu/patu/test/e2e/patu/deploy
    cp $HOME/work/patu/patu/deploy/* $HOME/work/patu/patu/test/e2e/patu/deploy/

    # Install Kubeproxy backend matrix
    if [ "${backend}" == "kubeproxy" ]; then
        echo -e "\n${backend} backend detected ..."
        kind create cluster \
            --name "${cluster_name}" \
            --image "${KINDEST_NODE_IMAGE}":"${E2E_K8S_VERSION}" \
            --retain \
            --wait=1m \
            "${kind_log_level}" \
            "--config=${artifacts_directory}/kind-config.yaml"
        if_error_exit "cannot create kind cluster ${cluster_name}"
        # Patch kube-proxy to set the verbosity level
        kubectl patch -n kube-system daemonset/kube-proxy \
            --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/command/-", "value": "--v='"${kind_cluster_log_level}"'" }]'

        # Install Patu using the installer
        KUBECONFIG=${HOME}/.kube/config patu-installer apply cni
        if_error_exit "Failed to install Patu"
    fi

    # Install KPNG backend matrix
    if [ "${backend}" == "kpng" ]; then
        echo -e "\n${backend} backend detected ..."
        kind create cluster \
            --name "${cluster_name}" \
            --image "${KINDEST_NODE_IMAGE}":"${E2E_K8S_VERSION}" \
            --retain \
            --wait=1m \
            "${kind_log_level}" \
        "--config=${artifacts_directory}/kind-config.yaml"
        if_error_exit "cannot create kind cluster ${cluster_name}"

        # Install Patu using the installer
        KUBECONFIG=${HOME}/.kube/config patu-installer apply all
        if_error_exit "Failed to install Patu"
    fi

    # Patch kube-proxy to set the verbosity level
    kubectl patch -n kube-system daemonset/kube-proxy \
        --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/command/-", "value": "--v='"${kind_cluster_log_level}"'" }]'

    kind get kubeconfig --internal --name "${cluster_name}" >"${artifacts_directory}/kubeconfig.conf"
    kind get kubeconfig --name "${cluster_name}" >"${artifacts_directory}/${KUBECONFIG_TESTS}"

    # IPv6 clusters need some CoreDNS changes in order to work in k8s CI:
    # 1. k8s CI doesn´t offer IPv6 connectivity, so CoreDNS should be configured
    # to work in an offline environment:
    # https://github.com/coredns/coredns/issues/2494#issuecomment-457215452
    # 2. k8s CI adds following domains to resolv.conf search field:
    # c.k8s-prow-builds.internal google.internal.
    # CoreDNS should handle those domains and answer with NXDOMAIN instead of SERVFAIL
    # otherwise pods stops trying to resolve the domain.
    #
    if [ "${ip_family}" = "ipv6" ]; then
        local k8s_context="kind-${cluster_name}"
        # Get the current config
        local original_coredns=$(kubectl --context "${k8s_context}" get -oyaml -n=kube-system configmap/coredns)
        echo "Original CoreDNS config:"
        echo "${original_coredns}"
        # Patch it
        local fixed_coredns=$(
            printf '%s' "${original_coredns}" | sed \
                -e 's/^.*kubernetes cluster\.local/& internal/' \
                -e '/^.*upstream$/d' \
                -e '/^.*fallthrough.*$/d' \
                -e '/^.*forward . \/etc\/resolv.conf$/d' \
                -e '/^.*loop$/d'
        )
        echo "Patched CoreDNS config:"
        echo "${fixed_coredns}"
        printf '%s' "${fixed_coredns}" | kubectl --context "${k8s_context}" apply -f -
    fi

    # Wait on Patu to become ready
    kubectl --context "${k8s_context}" wait \
        --for=condition=ready \
        pods \
        --timeout=30s \
        --namespace=kube-system \
        --selector app=patu 1>/dev/null

    pass_message "Cluster ${cluster_name} is created."
}

function wait_until_cluster_is_ready() {
    ###########################################################################
    # Description:                                                            #
    # Wait pods with selector k8s-app=kube-dns be ready and operational       #
    #                                                                         #
    # Arguments:                                                              #
    #   arg1: cluster name                                                    #
    #   arg2: ci_mode                                                         #
    ###########################################################################

    [ $# -eq 2 ]
    if_error_exit "Wrong number of arguments to ${FUNCNAME[0]}"

    local cluster_name=${1}
    local ci_mode=${2}
    local k8s_context="kind-${cluster_name}"
    local namespace="kube-system"

    kubectl --context "${k8s_context}" wait \
        --for=condition=ready \
        pods \
        --namespace="${namespace}" \
        --selector component=etcd 1>/dev/null

    if [ "${ci_mode}" = true ]; then
        kubectl --context "${k8s_context}" get nodes -o wide
        if_error_exit "unable to show nodes"

        kubectl --context "${k8s_context}" get pods --all-namespaces
        if_error_exit "error getting pods from all namespaces"
    fi

    pass_message "${cluster_name} is operational."
}

function create_infrastructure_and_run_tests() {
    ###########################################################################
    # Description:                                                            #
    # create_infrastructure_and_run_tests                                     #
    #                                                                         #
    # Arguments:                                                              #
    #   arg1: Path for E2E installation directory                             #
    #   arg2: ip_family                                                       #
    #   arg3: backend                                                         #
    #   arg4: e2e_test                                                        #
    #   arg5: suffix                                                          #
    #   arg6: developer_mode                                                  #
    #   arg7: <ci_mode>                                                         #
    ###########################################################################

    [ $# -eq 7 ]
    if_error_exit "Wrong number of arguments to ${FUNCNAME[0]}"

    local e2e_dir="${1}"
    local ip_family="${2}"
    local backend="${3}"
    local e2e_test="${4}"
    local suffix="${5}"
    local devel_mode="${6}"
    local ci_mode="${7}"

    local artifacts_directory="${e2e_dir}/artifacts"
    local cluster_name="patu-e2e-${ip_family}-${backend}${suffix}"

    export E2E_DIR="${e2e_dir}"
    export E2E_ARTIFACTS="${artifacts_directory}"
    export E2E_CLUSTER_NAME="${cluster_name}"
    export E2E_IP_FAMILY="${ip_family}"
    export E2E_BACKEND="${backend}"
    export E2E_DIR="${e2e_dir}"
    export E2E_ARTIFACTS="${artifacts_directory}"

    [ -d "${artifacts_directory}" ]
    if_error_exit "Directory \"${artifacts_directory}\" does not exist"

    [ -f "${e2e_test}" ]
    if_error_exit "File \"${e2e_test}\" does not exist"

    echo "${cluster_name}"

    create_cluster "${cluster_name}" "${ip_family}" "${artifacts_directory}" "${ci_mode}" "${backend}"
    wait_until_cluster_is_ready "${cluster_name}" "${ci_mode}"

    echo "${cluster_name}" >"${e2e_dir}"/clustername
}

function delete_kind_clusters() {
    ###########################################################################
    # Description:                                                            #
    # create_infrastructure_and_run_tests                                     #
    #                                                                         #
    # Arguments:                                                              #
    #   arg1: bin_directory                                                   #
    #   arg2: ip_family                                                       #
    #   arg3: backend                                                         #
    #   arg4: suffix                                                          #
    #   arg5: cluser_count                                                    #
    ###########################################################################
    echo "+==================================================================+"
    echo -e "\t\tErasing kind clusters"
    echo "+==================================================================+"

    [ $# -eq 5 ]
    if_error_exit "Wrong number of arguments to ${FUNCNAME[0]}"

    # setting up variables
    local bin_directory="${1}"
    local ip_family="${2}"
    local backend="${3}"
    local suffix="${4}"
    local cluster_count="${5}"

    add_to_path "${bin_directory}"

    [ "${cluster_count}" -ge "1" ]
    if_error_exit "cluster_count must be larger or equal to one"

    local cluster_name_base="patu-e2e-${ip_family}-${backend}"

    if [ "${cluster_count}" -eq "1" ]; then
        local tmp_suffix=${suffix:+"-${suffix}"}
        delete_kind_cluster "${cluster_name_base}${tmp_suffix}"
    else
        for i in $(seq "${cluster_count}"); do
            local tmp_suffix="-${suffix}${i}"
            delete_kind_cluster "${cluster_name_base}${tmp_suffix}"
        done
    fi
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

    if ${erase_clusters}; then
        delete_kind_clusters "${bin_dir}" "${ip_family}" "${backend}" "${suffix}" "${cluster_count}"
        exit 1
    fi

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
        set_host_network_settings "${ip_family}"
    fi

    install_binaries "${bin_dir}" "${E2E_K8S_VERSION}" "${OS}"
    # compile bpf bytecode and bindings so build completes successfully
    # TODO: sort out if the patu/kpng needs any extra bpf support than existing packages
    if [ "${backend}" == "ebpf" ]; then
        compile_bpf
    fi

    verify_host_network_settings "${ip_family}"

    if [ "${cluster_count}" -eq "1" ]; then
        local tmp_suffix=${suffix:+"-${suffix}"}
        set_e2e_dir "${e2e_dir}${tmp_suffix}" "${bin_dir}"
    else
        for i in $(seq "${cluster_count}"); do
            local tmp_suffix="-${suffix}${i}"
            set_e2e_dir "${e2e_dir}${tmp_suffix}" "${bin_dir}"
        done
    fi

    # preparation completed, time to setup infrastructure and run tests
    if [ "${cluster_count}" -eq "1" ]; then
        local tmp_suffix=${suffix:+"-${suffix}"}
        create_infrastructure_and_run_tests "${e2e_dir}${tmp_suffix}" "${ip_family}" "${backend}" \
            "${bin_dir}/e2e.test" "${tmp_suffix}" "${devel_mode}" "${ci_mode}"
    else
        local pids

        echo -e "\n+====================================================================================================+"
        echo -e "\t\tRunning parallel KPNG E2E tests \"-i ${ip_family} -b ${backend}\" in background on ${cluster_count} kind clusters."
        echo -e "+====================================================================================================+"

        for i in $(seq "${cluster_count}"); do
            local tmp_suffix="-${suffix}${i}"
            local output_file="${e2e_dir}${tmp_suffix}/output.log"
            rm -f "${output_file}"
            create_infrastructure_and_run_tests "${e2e_dir}${tmp_suffix}" "${ip_family}" "${backend}" \
                "${bin_dir}/e2e.test" "${tmp_suffix}" "${devel_mode}" "${ci_mode}" \
                &>"${e2e_dir}${tmp_suffix}/output.log" &
            pids[${i}]=$!
        done
        for pid in ${pids[*]}; do # not possible to use quotes here
            wait ${pid}
        done
        if ! ${devel_mode}; then
            print_reports "${ip_family}" "${backend}" "${e2e_dir}" "-${suffix}" "${cluster_count}"
        fi
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
    printf "\t-i set ip_family(ipv4/ipv6/dual) name in the e2e test runs.\n"
    printf "\t-b set backend (kubeproxy/kpng) name in the e2e test runs. \n"
    printf "\t-c flag allows for ci_mode. Please don't run on local systems.\n"
    printf "\t-d devel mode, creates the test env but skip e2e tests. Useful for debugging.\n"
    printf "\t-e erase kind clusters.\n"
    printf "\t-n number of parallel test clusters.\n"
    printf "\t-s suffix, will be appended to the E2@ directory and kind cluster name (makes it possible to run parallel tests.\n"
    printf "\t-B binary directory, specifies the path for the directory where binaries will be installed\n"
    printf "\t-D Dockerfile, specifies the path of the Dockerfile to use\n"
    printf "\t-E set E2E directory, specifies the path for the E2E directory\n"
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

if [[ "${cluster_count}" -lt "1" ]]; then
    echo "Cluster count must be larger or equal to 1"
    help
fi
if [[ "${cluster_count}" -lt "2" ]] && ${print_report}; then
    echo "Cluster count must be larger or equal to 2 when printing reports"
    help
fi

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
