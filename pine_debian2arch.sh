#!/bin/bash
# pinenote_arch_install.sh - Main installation script for Arch Linux on PineNote
SCRIPT_VERSION="1.0.0"
MINIMUM_SPACE_GB=6
MINIMUM_RAM_MB=1024

print_version() {
    echo "PineNote Arch Installation Script v${SCRIPT_VERSION}"
}
set -e # Exit on error

# Configuration variables
WORK_DIR="$HOME/alarm-bootstrap"
ROOTFS_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
MOUNT_POINT="/mnt"
USERNAME="user"
USER_PASSWORD="1234" # Change this!

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Cleanup function
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log "An error occurred. Cleaning up..."
        # Unmount everything in reverse order
        umount -R "$MOUNT_POINT/dev/pts" 2>/dev/null || true
        umount -R "$MOUNT_POINT/dev" 2>/dev/null || true
        umount -R "$MOUNT_POINT/proc" 2>/dev/null || true
        umount -R "$MOUNT_POINT/sys" 2>/dev/null || true
        umount -R "$MOUNT_POINT/run" 2>/dev/null || true
        umount -R "$MOUNT_POINT" 2>/dev/null || true
    fi
    exit $exit_code
}

# Add trap for cleanup
trap cleanup EXIT

check_root() {
    if [ "$EUID" -ne 0 ]; then 
        error "Please run as root"
    fi
}

# Verify checksum
verify_rootfs() {
    if [ -f "ArchLinuxARM-aarch64-latest.tar.gz.md5" ]; then
        md5sum -c ArchLinuxARM-aarch64-latest.tar.gz.md5 || error "Rootfs checksum verification failed"
    else
        warn "No MD5 checksum file found for verification"
    fi
}

# Verify required files exist
check_required_files() {
    log "Checking for required files..."
    local missing_files=0

    # Check kernel files
    if ! ls /boot/vmlinuz-*-pinenote-* >/dev/null 2>&1; then
        error "No PineNote kernel found in /boot/"
        missing_files=1
    fi

    if ! ls /boot/initrd.img-*-pinenote-* >/dev/null 2>&1; then
        error "No PineNote initrd found in /boot/"
        missing_files=1
    fi

    if [ ! -f "/boot/emergency/rk3566-pinenote-v1.2.dtb" ]; then
        error "DTB file not found in /boot/emergency/"
        missing_files=1
    fi

    if [ ! -f "/boot/waveform_firmware_recovered" ]; then
        error "Waveform firmware file not found in /boot/"
        missing_files=1
    fi

    if [ $missing_files -eq 1 ]; then
        error "Required files are missing. Please check your system."
    fi
}

# Check and unmount existing mounts
check_and_unmount() {
    local mount_point="$1"
    local device="$2"

    # Check if mount point is in use
    if mountpoint -q "$mount_point" 2>/dev/null; then
        log "Unmounting $mount_point..."
        umount -R "$mount_point" || error "Failed to unmount $mount_point"
    fi

    # Check if device is mounted anywhere
    if [ -n "$device" ] && grep -qs "$device" /proc/mounts; then
        log "Unmounting $device..."
        umount "$device" || error "Failed to unmount $device"
    fi
}

copy_kernel_modules() {
    log "Copying kernel modules..."

    # Get the kernel version from the running system
    KERNEL_VERSION=$(uname -r)

    # Create the modules directory
    mkdir -p "$MOUNT_POINT/usr/lib/modules/$KERNEL_VERSION"

    # Copy all modules
    cp -r "/usr/lib/modules/$KERNEL_VERSION"/* "$MOUNT_POINT/usr/lib/modules/$KERNEL_VERSION/" || \
        error "Failed to copy kernel modules"

    log "Kernel modules copied successfully"
}

setup_environment() {
    log "Creating working directory..."
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"

    log "Downloading Arch Linux ARM rootfs..."
    if [ ! -f "ArchLinuxARM-aarch64-latest.tar.gz" ]; then
        wget -c "$ROOTFS_URL" || error "Failed to download rootfs"
    else
        warn "Rootfs archive already exists, skipping download"
    fi
}

setup_partitions() {
    # Check if partition is mounted and unmount if necessary
    if mountpoint -q "$MOUNT_POINT"; then
        log "Unmounting $MOUNT_POINT..."
        umount -R "$MOUNT_POINT" || error "Failed to unmount $MOUNT_POINT"
    fi

    if grep -qs "/dev/disk/by-partlabel/os2" /proc/mounts; then
        log "Unmounting os2 partition..."
        umount /dev/disk/by-partlabel/os2 || error "Failed to unmount os2 partition"
    fi

    log "Formatting os2 partition..."
    mkfs.ext4 /dev/disk/by-partlabel/os2 || error "Failed to format os2"

    log "Mounting partitions..."
    mount /dev/disk/by-partlabel/os2 "$MOUNT_POINT" || error "Failed to mount os2"

    log "Extracting rootfs..." # this creates directories with default permissions we need to fix that later
    tar xpf ArchLinuxARM-aarch64-latest.tar.gz -C "$MOUNT_POINT" || error "Failed to extract rootfs"
}

mount_system_dirs() {
    log "Mounting system directories..."
    mount -t proc /proc "$MOUNT_POINT/proc" || error "Failed to mount proc"
    mount -t sysfs /sys "$MOUNT_POINT/sys" || error "Failed to mount sys"
    mount -o bind /dev "$MOUNT_POINT/dev" || error "Failed to mount dev"
    mount -o bind /dev/pts "$MOUNT_POINT/dev/pts" || error "Failed to mount dev/pts"
    mount -o bind /run "$MOUNT_POINT/run" || error "Failed to mount run"
}

copy_config_files() {
    log "Copying firmware and configuration files..."
    mkdir -p "$MOUNT_POINT/usr/lib/firmware"
    cp -rp /usr/lib/firmware/rockchip "$MOUNT_POINT/usr/lib/firmware/" || warn "Failed to copy firmware"
    cp /etc/resolv.conf "$MOUNT_POINT/etc/resolv.conf" || warn "Failed to copy resolv.conf"

    # Copy udev rules
    mkdir -p "$MOUNT_POINT/etc/udev/rules.d"
    for rule in 10_change_calmatrix 20_change_device_size 30_rockchip_ebc 40_backlight 81-libinput-pinenote; do
        if [ -f "/etc/udev/rules.d/${rule}.rules" ]; then
            cp "/etc/udev/rules.d/${rule}.rules" "$MOUNT_POINT/etc/udev/rules.d/" || \
                warn "Failed to copy udev rule: ${rule}"
        else
            warn "Udev rule not found: ${rule}"
        fi
    done

    # Copy modprobe configuration files
    log "Copying modprobe configurations..."
    mkdir -p "$MOUNT_POINT/usr/lib/modprobe.d"
    if [ -d "/usr/lib/modprobe.d" ]; then
        cp -r /usr/lib/modprobe.d/* "$MOUNT_POINT/usr/lib/modprobe.d/" || \
            warn "Failed to copy modprobe configurations"
    else
        warn "No modprobe configurations found in /usr/lib/modprobe.d/"
    fi

    # Fix directory permissions
    log "Fixing directory permissions..."
    chmod 700 "$MOUNT_POINT/etc/credstore/" || warn "Failed to set permissions for credstore"
    chmod 700 "$MOUNT_POINT/etc/credstore.encrypted/" || warn "Failed to set permissions for credstore.encrypted"
    chmod 755 "$MOUNT_POINT/usr/share/polkit-1/rules.d/" || warn "Failed to set permissions for polkit rules"
}

copy_kernel_files() {
    log "Copying kernel files..."

    # Create boot directory if it doesn't exist
    mkdir -p "$MOUNT_POINT/boot"

    # Find the most recent pinenote kernel
    KERNEL_FILE=$(ls -t /boot/vmlinuz-*-pinenote-* | head -n1)
    INITRD_FILE=$(ls -t /boot/initrd.img-*-pinenote-* | head -n1)

    if [ ! -f "$KERNEL_FILE" ]; then
        error "Kernel file not found in /boot/"
    fi

    if [ ! -f "$INITRD_FILE" ]; then
        error "Initrd file not found in /boot/"
    fi

    log "Using kernel: $(basename "$KERNEL_FILE")"
    log "Using initrd: $(basename "$INITRD_FILE")"

    # Copy files with specific names
    cp "$KERNEL_FILE" "$MOUNT_POINT$KERNEL_FILE" || error "Failed to copy kernel"
    cp "$INITRD_FILE" "$MOUNT_POINT$INITRD_FILE" || error "Failed to copy initrd"

    # Check if DTB file exists before copying
    if [ -f "/boot/emergency/rk3566-pinenote-v1.2.dtb" ]; then
        cp "/boot/emergency/rk3566-pinenote-v1.2.dtb" "$MOUNT_POINT/boot/" || error "Failed to copy DTB"
    else
        error "DTB file not found"
    fi

    # Check if waveform file exists before copying
    if [ -f "/boot/waveform_firmware_recovered" ]; then
        cp "/boot/waveform_firmware_recovered" "$MOUNT_POINT/boot/" || error "Failed to copy waveform"
    else
        error "Waveform firmware file not found"
    fi

    # Verify files were copied successfully
    if [ ! -f "$MOUNT_POINT$KERNEL_FILE" ] || \
       [ ! -f "$MOUNT_POINT$INITRD_FILE" ] || \
       [ ! -f "$MOUNT_POINT/boot/rk3566-pinenote-v1.2.dtb" ] || \
       [ ! -f "$MOUNT_POINT/boot/waveform_firmware_recovered" ]; then
        error "One or more required files failed to copy"
    fi

    log "Kernel files copied successfully"
}

configure_boot() {
    log "Configuring boot..."
    mkdir -p "$MOUNT_POINT/boot/extlinux"
    cat > "$MOUNT_POINT/boot/extlinux/extlinux.conf" << EOF
default l0
menu title U-Boot menu
prompt 1
timeout 10

label l0
        menu label Arch Linux PineNote
        linux $KERNEL_FILE
        initrd $INITRD_FILE
        fdt /boot/rk3566-pinenote-v1.2.dtb
        append root=/dev/mmcblk0p6 ignore_loglevel rw rootwait earlycon console=tty0 console=ttyS2,1500000n8 fw_devlink=off quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3 plymouth.ignore-serial-consoles vt.global_cursor_default=0
EOF

    if [ ! -f "$MOUNT_POINT/boot/extlinux/extlinux.conf" ]; then
        error "Failed to create boot configuration"
    fi

    log "Boot configuration created successfully"
}

configure_fstab() {
    log "Configuring fstab..."
    cat > "$MOUNT_POINT/etc/fstab" << EOF
/dev/mmcblk0p6 / ext4 defaults 0 1
/dev/mmcblk0p7 /home ext4 defaults 0 2
EOF

    if [ ! -f "$MOUNT_POINT/etc/fstab" ]; then
        error "Failed to create fstab configuration"
    fi

    log "fstab configuration created successfully"
}

########################################################################
################ Second part of system install #########################
########################################################################

configure_locale() {
    log "Configuring locale settings..."
    chroot "$MOUNT_POINT" /bin/bash << 'EOF'
    echo "en_GB.UTF-8 UTF-8" >> /etc/locale.gen
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
    echo "LANG=en_GB.UTF-8" > /etc/locale.conf
EOF
}


configure_pacman() {
    log "Configuring pacman and updating system..."
    chroot "$MOUNT_POINT" /bin/bash << 'EOF'
    pacman-key --init
    pacman-key --populate archlinuxarm
    pacman -Syu --noconfirm
EOF
}

install_packages() {
    log "Installing essential packages..."
    chroot "$MOUNT_POINT" /bin/bash << 'EOF'
    # Prevent installation of linux kernel package by adding to [options] section
    sed -i '/^\[options\]/a IgnorePkg = linux-aarch64' /etc/pacman.conf

    # Base packages (removed linux-firmware as it's not needed with Debian kernel)
    pacman -S --noconfirm base-devel git wget networkmanager \
        wpa_supplicant wireless_tools iw glibc

    # Additional dependencies
    pacman -S --noconfirm python python-pip inotify-tools libinput \
        xf86-input-libinput glib2 gsettings-desktop-schemas wtype \
        alsa-utils alsa-firmware sof-firmware bluez-utils

    pacman -S --noconfirm brightnessctl iio-sensor-proxy jq \ 
        noto-fonts noto-fonts-emoji nwg-menu python-i3ipc \ 
        python-pydbus wtype

    # NetworkManager related
    pacman -S --noconfirm network-manager-applet gtk3 gtk-layer-shell \
        libappindicator-gtk3

    # E-ink display related
    pacman -S --noconfirm sway swaybg swayidle swaylock waybar foot xournalpp vim

    # fonts required by waybar config
    sudo pacman -S --noconfirm ttf-font-awesome otf-font-awesome ttf-dejavu noto-fonts \
    ttf-liberation ttf-droid ttf-roboto ttf-ubuntu-font-family

    # Display and input management
    pacman -S --noconfirm greetd greetd-regreet squeekboard

    systemctl enable seatd

EOF
}

# Add a function to handle kernel setup
setup_kernel() {
    log "Setting up kernel..."

    # Remove any default kernel packages if they were installed
    chroot "$MOUNT_POINT" /bin/bash << 'EOF'
    pacman -Rdd --noconfirm linux-aarch64 2>/dev/null || true
    rm -f /boot/initramfs-linux.img 2>/dev/null || true
    rm -f /boot/vmlinuz-linux-aarch64 2>/dev/null || true
EOF

    # Remove default mkinitcpio preset if it exists
    rm -f "$MOUNT_POINT/etc/mkinitcpio.d/linux-aarch64.preset" 2>/dev/null || true
}

configure_libinput() {
    log "Configuring libinput..."
    # Append PineNote-specific settings to existing rules
    cat >> "$MOUNT_POINT/etc/udev/rules.d/81-libinput-pinenote.rules" << 'EOF'
# Additional PineNote-specific settings suggested by hrdl
ATTRS{name}=="cyttsp5", ENV{LIBINPUT_ATTR_PALM_PRESSURE_THRESHOLD}="27"
ATTRS{name}=="cyttsp5", ENV{LIBINPUT_ATTR_THUMB_PRESSURE_THRESHOLD}="28"
ATTRS{name}=="cyttsp5", ENV{LIBINPUT_ATTR_SIZE_HINT}="210x157"
#ATTRS{name}=="cyttsp5", ENV{LIBINPUT_ATTR_RESOLUTION_HINT}="4x4"
#ATTRS{name}=="cyttsp5", ENV{LIBINPUT_ATTR_PALM_SIZE_THRESHOLD}="1"
EOF
}

copy_system_configs() {
    log "Copying and creating system configurations..."

    # Copy existing modprobe configurations
    if [ -d "/etc/modprobe.d" ]; then
        mkdir -p "$MOUNT_POINT/etc/modprobe.d"
        cp -r /etc/modprobe.d/* "$MOUNT_POINT/etc/modprobe.d/" || \
            warn "Failed to copy modprobe configurations"
    fi

    # Create brcmfmac configuration
    log "Creating brcmfmac configuration..."
    cat > "$MOUNT_POINT/etc/modprobe.d/brcmfmac.conf" << 'EOF'
options brcmfmac feature_disable=0x82000
EOF

    # Verify the file was created
    if [ ! -f "$MOUNT_POINT/etc/modprobe.d/brcmfmac.conf" ]; then
        error "Failed to create brcmfmac configuration"
    fi

    # Verify the content
    if ! grep -q "feature_disable=0x82000" "$MOUNT_POINT/etc/modprobe.d/brcmfmac.conf"; then
        error "brcmfmac configuration content verification failed"
    fi

    log "System configurations copied and created successfully"
}

setup_users() {
    log "Setting up users and groups..."
    chroot "$MOUNT_POINT" /bin/bash << 'EOF'
    # Create necessary groups
    groupadd -f dialout
    groupadd -f plugdev
    groupadd -f bluetooth

    # Remove default alarm user
    userdel -r alarm 2>/dev/null || true

    # Create user group with specific GID
    groupadd -g 1000 user

    # Create user with specific UID and groups
    useradd -M -u 1000 -g 1000 \
        -G wheel,dialout,audio,video,input,plugdev,bluetooth,render,storage,power, seat, network \
        -s /bin/bash user

    # Set user password
    echo "user:1234" | chpasswd

    # Configure sudo for wheel group
    mkdir -p /etc/sudoers.d
    echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
    chmod 440 /etc/sudoers.d/wheel
EOF
}

configure_network() {
    log "Configuring NetworkManager..."

    # First, copy network configurations from host system
    if [ -d "/etc/NetworkManager/system-connections" ]; then
        mkdir -p "$MOUNT_POINT/etc/NetworkManager/system-connections"
        cp -r /etc/NetworkManager/system-connections/* \
            "$MOUNT_POINT/etc/NetworkManager/system-connections/" || \
            warn "Failed to copy network connections"
    fi

    # Create NetworkManager configuration matching Debian's setup
    cat > "$MOUNT_POINT/etc/NetworkManager/NetworkManager.conf" << 'EOF'
[main]
plugins=ifupdown,keyfile

[ifupdown]
managed=false
EOF

    chroot "$MOUNT_POINT" /bin/bash << 'EOF'
    # Enable NetworkManager
    systemctl enable NetworkManager

    # Disable systemd-networkd and related services
    systemctl disable systemd-networkd.service
    systemctl disable systemd-networkd.socket
    systemctl disable systemd-networkd-wait-online.service

    # Set permissions for network configurations
    if [ -d "/etc/NetworkManager/system-connections" ]; then
        chown -R root:root /etc/NetworkManager/system-connections/
        chmod 600 /etc/NetworkManager/system-connections/*
    fi

    # Create wifi configuration
    mkdir -p /etc/NetworkManager/conf.d
    cat > /etc/NetworkManager/conf.d/wifi.conf << WIFIEOF
[main]
rf.wifi.enabled=true
wifi.backend=wpa_supplicant
WIFIEOF
EOF
}


# Note about AUR packages
note_aur_packages() {
    log "Note: After installation, you'll need to manually install these AUR packages:"
    echo "  - rot8-git"
    echo "  - lisgd-git"
    echo ""
    echo "You can install them manually after reboot:"
    echo "Clone the packages:"
    echo "  git clone https://aur.archlinux.org/rot8-git.git"
    echo "  git clone https://aur.archlinux.org/lisgd-git.git"
    echo ""
    echo "Then install them with: makepgk -si"
}




# Main installation function
main() {
    log "Starting PineNote Arch Linux installation..."

    check_root
    check_required_files
    check_and_unmount "$MOUNT_POINT" "/dev/disk/by-partlabel/os2"
    setup_environment
    setup_partitions
    mount_system_dirs
    copy_config_files
    copy_kernel_files
    copy_kernel_modules
    configure_boot
    configure_fstab  
    
    log "Installation of base system completed successfully!"
    
    configure_locale
    configure_pacman
    install_packages
    # configure_libinput we may want to delete this one, the rule in hrdl udev is the same as the one in debian
    copy_system_configs
    setup_users
    configure_network

    note_aur_packages

    
    log "Installation completed successfully!"
    log "Please configure greetd, sway and waybar before reboot"
}

# Run main function
main "$@"
