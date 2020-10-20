#!/usr/bin/env bash

# This script will prepare two directories for netbooting Alpine Linux to a Raspberry Pi 4B.
# One directory should be served over TFTP, the other over HTTP
#
# The process is heavily "inspired" by https://gist.github.com/erincandescent/c3266fc3cbb7fe21be0ab1def7adbc48
# and https://wiki.alpinelinux.org/wiki/Raspberry_Pi_-_Headless_Installation


#####
# change these values to match your setup
VERSION=3.12
RELEASE=0
TFTP_IP=192.168.1.2
HTTP_IP=192.168.1.2

#####
# download the release, if not already present
REL_TAR=alpine-rpi-v${VERSION}.${RELEASE}-aarch64.tar.gz
WORKDIR=$(pwd)
if [ -e REL_TAR ]
then
	wget http://dl-cdn.alpinelinux.org/alpine/v${VERSION}/releases/aarch64/${REL_TAR}
fi


#####
# create files to be served over TFTP
cd ${WORKDIR}
mkdir tftp; cd tftp
tar xvzf ${REL_TAR} ./start4.elf # primary bootloader
tar xvzf ${REL_TAR} ./fixup4.dat # SDRAM setup
tar xvzf ${REL_TAR} ./bcm2711-rpi-4-b.dtb # device tree blob
tar xvzf ${REL_TAR} ./boot/vmlinux-rpi4 # kernel
ln -s boot/vmlinux-rpi4

# the initramfs needs af_packet.ko added:
tar xvzf ${REL_TAR} ./boot/modloop-rpi4 # kernel
mkdir modloop-rpi4
unsquashfs -d modloop-rpi4/lib boot/modloop-rpi4 'modules/*/modules.*' 'modules/*/kernel/net/packet/af_packet.ko'
(cd modloop-rpi4 && find . | cpio -H newc -ov | gzip) > initramfs-ext-rpi4
cat boot/initramfs-rpi4 initramfs-ext-rpi4 > initramfs-rpi4-netboot

cat << EOF >> config.txt
[pi4]
kernel=vmlinuz-rpi4
initramfs initramfs-rpi4-netboot
arm_64bit=1
EOF

cat << EOF >> cmdline.txt
modules=loop,squashfs,sd-mod,usb-storage console=ttyS0,115200 ip=dhcp alpine_repo=http://${HTTP_IP}/ apkovl=http://${HTTP_IP}/overlay.tar.gz
EOF

cat << EOF >> dnsmasq_tftpserver.sh
#!/usr/bin/env bash
sudo dnsmasq -kd -p 0 -C /dev/null -u nobody --enable-tftp --tftp-root=$(pwd)
EOF
chmod -x dnsmasq_tftpserver.sh


#####
# create files to be served over HTTP
cd ${WORKDIR}
tar xvzf ${REL_TAR} ./apks/aarch/APKINDEX.tar.gz
tar xvzf ${REL_TAR} ./apks/aarch/alpine-base-3.12.0-r0.apk
tar xvzf ${REL_TAR} ./apks/aarch/alpine-baselayout-3.2.0-r6.apk
tar xvzf ${REL_TAR} ./apks/aarch/alpine-conf-3.9.0-r1.apk
tar xvzf ${REL_TAR} ./apks/aarch/alpine-keys-2.2-r0.apk
tar xvzf ${REL_TAR} ./apks/aarch/apk-tools-2.10.5-r1.apk
tar xvzf ${REL_TAR} ./apks/aarch/busybox-1.31.1-r16.apk
tar xvzf ${REL_TAR} ./apks/aarch/busybox-initscripts-3.2-r2.apk
tar xvzf ${REL_TAR} ./apks/aarch/busybox-suid-1.31.1-r16.apk
tar xvzf ${REL_TAR} ./apks/aarch/ca-certificates-bundle-20191127-r2.apk
tar xvzf ${REL_TAR} ./apks/aarch/libc-utils-0.7.2-r3.apk
tar xvzf ${REL_TAR} ./apks/aarch/libcrypto1.1-1.1.1g-r0.apk
tar xvzf ${REL_TAR} ./apks/aarch/libedit-20191231.3.1-r0.apk
tar xvzf ${REL_TAR} ./apks/aarch/libssl1.1-1.1.1g-r0.apk
tar xvzf ${REL_TAR} ./apks/aarch/libtls-standalone-2.9.1-r1.apk
tar xvzf ${REL_TAR} ./apks/aarch/musl-1.1.24-r8.apk
tar xvzf ${REL_TAR} ./apks/aarch/musl-utils-1.1.24-r8.apk
tar xvzf ${REL_TAR} ./apks/aarch/ncurses-libs-6.2_p20200523-r0.apk
tar xvzf ${REL_TAR} ./apks/aarch/ncurses-terminfo-base-6.2_p20200523-r0.apk
tar xvzf ${REL_TAR} ./apks/aarch/openrc-0.42.1-r10.apk
tar xvzf ${REL_TAR} ./apks/aarch/openssl-1.1.1g-r0.apk
tar xvzf ${REL_TAR} ./apks/aarch/openssh-8.3_p1-r0.apk
tar xvzf ${REL_TAR} ./apks/aarch/openssh-client-8.3_p1-r0.apk
tar xvzf ${REL_TAR} ./apks/aarch/openssh-keygen-8.3_p1-r0.apk
tar xvzf ${REL_TAR} ./apks/aarch/openssh-server-8.3_p1-r0.apk
tar xvzf ${REL_TAR} ./apks/aarch/openssh-server-common-8.3_p1-r0.apk
tar xvzf ${REL_TAR} ./apks/aarch/openssh-sftp-server-8.3_p1-r0.apk
tar xvzf ${REL_TAR} ./apks/aarch/scanelf-1.2.6-r0.apk
tar xvzf ${REL_TAR} ./apks/aarch/ssl_client-1.31.1-r16.apk
tar xvzf ${REL_TAR} ./apks/aarch/zlib-1.2.11-r3.apk
mv apks http


#####
# create overlay to allow passwordless root login over ssh
# └── etc
#     ├── .default_boot_services
#     ├── local.d
#     │   └── headless.start
#     └── runlevels
#         └── default
#             └── local -> /etc/init.d/local
cd ${WORKDIR}
OVERLAY_DIR=overlay_ssh
mkdir ${OVERLAY_DIR}; cd ${OVERLAY_DIR}

mkdir -p etc/local.d
cat << EOF >> etc/local.d/headless.start
#!/bin/sh

__create_eni()
{
	cat <<-EOF > /etc/network/interfaces
	auto lo
	iface lo inet loopback

	auto ${iface}
	iface ${iface} inet dhcp
	        hostname localhost
	EOF
}

__edit_ess()
{
	cat <<-EOF >> /etc/ssh/sshd_config
	PermitEmptyPasswords yes
	PermitRootLogin yes
	EOF
}

iface="eth0"
__create_eni
rc-service networking start

/sbin/setup-sshd -c openssh
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.orig
__edit_ess
rc-service sshd restart
mv /etc/ssh/sshd_config.orig /etc/ssh/sshd_config
EOF
chmod +x etc/local.d/headless.start

touch etc/.default_boot_services

mkdir -p etc/runlevels/default
cd etc/runlevels/default
ln -s /etc/init.d/local
cd ${WORKDIR}/${OVERLAY_DIR}
tar czvf overlay_ssh.tar.gz etc/
cd ${WORKDIR}/http
ln -s ../${OVERLAY_DIR}/overlay_ssh.tar.gz overlay.tar.gz

cat << EOF >> python3_httpserver.sh
#!/usr/bin/env bash
sudo python3 -m http.server 80
EOF
chmod -x python_httpserver.sh


#####
# DONE!
echo
echo "Now serve both 'tftp' and 'http' folders (with the included dnsmasq/python scripts, or your favorite deamon) and power up the Raspberry Pi."
echo "you@machine: tftp$ ./dnsmasq_tftpserver.sh"
echo "and in another terminal:"
echo "you@machine: http$ ./python3_httpserver.sh"
