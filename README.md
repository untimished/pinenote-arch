# PineNote Arch Linux installation from Debian

Here are two methods to install Arch Linux on the PineNote's `os2` partition using the Debian installation on `os1`:

- Method 1: Using pacstrap from Debian (original method)
- Method 2: Using direct chroot from Arch ARM rootfs (alternative method)

## Method 1: Installation using pacstrap

These instructions are a rough guide to install Arch Linux to `os2` using the Debian installation on `os1`. They are pieced together from my shell history, so they haven't been tested.

### Preparation

#### Partitioning

```bash
sudo mkfs.ext4 /dev/disk/by-partlabel/os2
sudo mount /dev/disk/by-partlabel/os2 /mnt
```

#### Installation of `pacman` and `pacstrap`

```bash
sudo apt install pacman-package-manager arch-install-scripts

echo 'Server = http://mirror.archlinuxarm.org/$arch/$repo' |sudo tee -a /etc/pacman.d/mirrorlist

for repo in core extra community alarm; do
  printf "[%s]\nInclude = /etc/pacman.d/mirrorlist\n\n" "$repo"
done |sudo tee -a /etc/pacman.conf

sudo pacman-key --init

sed 's/^\[core\]$/&\nSigLevel = Never/' /etc/pacman.conf > /tmp/tmp.conf
sudo pacman -Sywdd --config /tmp/tmp.conf --noconfirm archlinuxarm-keyring 
sudo tar -C /usr/share/keyrings --strip-components=4 -xf /var/cache/pacman/pkg/archlinuxarm-keyring-*.pkg.tar.xz usr/share/pacman/keyrings/
rm /tmp/tmp.conf
sudo pacman-key --populate archlinuxarm
```

#### Installation
```bash
# Adapt to your needs
sudo pacstrap /mnt base mkinitcpio uboot-tools archlinuxarm-keyring linux-firmware sway waybar foot xournalpp openssh base-devel git go tmux \
 vulkan-panfrost wget networkmanager network-manager-applet greetd greetd-regreet squeekboard

# Obtain kernel. Either follow the instructions in build_kernel.sh or repurpose m-weigand's kernel (untested)
# TODO: Install kernel. dtb and Image go into /mnt/boot (e.g. /mnt/boot/$(uname -r)/ ), modules into /usr/lib/modules/$(uname -r)
# - /mnt/boot/extlinux/extlinux.conf
# - /mnt/boot/

# Configure hostname, locale, timezone (follow arch wiki)
# echo pinenote |sudo tee /mnt/etc/pinenote
# ln -s /etc/share/zoneinfo/Etc/UTC /mnt/etc/timezone
# Edit /etc/locale.{conf,gen} and run locale-gen

# Copy firmware from debian installation
sudo cp -rp /usr/lib/firmware/rockchip /mnt/usr/lib/firmware/
# TODO: maybe also broadcom firmware instead of linux-firmware

# Copy *AND ADAPT* pinenote preset from this repository
# /etc/mkinitcpio.d/pinenote.preset

# Copy other relevant files to /etc from this repository
# TODO: helper scripts (change waveforms, refresh screen, ...)

# Use the same home partition
echo '/dev/disk/by-partlabel/data /home              ext4   defaults' |sudo tee -a /mnt/etc/fstab

# chroot: set up accounts and create unitrd
sudo arch-chroot /mnt
$ passwd # set root password
$ groupadd nopasswdlogin
# Rather generous, consider removing some
$ useradd -MG adm,dialout,sudo,audio,video,plugdev,input,render,bluetooth,nopasswdlogin user
$ passwd user
$ # Add first rule `auth       sufficient   pam_succeed_if.so user ingroup nopasswdlogin` to /etc/pam.d/greetd
$ mkinitcpio --preset pinenote
$ mkimage -A arm64 -T ramdisk -n uInitrd -d /boot/initramfs-linux.img /boot/uInitrd.img
$ # maybe network manager stuff 
$ exit
$ sync && umount -R /mnt
```

## Method 2: Installation using Arch ARM rootfs

This should work with the caviat of the issues with NetworkManager and Sway described. The following is what I reassembled from my notes so it is untested, pls give this a go and give feedback.

As I was debugging some issues I had to mount and unmount chroot filesystems multiple times so I provide here a hand bash script (pine_chroot.sh) to do this quickly after the initial setup is done.

### Initial Setup
```bash
# Create working directory and download rootfs
mkdir ~/alarm-bootstrap &amp;&amp; cd ~/alarm-bootstrap
wget http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz

# Format and mount os2
sudo mkfs.ext4 /dev/disk/by-partlabel/os2
sudo mount /dev/disk/by-partlabel/os2 /mnt

# Extract rootfs
sudo tar xpf ArchLinuxARM-aarch64-latest.tar.gz -C /mnt
```

### Mount Filesystems and Copy Debian Files
```bash
# Mount necessary filesystems
sudo mount -t proc /proc /mnt/proc
sudo mount -t sysfs /sys /mnt/sys
sudo mount -o bind /dev /mnt/dev
sudo mount -o bind /dev/pts /mnt/dev/pts
sudo mount -o bind /run /mnt/run

# Copy firmware and configuration files
sudo cp -rp /usr/lib/firmware/rockchip /mnt/usr/lib/firmware/
sudo cp /etc/resolv.conf /mnt/etc/resolv.conf

# Copy udev rules
sudo cp /etc/udev/rules.d/10_change_calmatrix.rules /mnt/etc/udev/rules.d/
sudo cp /etc/udev/rules.d/20_change_device_size.rules /mnt/etc/udev/rules.d/
sudo cp /etc/udev/rules.d/30_rockchip_ebc.rules /mnt/etc/udev/rules.d/
sudo cp /etc/udev/rules.d/40_backlight.rules /mnt/etc/udev/rules.d/
sudo cp /etc/udev/rules.d/81-libinput-pinenote.rules /mnt/etc/udev/rules.d/

# Create home mount point
sudo mkdir -p /mnt/home
```

### System Configuration
I provided a pine_chroot.sh for quick chroot mount/umount in case of need.
```bash
# Enter chroot
sudo chroot /mnt /bin/bash
```

```bash
# Initialize pacman
pacman-key --init
pacman -Syu

# Configure locales
pacman -S glibc
echo "en_GB.UTF-8 UTF-8" >> /etc/locale.gen
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

# Set system locale
echo "LANG=en_GB.UTF-8" > /etc/locale.conf

bash # this will update locales in the session

# Install essential packages
# Basic system and development tools
pacman -S base-devel linux-firmware git wget networkmanager

#install wpa_supplicant wireless_tools
pacman -S wpa_supplicant wireless_tools

# E-ink display related (incomplete list)
pacman -S sway swaybg waybar foot xournalpp vim

# Display and input management
pacman -S greetd greetd-regreet squeekboard


```

### Kernel Setup

we are copying files over from debian so we exit chroot. For convenience, do not unmount all the chroot filesystem unless you need to reboot.
```bash
# Exit chroot first
exit

# Copy kernel files from Debian
sudo cp /boot/vmlinuz-6.12.0-rc2-pinenote-202410092341-00187-g5392aa8e3808 /mnt/boot/Image
sudo cp /boot/initrd.img-6.12.0-rc2-pinenote-202410092341-00187-g5392aa8e3808 /mnt/boot/uInitrd.img
sudo cp /boot/emergency/rk3566-pinenote-v1.2.dtb /mnt/boot/
sudo cp /boot/waveform_firmware_recovered /mnt/boot/

```
### Boot Configuration

```bash
sudo mkdir -p /mnt/boot/extlinux
sudo vim /mnt/boot/extlinux/extlinux.conf
````
with this content:
```
timeout 10
default pinenote
menu title Boot Menu

label pinenote
        linux /boot/Image
        initrd /boot/uInitrd.img
        fdt /boot/rk3566-pinenote-v1.2.dtb
        append root=/dev/mmcblk0p6 ignore_loglevel rw rootwait earlycon console=tty0 console=ttyS2,1500000n8 fw_devlink=off init=/sbin/init

```

### SETUP mkinitcpio (THIS DOES NOT WORK atm but it is not necessary)

We can rely on the debian kernel but this was an attempt to configure mkinitcpio:
```bash
# Enter chroot
sudo chroot /mnt /bin/bash

vim /etc/mkinitcpio.conf
```
Edit to suit this:
```
MODULES=(rockchip_ebc)
BINARIES=()
FILES=()
#
# mine had microcode (no need since we are in arm), 
HOOKS=(base udev autodetect modconf kms keyboard keymap block filesystems fsck) 
# and typefont is also not needed I think
```
then we can try and generate initramfs

```bash
mkinitcpio -P
```
this currently gives error missing rockhip_ebc!

We can proceed anyway thanks to the debian kernel that is already working.

### libinput config

```bash
sudo vim /mnt/etc/udev/rules.d/81-libinput-pinenote.rules
```
to add the additional settings
```
# downloaded from https://gitlab.com/hrdl/pinenote-shared/-/blob/main/etc/udev/rules.d/81-libinp
ut-pinenote.rules
# install to /etc/udev/rules.d
ACTION=="remove", GOTO="libinput_device_group_end"
KERNEL!="event[0-9]*", GOTO="libinput_device_group_end"

ATTRS{phys}=="?*", ATTRS{name}=="cyttsp5", ENV{LIBINPUT_DEVICE_GROUP}="pinenotetouch"
ATTRS{phys}=="?*", ATTRS{name}=="w9013 2D1F:0095 Stylus", ENV{LIBINPUT_DEVICE_GROUP}="pinenoteto
uch"

ATTRS{phys}=="?*", ATTRS{name}=="cyttsp5", ENV{LIBINPUT_CALIBRATION_MATRIX}="-1 0 1 0 -1 1"

# Additional PineNote-specific settings suggested by hrdl
ATTRS{name}=="cyttsp5", ENV{LIBINPUT_ATTR_PALM_PRESSURE_THRESHOLD}="27"
ATTRS{name}=="cyttsp5", ENV{LIBINPUT_ATTR_THUMB_PRESSURE_THRESHOLD}="28"
ATTRS{name}=="cyttsp5", ENV{LIBINPUT_ATTR_SIZE_HINT}="210x157"
#ATTRS{name}=="cyttsp5", ENV{LIBINPUT_ATTR_RESOLUTION_HINT}="4x4"
#ATTRS{name}=="cyttsp5", ENV{LIBINPUT_ATTR_PALM_SIZE_THRESHOLD}="1"

LABEL="libinput_device_group_end"

```
### User and System Setup

```bash
# Re-enter chroot - if you are not in already
sudo chroot /mnt /bin/bash

#edit fstab to specify what and how to mount partitions
vim /etc/fstab
```
as:
```
  /dev/mmcblk0p6 / ext4 defaults 0 1
  /dev/mmcblk0p7 /home ext4 defaults 0 2
```
```bash
# Create missing groups
groupadd dialout
groupadd plugdev
groupadd bluetooth

# create a user account
# Note: In arch 'wheel' group is used for admin privileges - instead of 'sudo' group in Debian
useradd -M -G wheel,dialout,audio,video,plugdev,bluetooth,render,input -s /bin/bash user

passwd user  # set to 1234 or whatever

# Enable sudo for wheel group and add the wheel 
EDITOR=vim visudo -f /etc/sudoers.d/wheel
```
with this:
```
%wheel ALL=(ALL:ALL) ALL
```

### NetworkManager:
```bash
# Enable NetworkManager
systemctl enable NetworkManager

# Disable systemd-networkd (to prevent possible conflicts.. Added this as I was trying to resolve the wifi connection issue
systemctl disable systemd-networkd.service
systemctl disable systemd-networkd.socket
systemctl disable systemd-networkd-wait-online.service

# Enable wpa_supplicant
systemctl enable wpa_supplicant

```

Configure network manager: I thought I could copy over to arch the conf file but it does not seem to autoconnect to the wifi after boot with the following configuration. Something is wrong but I cannot see it.

```bash
# exit chroot
exit

# copy over the configuration files of the networks you have already setup in os1
# Note: These will only work if the WiFi networks are available and configured in os1
sudo cp -r /etc/NetworkManager/system-connections/* /mnt/etc/NetworkManager/system-connections/
sudo chown -R root:root /mnt/etc/NetworkManager/system-connections/*
sudo chmod 600 /mnt/etc/NetworkManager/system-connections/*

# and we re-enter to do the configs
# Enter chroot
sudo chroot /mnt /bin/bash

vim /etc/NetworkManager/NetworkManager.conf
```
Edit to look like this:
```
  [main]
  plugins=ifupdown,keyfile
  dhcp=internal

  [ifupdown]
  managed=true

  [connection]
  wifi.powersave=2

  [device]
  wifi.scan-rand-mac-address=no
```

and add wifi spec in /etc/NetworkManager/conf.d/
```bash
vim /etc/NetworkManager/conf.d/wifi.conf
```
with this content:
```
  [main]
  rf.wifi.enabled=true
  wifi.backend=wpa_supplicant
```

### Configure Greeter

Configure greetd for the e-ink display:

```bash
# enable greetd
systemctl enable greetd


# Edit greetd configuration file:
vim /etc/greetd/config.toml
```

with this:

```
  [terminal]
  vt = 1

  [default_session]
  command = "sway"
  user = "user"

  [environment]
  XDG_SESSION_TYPE = "wayland"
  WLR_RENDERER = "pixman" ## added this after some debugging not sure is helping
  WLR_RENDERER_ALLOW_SOFTWARE = "1" ## added this after some debugging not sure is helping
```

Create PAM configurations for greetd and add nopasswordlogin for `user`.
```bash
vim /etc/pam.d/greetd
```

```
  auth       required     pam_securetty.so
  auth       requisite    pam_nologin.so
  auth       include      system-local-login
  account    include      system-local-login
  session    include      system-local-login

  # this should add nopassword login to pam
  auth       sufficient   pam_succeed_if.so user ingroup nopasswdlogin
```

and this for nopassword login
```bash
# Add nopasswdlogin group
groupadd nopasswdlogin
usermod -aG nopasswdlogin user

# Add nopasswdlogin to PAM
echo "auth       sufficient   pam_succeed_if.so user ingroup nopasswdlogin" > /etc/pam.d/greetd
```

### Configure Sway
```bash
# Create sway config in etc
vim /etc/sway/config.d/pinenote.conf
```
with this:
```
  # PineNote specific configurations
  output * bg #FFFFFF solid_color

  # Disable xwayland explicitly: no need for this and X stuff
  xwayland disable

  # E-ink specific settings
  output * max_render_time 1000
  output * adaptive_sync off

```

### reboot
manually unmount all chroot filesystem or use `pine_chroot.sh -u`
```bash
exit
cd ~

umount -R /mnt

sudo reboot
```

### Current Status

This installation method successfully boots to login prompt but has some known issues:

#### Critical Issues
- UART keyboard input not working properly, preventing console login
- Sway not starting correctly after login
- WiFi doesn't connect automatically, limiting remote access

#### Working Features
- System boots without errors
- Basic filesystem setup complete
- User configuration and permissions set correctly

PRs or suggestions to fix these issues are welcome.