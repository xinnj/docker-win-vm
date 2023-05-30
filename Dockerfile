FROM archlinux:base
LABEL maintainer='xinnj@hotmail.com'

SHELL ["/bin/bash", "-c"]

# OPTIONAL: Arch Linux server mirrors for super fast builds
ARG MIRROR_COUNTRY=US

RUN curl -L -o /etc/pacman.d/mirrorlist "https://www.archlinux.org/mirrorlist/?country=${MIRROR_COUNTRY:-US}&protocol=https&use_mirror_status=on" \
    && sed -i -e 's/^#Server/Server/' -e '/^#/d' /etc/pacman.d/mirrorlist \
    && cat /etc/pacman.d/mirrorlist \
    && useradd arch -p arch \
    && usermod -a -G kvm arch \
    && tee -a /etc/sudoers <<< 'arch ALL=(ALL) NOPASSWD: ALL' \
    && mkdir -p /home/arch \
    && chown arch:arch /home/arch

RUN yes | pacman -Sy qemu-desktop virtiofsd sudo openssh swtpm xorg-server-xvfb xorg-xrandr expect --noconfirm \
    && yes | pacman -Scc

USER arch
WORKDIR /home/arch/win-vm

ADD --chown=arch:arch --chmod=755 ssh-expect /home/arch/win-vm/
ADD --chown=arch:arch --chmod=755 ssh-copy-id-win /home/arch/win-vm/

RUN touch Launch.sh \
    && chmod +x ./Launch.sh \
    && tee -a Launch.sh <<< '#!/bin/bash' \
    && tee -a Launch.sh <<< 'set -eux' \
    && tee -a Launch.sh <<< 'sudo touch /dev/kvm /dev/snd "${IMAGE_PATH}" 2>/dev/null || true' \
    && tee -a Launch.sh <<< 'sudo chown -R $(id -u):$(id -g) /dev/kvm /dev/snd "${IMAGE_PATH}" 2>/dev/null || true' \
    && tee -a Launch.sh <<< 'sudo chmod -R 777 /tmp/.X11-unix 2>/dev/null || true' \
    && tee -a Launch.sh <<< '[[ "${RAM}" = max ]] && export RAM="$(("$(head -n1 /proc/meminfo | tr -dc "[:digit:]") / 1000000"))"' \
    && tee -a Launch.sh <<< '[[ "${RAM}" = half ]] && export RAM="$(("$(head -n1 /proc/meminfo | tr -dc "[:digit:]") / 2000000"))"' \
    && tee -a Launch.sh <<< 'sudo chown -R $(id -u):$(id -g) /dev/snd 2>/dev/null || true' \
    && tee -a Launch.sh <<< 'cp -f /usr/share/edk2-ovmf/x64/OVMF_VARS.fd /home/arch/win-vm/' \
    && tee -a Launch.sh <<< 'sudo /usr/lib/virtiofsd --socket-path=/var/run/qemu-vm-001.sock --shared-dir=/mnt/hostshare --cache always --socket-group=kvm &' \
    && tee -a Launch.sh <<< 'mkdir -p /home/arch/win-vm/mytpm' \
    && tee -a Launch.sh <<< 'swtpm socket --tpm2 --tpmstate dir=/home/arch/win-vm/mytpm --ctrl type=unixio,path=/home/arch/win-vm/mytpm/swtpm-sock &' \
    && tee -a Launch.sh <<< 'printf -v macaddr "52:54:%02x:%02x:%02x:%02x" $(( $RANDOM & 0xff)) $(( $RANDOM & 0xff )) $(( $RANDOM & 0xff)) $(( $RANDOM & 0xff ))' \
    && tee -a Launch.sh <<< 'export INSTALL_ISO_DEVICE="-drive index=2,media=cdrom,file=${INSTALL_ISO_PATH}"' \
    && tee -a Launch.sh <<< '[[ "${INSTALL_ISO_PATH}" = none ]] && export INSTALL_ISO_DEVICE=""' \
    && tee -a Launch.sh <<< 'export DRIVER_ISO_DEVICE="-drive index=3,media=cdrom,file=${DRIVER_ISO_PATH}"' \
    && tee -a Launch.sh <<< '[[ "${DRIVER_ISO_PATH}" = none ]] && export DRIVER_ISO_DEVICE=""' \
    && tee -a Launch.sh <<< 'exec qemu-system-x86_64 -m ${RAM}G \' \
    && tee -a Launch.sh <<< '-cpu host,hv_relaxed,hv_spinlocks=0x1fff,hv_vapic,hv_time \' \
    && tee -a Launch.sh <<< '-machine q35 -accel kvm \' \
    && tee -a Launch.sh <<< '-smp ${CPU_STRING:-${SMP},cores=${CORES}} \' \
    && tee -a Launch.sh <<< '-usb -device usb-tablet \' \
    && tee -a Launch.sh <<< '-drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2-ovmf/x64/OVMF_CODE.fd \' \
    && tee -a Launch.sh <<< '-drive if=pflash,format=raw,file=/home/arch/win-vm/OVMF_VARS.fd \' \
    && tee -a Launch.sh <<< '-drive index=0,media=disk,if=virtio,file=${IMAGE_PATH},format=${IMAGE_FORMAT} \' \
    && tee -a Launch.sh <<< '${INSTALL_ISO_DEVICE} \' \
    && tee -a Launch.sh <<< '${DRIVER_ISO_DEVICE} \' \
    && tee -a Launch.sh <<< '-netdev user,id=net0,dnssearch=default.svc.cluster.local,dnssearch=svc.cluster.local,hostfwd=tcp::${INTERNAL_SSH_PORT}-:22,hostfwd=tcp::${SCREEN_SHARE_PORT}-:5900,${ADDITIONAL_PORTS} \' \
    && tee -a Launch.sh <<< '-device ${NETWORKING},netdev=net0,id=net0,mac=${MAC_ADDRESS:-$macaddr} \' \
    && tee -a Launch.sh <<< '-boot menu=on \' \
    && tee -a Launch.sh <<< '-vga std \' \
    && tee -a Launch.sh <<< '-monitor stdio \' \
    && tee -a Launch.sh <<< '-object memory-backend-memfd,id=mem,size=${RAM}G,share=on \' \
    && tee -a Launch.sh <<< '-numa node,memdev=mem \' \
    && tee -a Launch.sh <<< '-chardev socket,id=char0,path=/var/run/qemu-vm-001.sock \' \
    && tee -a Launch.sh <<< '-device vhost-user-fs-pci,chardev=char0,tag=myfs \' \
    && tee -a Launch.sh <<< '-chardev socket,id=chrtpm,path=/home/arch/win-vm/mytpm/swtpm-sock \' \
    && tee -a Launch.sh <<< '-tpmdev emulator,id=tpm0,chardev=chrtpm \' \
    && tee -a Launch.sh <<< '-device tpm-tis,tpmdev=tpm0 \' \
    && tee -a Launch.sh <<< '-rtc base=localtime \' \
    && tee -a Launch.sh <<< '${EXTRA:-}'

RUN mkdir -p ~/.ssh \
    && touch ~/.ssh/authorized_keys \
    && touch ~/.ssh/config \
    && chmod 700 ~/.ssh \
    && chmod 600 ~/.ssh/config \
    && chmod 600 ~/.ssh/authorized_keys

RUN touch Auto.sh \
    && chmod +x ./Auto.sh \
    && tee -a Auto.sh <<< '#!/bin/bash' \
    && tee -a Auto.sh <<< 'export DISPLAY=:99' \
    && tee -a Auto.sh <<< 'Xvfb ${DISPLAY} -screen 0 1920x1080x16 &' \
    && tee -a Auto.sh <<< 'until [[ "$(xrandr --query 2>/dev/null)" ]]; do sleep 1 ; done' \
    && tee -a Auto.sh <<< '[[ -s "${SSH_KEY}" ]] || {' \
    && tee -a Auto.sh <<< '  /usr/bin/ssh-keygen -t rsa -f "${SSH_KEY}" -q -N ""' \
    && tee -a Auto.sh <<< '  chmod 600 "${SSH_KEY}"' \
    && tee -a Auto.sh <<< '}' \
    && tee -a Auto.sh <<< '/bin/bash -c ./Launch.sh & echo "Booting Docker-win-vm in the background. Please wait..."' \
    && tee -a Auto.sh <<< 'for i in {1..20}; do' \
    && tee -a Auto.sh <<< '  ./ssh-copy-id-win 127.0.0.1 10022 ${USERNAME:=jenkins} ${PASSWORD:=Jenkins} "${SSH_KEY}.pub" > /dev/null' \
    && tee -a Auto.sh <<< '  if [[ "$?" == "0" ]]; then' \
    && tee -a Auto.sh <<< '    break' \
    && tee -a Auto.sh <<< '  else' \
    && tee -a Auto.sh <<< '    echo "Repeating until able to copy SSH key into win-vm..."' \
    && tee -a Auto.sh <<< '    if [[ "$i" == "20" ]]; then' \
    && tee -a Auto.sh <<< '      echo "Connect win-vm failed!"' \
    && tee -a Auto.sh <<< '      while killall -15 qemu-system-x86_64; do' \
    && tee -a Auto.sh <<< '        echo "Shutting down win-vm..."' \
    && tee -a Auto.sh <<< '        sleep 1' \
    && tee -a Auto.sh <<< '      done' \
    && tee -a Auto.sh <<< '      echo "Shutdown win-vm finished, exit."' \
    && tee -a Auto.sh <<< '      exit 1' \
    && tee -a Auto.sh <<< '    fi' \
    && tee -a Auto.sh <<< '    sleep 5' \
    && tee -a Auto.sh <<< '  fi' \
    && tee -a Auto.sh <<< 'done' \
    && tee -a Auto.sh <<< 'grep ${SSH_KEY} ~/.ssh/config || {' \
    && tee -a Auto.sh <<< '  tee -a ~/.ssh/config <<< "Host 127.0.0.1"' \
    && tee -a Auto.sh <<< '  tee -a ~/.ssh/config <<< "    User ${USERNAME:=jenkins}"' \
    && tee -a Auto.sh <<< '  tee -a ~/.ssh/config <<< "    Port 10022"' \
    && tee -a Auto.sh <<< '  tee -a ~/.ssh/config <<< "    IdentityFile ${SSH_KEY}"' \
    && tee -a Auto.sh <<< '  tee -a ~/.ssh/config <<< "    StrictHostKeyChecking no"' \
    && tee -a Auto.sh <<< '  tee -a ~/.ssh/config <<< "    UserKnownHostsFile=~/.ssh/known_hosts"' \
    && tee -a Auto.sh <<< '}' \
    && tee -a Auto.sh <<< 'sleep 5; echo "Execute on win-vm: ${WIN_COMMANDS}"' \
    && tee -a Auto.sh <<< 'ssh 127.0.0.1 "${WIN_COMMANDS}"'

ENV RAM=4
ENV INSTALL_ISO_PATH=none
ENV DRIVER_ISO_PATH=none
ENV HEADLESS=false
ENV SMP=4
ENV CORES=4
ENV IMAGE_PATH=/image
ENV IMAGE_FORMAT=qcow2
ENV INTERNAL_SSH_PORT=10022
ENV SCREEN_SHARE_PORT=5900
ENV ADDITIONAL_PORTS=
ENV NETWORKING=virtio-net-pci
ENV SSH_KEY=/home/arch/.ssh/id_docker_win
ENV WIN_COMMANDS=

CMD if [[ "${HEADLESS}" = true ]]; then ./Auto.sh; else ./Launch.sh; fi
