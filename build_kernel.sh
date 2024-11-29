#!/bin/sh

# 1. git clone https://github.com/m-weigand/linux
# 2. Copy this script into linux/
# 3. Make sure the aarch64-linux-gnu- cross-compiler is installed
# 4. Run this script
# 5. Maybe comment out the mrproper target to accelerate future builds
# 6. The kernel image, dtb, and modules are in an tar.zst in the parent directory

export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_PATH=pack INSTALL_MOD_PATH=pack

set -e

# Consider commenting these
make mrproper
make pinenote_defconfig

a=$(date)
make -j$(nproc)
b=$(date)
make modules_install dtbs_install
kr=$(make kernelrelease)
tar --zstd -cf ../${kr}.tar.zst arch/arm64/boot/Image pack/dtbs/${kr}/rockchip/rk3566-pinenote-v1.2.dtb pack/lib/modules/${kr}
echo ${kr}
echo $b $a
