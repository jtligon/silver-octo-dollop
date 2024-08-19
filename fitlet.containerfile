FROM quay.io/fedora/fedora-bootc:40

RUN dnf install -y cockpit cockpit-ostree cockpit-podman cockpit-storaged cockpit-ws cockpit-machines cockpit-selinux ssh-import-id bash-completion git wget && dnf clean all

RUN systemctl enable podman-auto-update.timer cockpit.socket

COPY mycustom-user.conf /usr/lib/sysusers.d

# Where does this go? after systemd makes the user?
# RUN mkdir -p /var/home/jligon/.ssh
# RUN wget http://keys.github.com/jtligon/??? /var/home/jligon/.ssh/authorized_keys
# RUN ssh-import-id-gh jtligon

RUN mkdir -p /motioneye/config /motioneye/data /data

COPY ./motioneye.container /etc/containers/systemd/motioneye.container

COPY ./Ligons6.nmconnection /etc/NetworkManager/system-connections/Ligons6.nmconnection

