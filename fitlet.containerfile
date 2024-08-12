FROM quay.io/fedora/fedora-bootc:40

RUN dnf install -y cockpit cockpit-podman cockpit-storaged cockpit-ws cockpit-machines cockpit-selinux bash-completion git wget && dnf clean all

RUN systemctl enable podman-auto-update.timer cockpit.socket

RUN mkdir -p /motioneye/config /motioneye/data /data


COPY [unpackaged application]
COPY [configuration files]
