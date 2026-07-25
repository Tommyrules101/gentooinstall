#!/bin/bash
set -e

DISK="/dev/sda"
MOUNT="/mnt/gentoo"

echo "=== Partitioning Disk ==="
parted -s $DISK mklabel gpt
parted -s $DISK mkpart ESP fat32 1MiB 1025MiB
parted -s $DISK set 1 esp on
parted -s $DISK mkpart SWAP linux-swap 1025MiB 5121MiB
parted -s $DISK mkpart ROOT ext4 5121MiB 100%

mkfs.vfat -F32 ${DISK}1
mkswap ${DISK}2
mkfs.ext4 ${DISK}3

mount ${DISK}3 $MOUNT
mkdir -p $MOUNT/boot
mount ${DISK}1 $MOUNT/boot
swapon ${DISK}2

echo "=== Downloading Stage3 ==="
cd $MOUNT

wget https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64/stage3-amd64.tar.xz -O stage3.tar.xz

tar xpvf stage3.tar.xz --xattrs-include='*.*' --numeric-owner

echo "=== Configuring make.conf ==="
cat <<EOF > $MOUNT/etc/portage/make.conf
COMMON_FLAGS="-O2 -pipe"
MAKEOPTS="-j$(nproc)"
USE="kde plasma elogind networkmanager pipewire pulseaudio -alsa"
VIDEO_CARDS="virtio"
INPUT_DEVICES="libinput"
EOF

echo "=== Copying DNS ==="
cp -L /etc/resolv.conf $MOUNT/etc/

echo "=== Mounting system dirs ==="
mount -t proc /proc $MOUNT/proc
mount --rbind /sys $MOUNT/sys
mount --rbind /dev $MOUNT/dev

echo "=== Entering chroot ==="
cat <<'CHROOTEOF' | chroot /mnt/gentoo /bin/bash
source /etc/profile
export PS1="(gentoo-chroot) $PS1"

echo "=== Syncing Portage ==="
emerge --sync

echo "=== Installing dist-kernel ==="
emerge sys-kernel/gentoo-kernel-bin

echo "=== Installing system tools ==="
emerge grub efibootmgr networkmanager sudo vim

echo "=== Setting timezone ==="
echo "America/New_York" > /etc/timezone
emerge --config sys-libs/timezone-data

echo "=== Setting locale ==="
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set en_US.utf8

echo "=== Fstab ==="
cat <<EOF > /etc/fstab
/dev/sda3   /       ext4    noatime     0 1
/dev/sda1   /boot   vfat    defaults    0 2
/dev/sda2   none    swap    sw          0 0
EOF

echo "=== Installing KDE Plasma + Discover ==="
emerge kde-plasma/plasma-meta kde-plasma/sddm kde-apps/discover

echo "=== Installing PipeWire ==="
emerge pipewire wireplumber pipewire-alsa pipewire-pulse pipewire-jack

echo "=== Installing Google Chrome ==="
emerge www-client/google-chrome

echo "=== Enabling services ==="
rc-update add NetworkManager default
rc-update add sddm default

echo "=== Installing GRUB ==="
grub-install --target=x86_64-efi --efi-directory=/boot
grub-mkconfig -o /boot/grub/grub.cfg

echo "=== Setting root password ==="
echo "root:11312" | chpasswd

echo "=== Creating user tommy ==="
useradd -m -G wheel,audio,video tommy
echo "tommy:11312" | chpasswd

echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

CHROOTEOF

echo "=== Unmounting ==="
umount -R $MOUNT

echo "=== Installation Complete — Reboot Now ==="
