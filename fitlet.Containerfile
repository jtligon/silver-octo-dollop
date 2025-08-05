FROM quay.io/fedora/fedora-bootc:42-x86_64

RUN dnf install -y --skip-unavailable cockpit cockpit-ostree cockpit-podman cockpit-storaged cockpit-ws wpa_supplicant cockpit-selinux iwlwifi-mvm-firmware git wget intel-media-driver libva-intel-driver mesa-dri-drivers && dnf clean all

RUN mkdir -p /usr/lib/ostree && \
    echo 'ostree_prepare_root_enabled=1' > /usr/lib/ostree/prepare-root.conf

ADD wheel-passwordless-sudo /etc/sudoers.d/wheel-passwordless-sudo

RUN mkdir -p /motioneye/config /motioneye/data /data

RUN systemctl enable podman-auto-update.timer cockpit.socket

COPY ./mycustom-user.conf /usr/lib/sysusers.d/mycustom-user.conf

COPY ./motioneye.container /etc/containers/systemd/motioneye.container

COPY ./oneShot.unit /etc/systemd/system/ssh-key-import.service
RUN systemctl enable ssh-key-import.service

RUN bootc container lint