#!/bin/sh

pdir=/sys/module/rockchip_ebc/parameters
#if grep '^[12]$' "${pdir}/bw_mode"; then
#fi

echo on > /sys/devices/platform/fdec0000.ebc/power/control
#if [ $(cat /sys/module/rockchip_ebc/parameters/bw_mode) = Y ]; then
#  return
#fi
if [ -e /sys/module/rockchip_ebc/parameters/lut_type ]; then
  echo 6 > /sys/module/rockchip_ebc/parameters/lut_type
elif [ -e /sys/module/rockchip_ebc/parameters/default_waveform ]; then
  #echo 1 > /sys/module/rockchip_ebc/parameters/default_waveform
  echo 1 > /sys/module/rockchip_ebc/parameters/default_waveform
fi
