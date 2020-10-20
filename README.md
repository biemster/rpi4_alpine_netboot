# Netboot Alpine Linux on Raspberry Pi 4
This script will set up two folders, one to be served over TFTP, and the other over HTTP. The rpi4 will boot without SD card, or any storage attached.

## Steps
The procedure consists of 4 steps:
1. Prepare the Raspberry Pi 4
2. Run the `...` script to set up the TFTP and HTTP folders
3. configure the TFTP server
4. configure the HTTP server

## Prerequisities
Three variables need to be set at the top of the script:

`VERSION`: the Alpine Linux version to be installed

`TFTP_IP`: the IP address of the TFTP server

`HTTP_IP`: the IP address of the HTTP server (both TFTP and HTTP servers can run on the same machine/IP)
