FROM quay.io/fedora/fedora-bootc:40-x86_64

RUN dnf install -y NetworkManager-wwan NetworkManager-wifi cockpit cockpit-ostree cockpit-podman cockpit-storaged cockpit-ws wpa_supplicant cockpit-selinux cockpit-pcp iwlwifi-mvm-firmware openssl  bash-completion git wget && dnf clean all

ADD wheel-passwordless-sudo /etc/sudoers.d/wheel-passwordless-sudo

RUN mkdir -p /motioneye/config /motioneye/data /data

RUN systemctl enable podman-auto-update.timer cockpit.socket

COPY ./motioneye.container /etc/containers/systemd/motioneye.container
