#!/usr/bin/env bash

pacman-key --init
pacman-key --populate archlinuxarm
pacman -Syu base-devel git rxvt-unicode-terminfo

echo "[Warning] Please add default user to /etc/sudoers"
