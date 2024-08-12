FROM quay.io/fedora/fedora-bootc:40

RUN dnf install -y cockpit cockpit-ostree cockpit-podman cockpit-storaged cockpit-ws cockpit-machines cockpit-selinux bash-completion git wget && dnf clean all

RUN systemctl enable podman-auto-update.timer cockpit.socket

RUN mkdir -p /motioneye/config /motioneye/data /data

COPY ./motioneye.container /etc/containers/systemd/motioneye.container

COPY ./Ligons6.nmconnection /etc/NetworkManager/system-connections/Ligons6.nmconnection

