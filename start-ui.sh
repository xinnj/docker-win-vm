#!/bin/bash
set -e

base=`dirname $0`
if [[ "$#" -lt "1" ]]; then
    echo "Usage: `basename $0` <image file> [shared path] [driver iso file] [install iso file]"
    exit 1
fi

imageFile=$1

sharedPath=""
if [[ ! -z "$2" ]]; then
    sharedPath="-v \"$2:/mnt/hostshare\" -e HOST_SHARE=/mnt/hostshare"
fi

driverIso=""
if [[ ! -z "$3" ]]; then
    driverIso="-v \"$3:/virtio-win.iso\" -e DRIVER_ISO_PATH=/virtio-win.iso"
fi

installIso=""
if [[ ! -z "$4" ]]; then
    installIso="-v \"$4:/install.iso\" -e INSTALL_ISO_PATH=/install.iso"
fi

xhost +

podman run -d --name win-vm --rm \
    --privileged \
    --device /dev/kvm \
    -v "${imageFile}:/image" \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -e "DISPLAY=${DISPLAY:-:0.0}" \
    -e RAM=6 \
    ${driverIso} \
    ${installIso} \
    ${sharedPath} \
    docker.io/xinnj/docker-win-vm
