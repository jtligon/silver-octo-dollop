FROM quay.io/fedora/fedora-bootc:41

RUN dnf install -y cockpit cockpit-ostree cockpit-podman cockpit-storaged cockpit-ws wpa_supplicant cockpit-selinux iwlwifi-mvm-firmware openssl  bash-completion git wget && dnf clean all

ADD wheel-passwordless-sudo /etc/sudoers.d/wheel-passwordless-sudo

RUN mkdir -p /motioneye/config /motioneye/data /data

RUN systemctl enable podman-auto-update.timer cockpit.socket

COPY ./motioneye.container /etc/containers/systemd/motioneye.container

COPY ./install-config.toml /usr/lib/bootc/install/00-fedora.toml