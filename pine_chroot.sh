#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

# Mount points
MOUNT_POINT="/mnt"
OS2_PART="/dev/disk/by-partlabel/os2"

# Function to unmount everything
unmount_all() {
    echo "Unmounting filesystems..."
    umount -R ${MOUNT_POINT}/dev/pts 2>/dev/null
    umount -R ${MOUNT_POINT}/dev 2>/dev/null
    umount -R ${MOUNT_POINT}/proc 2>/dev/null
    umount -R ${MOUNT_POINT}/sys 2>/dev/null
    umount -R ${MOUNT_POINT}/run 2>/dev/null
    umount -R ${MOUNT_POINT} 2>/dev/null
    echo "Unmounting complete"
    exit 0
}

# Function to mount and enter chroot
mount_and_chroot() {
    # Mount root partition
    echo "Mounting root partition..."
    mount ${OS2_PART} ${MOUNT_POINT}

    # Mount virtual filesystems
    echo "Mounting virtual filesystems..."
    mount -t proc /proc ${MOUNT_POINT}/proc
    mount -t sysfs /sys ${MOUNT_POINT}/sys
    mount -o bind /dev ${MOUNT_POINT}/dev
    mount -o bind /dev/pts ${MOUNT_POINT}/dev/pts
    mount -o bind /run ${MOUNT_POINT}/run

    # Copy resolv.conf for network access
    echo "Copying resolv.conf..."
    cp /etc/resolv.conf ${MOUNT_POINT}/etc/resolv.conf

    echo "Entering chroot..."
    chroot ${MOUNT_POINT} /bin/bash
}

# Check for unmount flag
if [ "$1" = "-u" ]; then
    unmount_all
else
    mount_and_chroot
fi
