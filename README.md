# PineNote Arch Linux installation from Debian

These instructions are a rough guide to install Arch Linux to `os2` using the Debian installation on `os1`. They are pieced together from my shell history, so they haven't been tested.

## Preparation

### Partitioning

```bash
sudo mkfs.ext4 /dev/disk/by-partlabel/os2
sudo mount /dev/disk/by-partlabel/os2 /mnt
```

### Installation of `pacman` and `pacstrap`

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

### Installation
```bash
# Adapt to your needs
sudo pacstrap /mnt base mkinitcpio uboot-tools archlinuxarm-keyring linux-firmware sway waybar foot xournalpp openssh base-devel git go tmux \
 vulkan-panfrost wget networkmanager network-manager-applet greetd greetd-regreet squeekboard

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
