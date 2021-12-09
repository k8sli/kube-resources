#!/bin/bash

: ${KUBE_VERSION:=v1.22.4}
: ${CALICO_VERSION:=v3.19.1}
: ${SKOPEO_VERSION:=v1.4.1}

function install_skopeo(){
    if ./skopeo --version 2>/dev/null; then
        echo "skopeo already installed"
    else
        echo "Installing skopeo"
        wget -q -k https://github.com/k8sli/skopeo/releases/download/${SKOPEO_VERSION}/skopeo-linux-amd64 -O ./skopeo
        chmod +x ./skopeo
    fi
}

function skopeo_copy(){
    local source_image=$1
    local target_image=$2
    if ./skopeo --insecure-policy copy --src-tls-verify=false docker://${source_image} --additional-tag ${source_image} docker-archive:${target_image}; then
        echo "Successfully copied ${source_image} to ${target_image}"
    else
        echo "Failed to copy ${source_image} to ${target_image}"
        exit 1
    fi
}

function download_files(){
    for file in kubeadm kubectl kubelet; do
        wget -q -k https://dl.k8s.io/${KUBE_VERSION}/bin/linux/amd64/${file} -O kube/bin/${file}
    done
    wget -q -k https://github.com/kubernetes-sigs/cri-tools/releases/download/${KUBE_VERSION%.*}.0/crictl-${KUBE_VERSION%.*}.0-linux-amd64.tar.gz
    tar -xzf crictl-${KUBE_VERSION%.*}.0-linux-amd64.tar.gz -C kube/bin/
    chmod +x kube/bin/*
}

function download_images(){
    for image in kube-{apiserver,controller-manager,proxy,scheduler}; do
        skopeo_copy k8s.gcr.io/${image}:${KUBE_VERSION} kube/images/${image}-${KUBE_VERSION}.tar
    done

    for image in $(./kube/bin/kubeadm config images list --kubernetes-version ${KUBE_VERSION} | grep -v '/kube-'); do
        image_tar="$(echo ${image} | awk -F'/' '{print $NF}' | tr ':' '-').tar"
        skopeo_copy ${image} kube/images/${image_tar}
    done

    for image in node cni pod2daemon-flexvol kube-controllers; do
        image_tar="kube/images/calico-${image}-${CALICO_VERSION}.tar"
        skopeo_copy quay.io/calico/${image}:${CALICO_VERSION} ${image_tar}
    done
    skopeo_copy docker.io/fanux/lvscare:latest kube/images/lvscare.tar
}

function main(){
    rm -rf kube
    mkdir -p kube/{images,bin}
    install_skopeo
    download_files
    download_images
}

main "$@"
