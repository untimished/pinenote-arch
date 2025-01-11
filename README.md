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
$ Fix greeter home directory for gsettings / squeekboard to work
$ usermod -d /etc/greetd greeter
$ chown -R greeter:greeter /etc/greetd
$ mkinitcpio --preset pinenote
$ mkimage -A arm64 -T ramdisk -n uInitrd -d /boot/initramfs-linux.img /boot/uInitrd.img
$ # maybe network manager stuff 
$ exit
$ sync && umount -R /mnt
```

## Method 2: Installation using Arch ARM rootfs

A script to install Arch Linux on the PineNote e-ink tablet, converting from an existing Debian installation.

## Overview

This script automates the process of installing Arch Linux ARM on the PineNote device, handling all necessary system configurations, kernel setup, and essential package installation.

```bash

### Main installation function

main() {
    log "Starting PineNote Arch Linux installation..."

    check_root
    check_required_files
    check_and_unmount "$MOUNT_POINT" "/dev/disk/by-partlabel/os2"
    setup_environment
    setup_partitions    # this will format OS2 partition !!
    mount_system_dirs
    copy_config_files
    copy_kernel_files   # copying the kernel from debian to /boot/
    copy_kernel_modules # copying the kernel modules from debian kernel
    configure_boot      # setting up extlinux.conf 
    configure_fstab  
    
    log "Installation of base system completed successfully!"
    
    configure_locale     # currently set up for en_GB.UTF-8
    configure_pacman 
    install_packages     # here we prevent the install of the arm kernel from arch because we have debian kernel
    configure_libinput   # appending some custom configs for touch input
    copy_system_configs  # copying modprobe.d/* configs from debian
    setup_users          # setting up "user" with GID 1000 so that it shares the same home with debian
    configure_network    # copying over wifi settings from debian, including any wpa saved config

    note_aur_packages

    
    log "Installation completed successfully!"
    log "Please configure greetd, sway and waybar before reboot"
}
```


## Prerequisites

- Root access
- Running Debian system on PineNote
- Minimum 6GB free space
- Minimum 1GB RAM
- Working internet connection

## basic assumptions (these may change in your case)
- Required kernel files in `/boot`:
  - PineNote kernel (`vmlinuz-*-pinenote-*`)
  - PineNote initrd (`initrd.img-*-pinenote-*`)
  - DTB file (`/boot/emergency/rk3566-pinenote-v1.2.dtb`)
  - Waveform firmware (`/boot/waveform_firmware_recovered`)

## Features

- Full system installation and configuration
- Kernel and firmware setup
- Network configuration
- User management
- E-ink display optimization
- Input device configuration
- Essential package installation

## Installation

1. Download the script:

```bash
wget https://raw.githubusercontent.com/username/pine_debian2arch.sh
chmod +x pine_debian2arch.sh

```

### Add bash pine-specific bash scripts

Copy utility scripts from here
```bash
# exit chroot
exit
sudo cp -r [github]/misc/bin/* /mnt/usr/local/bin/
sudo chmod +x /mnt/usr/local/bin/*
```



## Additional steps to complete the installation 

The above should give a bootable system with console access over ssh or uart. 

The following are necessary steps to have a graphical UI.


### Configure Greeter

Configure greetd for the e-ink display:

```

sudo cp [github]/etc/greetd/* /mnt/etc/greetd/

## enter CHROOT
# if you use the greeter user, make sure the home directory is properly set and has correct permissions

sudo usermod -d /etc/greetd greeter
sudo chown -R greeter:greeter /etc/greetd

## EXIT CHROOT


```

```bash
sudo chroot /mnt /bin/bash
# enable greetd
systemctl enable greetd
```

### Configure Sway and waybar
```
# we can copy in the .config of user in debian because this will be exactly the same home in arch
sudo cp [github]misc/.config/* ~/.config/

```

### reboot
manually unmount all chroot filesystem or use `pine_chroot.sh -u`
```bash
#exit chroot
exit

# make sure we are not in any folder that need unmount
cd ~

sudo umount -R /mnt

sudo reboot
```


#### rot8 and lisgd
```bash
cd ~

git clone https://aur.archlinux.org/rot8-git.git # these will have to be install when home is mounted properly not over chroot

git clone https://aur.archlinux.org/lisgd-git.git  # these will have to be install when home is mounted properly not over chroot


```

