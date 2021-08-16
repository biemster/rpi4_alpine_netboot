# Netboot Alpine Linux on Raspberry Pi 4
This script will set up two folders, one to be served over TFTP, and the other over HTTP. The rpi4 will boot without SD card, or any storage attached.
No NFS server is needed, and the Pi will run completely independent of network and storage after booting.

### Steps
The procedure consists of 4 steps:
1. Prepare the Raspberry Pi 4
2. Run the `create_tftp_http_dirs.sh` script to set up the TFTP and HTTP folders
3. serve the TFTP and HTTP folders with the application of your choice
4. do the initial setup of Alpine Linux on your Pi, and serve the newly created overlay in the HTTP folder
5. Optional: serve different overlays (configs) for each Pi you have
6. Optional: add kernel modules to the initramfs

### Prerequisites
Three variables need to be set at the top of the script:

`VERSION` and `RELEASE`: the Alpine Linux version and dot release to be installed. You can also specify `VERSION=latest-stable` and the script will always pull the last stable Alpine release.

`HTTP_IP`: the IP address of the HTTP server (both TFTP and HTTP servers can run on the same machine/IP,
and if you use the included script, this is the address of the machine you're currently on).

On top of setting these variables you need `python3` to serve the http folder, and `dnsmasq` to serve the tftp folder with the included scripts.
Alternatively you could use an HTTP server like apache or nginx, and a TFTP server like tftpd-hpa or atftpd.
Further the script is using `wget`, `tar`, `unsquashfs`, `cpio`, `gzip`, and `yq`, so check if those are available on your system.


## Step 1: Prepare the Raspberry Pi 4
With the Raspberry Pi 4, the bootloader resides in an on-board EEPROM, and not on the SD card anymore. More info here:
(https://www.raspberrypi.org/documentation/hardware/raspberrypi/bcm2711_bootloader_config.md)
make sure you familiarize yourself with this info. On top of that page is explained how to update your bootloader to the latest stable
version, follow these steps all up to, but not including, flashing the new bootloader to EEPROM.

Before flashing the latest bootloader we need to make two changes to the `bootconf.txt` file, which you should now have if you followed the steps.
We first need to add a line `TFTP_IP=<your tftp server ip goes here>` with the same ip address as used in the `create_tftp_http_dirs.sh` script.
Second we need to change `BOOT_ORDER` to something that puts the network boot first. I put `BOOT_ORDER=0xf12`, so I can fallback on a SD card boot if necessary.

Now apply the new configuration to the EEPROM image file and flash the bootloader, as explained on top of the linked page above. Now your Pi is ready to netboot!


## Step 2: Create the TFTP and HTTP folders
All the hard work in this step is already done by [erincandescent](https://gist.github.com/erincandescent/c3266fc3cbb7fe21be0ab1def7adbc48) (thanks!),
so this is simple for us. Just set the Alpine Linux version and your own TFTP and HTTP server ip addresses in the `create_tftp_http_dirs.sh` script and run it.


## Step 3: Serve the TFTP and HTTP folders
To serve the necessary files for the netboot process, open two terminal windows and navigate to the `tftp` and `http` folders you just created.

In the terminal that navigated to the TFTP folder use `$ ./dnsmasq_tftpserver.sh`

In the terminal that navigated to the HTTP folder use `$ ./python3_httpserver.sh`

Alternatively both can run in a single terminal as well: `user@pc rpi4_alpine_netboot$ tftp/dnsmasq_tftpserver.sh & http/python3_httpserver.sh`


## Step 4: Initial setup of Alpine Linux
When all went well and the Pi booted up, it's listening on SSH and accepting passwordless root login. The Alpine Wiki
(https://wiki.alpinelinux.org/wiki/Raspberry_Pi_-_Headless_Installation)
suggests that `setup-alpine` will not work, and the `/sbin/setup-*` scripts should be called individually. In my experience `setup-alpine` actually
works fine, so let's take the traditional route (fall back to the above link if the following does not work for you):

`# setup-alpine`

and fill in the required info when asked for it. After that, create a new user and have its home dir copied in the overlay later on:

```
adduser <USERNAME>
lbu include /home/<USERNAME>
```

and remove the local script service from the default user level:

```
rc-update del local default
rm /etc/local.d/headless.start
```

Now create a new overlay with your Pi all set up:

`lbu package`

and transfer your new overlay file to the `http` folder on the machine that serves it:

`user@webserver http$ scp root@<rpi_ip_here>:~/<hostname_of_pi>.apkovl.tar.gz .`

where `<hostname_of_pi>` is the hostname you have set during the setup phase using `setup-alpine`. Now remove the `overlay.tar.gz` symlink in the `http` directory
which still points to the initial overlay `overlay_ssh.tar.gz`, and recreate the symlink now pointing to the overlay you just created and downloaded:

`ln -s <hostname_of_pi>.apkovl.tar.gz overlay.tar.gz`

and reboot your Pi.


## Step 5: (Optional / Advanced) Create different overlays (configurations) for individual Pi's
In most cases, having multiple Pi's means they need to do different tasks. It is very useful to have different configurations sent to them,
instead of having one big 'one size fits all' overlay for all of them.
To achieve this, the individual Pi's need to be sent a unique `cmdline.txt` file pointing to a individual overlay tarball in the `apkovl` variable.
You might have noticed in the `dnsmasq` output or your TFTP server logs that the Pi is first searching for the start4.elf file in a subfolder
in the TFTP root:

```
...
tftp[5387] : file /home/biemster/rpi4_alpine_netboot/tftp/46e4bb06/start4.elf not found
...
```

This 8 digit subfolder (46e4bb06 in this case) is actually the serial number of the Pi that is trying to netboot.
Place a copy of the cmdline.txt in a subfolder that corresponds to the serial number of your Pi, and symlink the other
files of the TFTP root folder in this subfolder as well. Now you can specify in the `apkovl` variable in the `cmdline.txt`
which overlay tarball this specific Pi should boot, and don't forget to place that tarball in the `http` folder.


## Step 6: (Optional / Advanced) Add additional kernel modules to the initramfs
Undoubtedly you'll need additional kernel modules when you progress setting up your Pi. There are two options to do this, an easy option
with a bit of overhead (20MB), and an option without overhead which requires knowing exactly which modules are needed.

Option 1: Easy but with a bit of overhead. Add a symlink to the modloop to the `http` folder:
```
user@webserver http$ ln -s ../tftp/boot/modloop-rpi4
```
and add the following option to your `cmdline.txt`, right after `ip=dhcp` (don't forget to put in your http server ip, and correct the version):
```
modloop=http://<http_ip_goes_here>/alpine/v3.12/main/modloop-rpi4
```

Option 2: Requires exact list of needed modules, but adds no overhead. The modules need to be added to the `initramfs`,
in the `create_tftp_http_dirs.sh` script's `MODULES_INITRAMFS` variable, like this (SPI modules are taken as example):
```
MODULES_INITRAMFS=("net/packet/af_packet.ko" # af_packet.ko is necessary, add additional if required
	"drivers/spi")
```
