#!/usr/bin/env bash

# This script will prepare two directories for netbooting Alpine Linux to a Raspberry Pi 4B.
# One directory should be served over TFTP, the other over HTTP
#
# The process is heavily "inspired" by https://gist.github.com/erincandescent/c3266fc3cbb7fe21be0ab1def7adbc48
# and https://wiki.alpinelinux.org/wiki/Raspberry_Pi_-_Headless_Installation


#####
# change these values to match your setup
VERSION=3.12
RELEASE=1
TFTP_IP=192.168.1.2
HTTP_IP=192.168.1.2

MODULES_INITRAMFS=("net/packet/af_packet.ko") # af_packet.ko is necessary, add additional if required

#####
# download the release, if not already present
REL_TAR=alpine-rpi-${VERSION}.${RELEASE}-aarch64.tar.gz
WORKDIR=$(pwd)
if [ ! -e ${REL_TAR} ]
then
	wget http://dl-cdn.alpinelinux.org/alpine/v${VERSION}/releases/aarch64/${REL_TAR}
fi


#####
# create files to be served over TFTP
echo "* preparing TFTP folder"
cd ${WORKDIR}
mkdir tftp; cd tftp
tar xvzf ../${REL_TAR} ./start4.elf # primary bootloader
tar xvzf ../${REL_TAR} ./fixup4.dat # SDRAM setup
tar xvzf ../${REL_TAR} ./bcm2711-rpi-4-b.dtb # device tree blob
tar xvzf ../${REL_TAR} ./boot/vmlinuz-rpi4 # kernel
ln -s boot/vmlinuz-rpi4

# the initramfs needs af_packet.ko added:
tar xvzf ../${REL_TAR} ./boot/modloop-rpi4 # kernel modules
tar xvzf ../${REL_TAR} ./boot/initramfs-rpi4 # initramfs
mkdir modloop-rpi4
unsquashfs -d modloop-rpi4/lib boot/modloop-rpi4 'modules/*/modules.*'
for mod in "${MODULES_INITRAMFS[@]}"
do
	unsquashfs -f -d modloop-rpi4/lib boot/modloop-rpi4 "modules/*/kernel/${mod}"
done
(cd modloop-rpi4 && find . | cpio -H newc -ov | gzip) > initramfs-ext-rpi4
cat boot/initramfs-rpi4 initramfs-ext-rpi4 > initramfs-rpi4-netboot

cat << EOF >> config.txt
[pi4]
kernel=vmlinuz-rpi4
initramfs initramfs-rpi4-netboot
arm_64bit=1
EOF

cat << EOF >> cmdline.txt
modules=loop,squashfs console=ttyS0,115200 ip=dhcp alpine_repo=http://${HTTP_IP}/alpine/v${VERSION}/main apkovl=http://${HTTP_IP}/alpine/v${VERSION}/main/overlay.tar.gz
EOF

cat << EOF >> dnsmasq_tftpserver.sh
#!/usr/bin/env bash
sudo dnsmasq -kd -p 0 -C /dev/null -u nobody --enable-tftp --tftp-root=$(pwd)
EOF
chmod +x dnsmasq_tftpserver.sh


#####
# create files to be served over HTTP
echo "* preparing HTTP folder"
cd ${WORKDIR}
tar xvzf ${REL_TAR} ./apks/
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
echo "* creating initial overlay"
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

	auto eth0
	iface eth0 inet dhcp
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
chmod +x python3_httpserver.sh


#####
# DONE!
echo
echo "Now serve both 'tftp' and 'http' folders (with the included dnsmasq/python scripts, or your favorite deamon) and power up the Raspberry Pi."
echo "you@machine: tftp$ ./dnsmasq_tftpserver.sh"
echo "and in another terminal:"
echo "you@machine: http$ ./python3_httpserver.sh"
