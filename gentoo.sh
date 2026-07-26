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

echo "=== Mounting Filesystems ==="
mount ${DISK}3 $MOUNT
mkdir -p $MOUNT/boot
mount ${DISK}1 $MOUNT/boot
swapon ${DISK}2

echo "=== Downloading Stage3 (systemd) ==="
cd $MOUNT
STAGE=$(curl -s https://www.gentoo.org/downloads/mirrors/ | grep -o 'https://.*stage3-amd64-systemd-.*tar.xz' | head -n 1)
wget $STAGE -O stage3.tar.xz
tar xpvf stage3.tar.xz --xattrs-include='*.*' --numeric-owner

echo "=== Configuring make.conf ==="
cat <<EOF > $MOUNT/etc/portage/make.conf
COMMON_FLAGS="-O2 -pipe"
MAKEOPTS="-j$(nproc)"
USE="X X11 kde qt5 pipewire pulseaudio -alsa networkmanager flatpak packagekit appstream"
VIDEO_CARDS="virtio"
INPUT_DEVICES="libinput"
EOF

echo "=== Copying DNS ==="
cp -L /etc/resolv.conf $MOUNT/etc/

echo "=== Mounting system dirs ==="
mount -t proc /proc $MOUNT/proc
mount --rbind /sys $MOUNT/sys
mount --make-rslave $MOUNT/sys
mount --rbind /dev $MOUNT/dev
mount --make-rslave $MOUNT/dev

echo "=== Entering chroot ==="
cat <<'CHROOTEOF' | chroot /mnt/gentoo /bin/bash
set -e
source /etc/profile

echo "=== Syncing Portage ==="
emerge --sync

echo "=== Installing Kernel ==="
emerge --ask=n sys-kernel/gentoo-kernel-bin

echo "=== Timezone & Locale ==="
echo "America/New_York" > /etc/timezone
emerge --config sys-libs/timezone-data
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set en_US.utf8

echo "=== Fstab ==="
cat <<EOF > /etc/fstab
/dev/sda3   /       ext4    noatime     0 1
/dev/sda1   /boot   vfat    defaults    0 2
/dev/sda2   none    swap    sw          0 0
EOF

echo "=== Installing KDE Plasma (X11) ==="
emerge --ask=n kde-plasma/plasma-meta kde-plasma/sddm kde-plasma/sddm-kcm kde-apps/dolphin kde-apps/konsole

echo "=== Installing Discover ==="
emerge --ask=n kde-apps/discover

echo "=== Installing PipeWire ==="
emerge --ask=n pipewire wireplumber pipewire-alsa pipewire-pulse pipewire-jack

echo "=== Installing Chrome ==="
emerge --ask=n www-client/google-chrome

echo "=== Installing Flatpak ==="
emerge --ask=n sys-apps/flatpak app-admin/packagekit dev-util/appstream
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

echo "=== Installing NetworkManager ==="
emerge --ask=n net-misc/networkmanager
systemctl enable NetworkManager

echo "=== Enabling SDDM ==="
systemctl enable sddm

echo "=== Installing systemd-boot ==="
bootctl install

echo "=== Creating Users ==="
echo "root:11312" | chpasswd
useradd -m -G wheel,audio,video tommy
echo "tommy:11312" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

CHROOTEOF

echo "=== Unmounting ==="
umount -l $MOUNT/dev || true
umount -l $MOUNT/sys || true
umount -l $MOUNT/proc || true
umount -R $MOUNT || true

echo "=== Installation Complete — Reboot Now ==="
