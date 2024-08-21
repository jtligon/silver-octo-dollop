FROM registry.gitlab.com/fedora/bootc/base-images/fedora-bootc-minimal:40-amd64

RUN dnf install -y cockpit cockpit-ostree cockpit-podman cockpit-storaged cockpit-ws cockpit-machines cockpit-selinux bash-completion git wget && dnf clean all

# can't do this as its not in fedora
# RUN dnf install -y ssh-import-id && dnf clean all
# COPY ./oneShot.unit /etc/systemd/system/ssh-import-id.service
# RUN systemctl enable ssh-import-id.service

ADD wheel-passwordless-sudo /etc/sudoers.d/wheel-passwordless-sudo

COPY mycustom-user.conf /usr/lib/sysusers.d

RUN mkdir -p /motioneye/config /motioneye/data /data

RUN systemctl enable podman-auto-update.timer cockpit.socket

COPY ./motioneye.container /etc/containers/systemd/motioneye.container

COPY ./Ligons6.nmconnection /etc/NetworkManager/system-connections/Ligons6.nmconnection

