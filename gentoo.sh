#!/bin/bash
set -e

DISK="/dev/sda"
MOUNT="/mnt/gentoo"

echo "=== Creating /mnt/gentoo ==="
mkdir -p /mnt/gentoo

echo "=== Partitioning Disk (Handbook layout) ==="
parted -s $DISK mklabel gpt
parted -s $DISK mkpart ESP fat32 1MiB 1025MiB
parted -s $DISK set 1 esp on
parted -s $DISK mkpart SWAP linux-swap 1025MiB 5121MiB
parted -s $DISK mkpart ROOT ext4 5121MiB 100%

mkfs.vfat -F32 ${DISK}1
mkswap ${DISK}2
mkfs.ext4 ${DISK}3

echo "=== Mounting partitions ==="
mount ${DISK}3 $MOUNT
mkdir -p $MOUNT/boot
mount ${DISK}1 $MOUNT/boot
swapon ${DISK}2

echo "=== Moving into /mnt/gentoo ==="
cd /mnt/gentoo

echo "=== Downloading Stage3 OpenRC ==="
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/20260719T170103Z/stage3-amd64-openrc-20260719T170103Z.tar.xz -O stage3.tar.xz

echo "=== Extracting Stage3 ==="
tar xpvf stage3.tar.xz --xattrs-include='*.*' --numeric-owner

echo "=== Copying DNS ==="
cp -L /etc/resolv.conf $MOUNT/etc/

echo "=== Mounting system dirs (Handbook required) ==="
mount -t proc /proc $MOUNT/proc
mount --rbind /sys $MOUNT/sys
mount --make-rslave $MOUNT/sys
mount --rbind /dev $MOUNT/dev
mount --make-rslave $MOUNT/dev

echo "=== Chrooting into Gentoo ==="
chroot /mnt/gentoo /bin/bash <<'CHROOTEOF'
source /etc/profile
export PS1="(gentoo-chroot) $PS1"

echo "=== Configuring make.conf with correct USE flags ==="
cat <<EOF > /etc/portage/make.conf
COMMON_FLAGS="-O2 -pipe"
MAKEOPTS="-j$(nproc)"
USE="X X11 kde qt5 policykit networkmanager pipewire pulseaudio -alsa flatpak packagekit appstream"
VIDEO_CARDS="virtio"
INPUT_DEVICES="libinput"
EOF

echo "=== Syncing Portage ==="
emerge --sync

echo "=== Installing dist-kernel ==="
emerge sys-kernel/gentoo-kernel-bin

echo "=== Installing system tools ==="
emerge sys-boot/grub efibootmgr networkmanager wpa_supplicant nmtui sudo vim

echo "=== Setting timezone ==="
echo "America/New_York" > /etc/timezone
emerge --config sys-libs/timezone-data

echo "=== Setting locale ==="
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set en_US.utf8

echo "=== Writing fstab ==="
cat <<EOF > /etc/fstab
/dev/sda3   /       ext4    noatime     0 1
/dev/sda1   /boot   vfat    defaults    0 2
/dev/sda2   none    swap    sw          0 0
EOF

echo "=== Installing KDE Plasma X11 + Discover + Polkit ==="
emerge kde-plasma/plasma-meta \
       kde-plasma/sddm \
       kde-plasma/sddm-kcm \
       kde-plasma/polkit-kde-agent \
       kde-apps/discover \
       kde-apps/dolphin \
       kde-apps/konsole

echo "=== Installing PipeWire ==="
emerge pipewire wireplumber pipewire-alsa pipewire-pulse pipewire-jack

echo "=== Installing Google Chrome ==="
echo 'www-client/google-chrome google-chrome' >> /etc/portage/package.license
emerge www-client/google-chrome

echo "=== Installing Flatpak + Discover backend ==="
emerge flatpak packagekit appstream
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

echo "=== Enabling services ==="
rc-update add NetworkManager default
rc-update add sddm default

echo "=== Installing GRUB EFI ==="
grub-install --target=x86_64-efi --efi-directory=/boot
grub-mkconfig -o /boot/grub/grub.cfg

echo "=== Setting root password ==="
echo "root:11312" | chpasswd

echo "=== Creating user tommy ==="
useradd -m -G wheel,audio,video tommy
echo "tommy:11312" | chpasswd

echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

CHROOTEOF

echo "=== Unmounting (Handbook safe method) ==="
umount -l $MOUNT/dev
umount -l $MOUNT/sys
umount -l $MOUNT/proc
umount -R $MOUNT

echo "=== Installation Complete — Reboot Now ==="
