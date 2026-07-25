#!/bin/bash
set -e

# ============================================================
# Global variables
# ============================================================
DISK=""
MACHINE_TYPE=""
INIT_SYSTEM=""
STORAGE_LAYOUT=""
DESKTOP_ENV=""
FEATURES=()
MOUNT="/mnt/gentoo"

# ============================================================
# Helper: simple numbered menu
# ============================================================
select_option() {
    local title="$1"; shift
    local options=("$@")
    echo
    echo "$title"
    echo "--------------------------"
    local i=1
    for opt in "${options[@]}"; do
        echo "$i) $opt"
        ((i++))
    done
    local choice
    while true; do
        read -rp "#? " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
            echo "${options[choice-1]}"
            return 0
        fi
        echo "Invalid choice, try again."
    done
}

# ============================================================
# 1. Disk selection
# ============================================================
select_disk() {
    local options=("/dev/sda" "/dev/vda" "/dev/nvme0n1" "Custom")
    DISK=$(select_option "Select installation disk:" "${options[@]}")
    if [[ "$DISK" == "Custom" ]]; then
        read -rp "Enter disk path (e.g. /dev/sdb): " DISK
    fi
    echo "Selected disk: $DISK"
}

# ============================================================
# 2. Machine type
# ============================================================
select_machine_type() {
    local options=("Virtual Machine" "AMD PC" "Intel PC" "Laptop" "Server")
    MACHINE_TYPE=$(select_option "Machine Type:" "${options[@]}")
    echo "Selected machine type: $MACHINE_TYPE"
}

# ============================================================
# 3. Init system
# ============================================================
select_init_system() {
    local options=("OpenRC" "systemd")
    INIT_SYSTEM=$(select_option "Init System:" "${options[@]}")
    echo "Selected init system: $INIT_SYSTEM"
}

# ============================================================
# 4. Storage layout
# ============================================================
select_storage_layout() {
    local options=(
        "Default (1G EFI, 4G swap, rest root)"
        "VM Optimized (512M EFI, 2G swap, rest root)"
        "Gaming PC (1G EFI, 8G swap, rest root)"
        "Laptop (1G EFI, 8G swap, hibernate)"
        "Custom"
    )
    STORAGE_LAYOUT=$(select_option "Storage Layout:" "${options[@]}")
    echo "Selected storage layout: $STORAGE_LAYOUT"
}

# ============================================================
# 5. Desktop environment
# ============================================================
select_desktop_env() {
    local options=(
        "KDE Plasma (X11)"
        "KDE Plasma (Wayland)"
        "GNOME"
        "XFCE"
        "Cinnamon"
        "MATE"
        "LXQt"
        "Budgie"
        "i3"
        "Sway"
        "Openbox"
        "AwesomeWM"
        "No Desktop (server)"
    )
    DESKTOP_ENV=$(select_option "Desktop Environment:" "${options[@]}")
    echo "Selected desktop: $DESKTOP_ENV"
}

# ============================================================
# 6. Optional features
# ============================================================
select_optional_features() {
    echo
    echo "Optional Features (comma separated indices):"
    local options=(
        "Flatpak + Flathub"
        "Chrome"
        "Firefox"
        "PipeWire"
        "NetworkManager"
        "Bluetooth"
        "Printing (CUPS)"
        "GRUB EFI"
        "systemd-boot"
        "Timeshift"
        "Steam"
        "Lutris"
        "MangoHUD"
    )
    local i=1
    for opt in "${options[@]}"; do
        echo "$i) $opt"
        ((i++))
    done
    read -rp "#? " sel
    FEATURES=()
    IFS=',' read -ra idxs <<< "$sel"
    for idx in "${idxs[@]}"; do
        idx="${idx//[[:space:]]/}"
        if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#options[@]} )); then
            FEATURES+=("${options[idx-1]}")
        fi
    done
    echo "Selected features: ${FEATURES[*]:-none}"
}

# ============================================================
# Summary + confirmation
# ============================================================
show_summary() {
    echo
    echo "Installation Summary"
    echo "--------------------"
    echo "Disk:           $DISK"
    echo "Machine Type:   $MACHINE_TYPE"
    echo "Init System:    $INIT_SYSTEM"
    echo "Storage Layout: $STORAGE_LAYOUT"
    echo "Desktop:        $DESKTOP_ENV"
    echo "Features:       ${FEATURES[*]:-none}"
    echo
}

confirm_install() {
    local ans
    while true; do
        read -rp "Proceed with installation? (yes/no) " ans
        case "$ans" in
            yes|y|Y) return 0 ;;
            no|n|N)  return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# ============================================================
# Partitioning logic
# ============================================================
partition_disk() {
    echo "=== Partitioning disk $DISK ==="
    parted -s "$DISK" mklabel gpt

    case "$STORAGE_LAYOUT" in
        Default*)
            EFI_START="1MiB"; EFI_END="1025MiB"
            SWAP_START="1025MiB"; SWAP_END="5121MiB"
            ROOT_START="5121MiB"; ROOT_END="100%"
            ;;
        VM\ Optimized*)
            EFI_START="1MiB"; EFI_END="513MiB"
            SWAP_START="513MiB"; SWAP_END="2561MiB"
            ROOT_START="2561MiB"; ROOT_END="100%"
            ;;
        Gaming\ PC*)
            EFI_START="1MiB"; EFI_END="1025MiB"
            SWAP_START="1025MiB"; SWAP_END="9217MiB"
            ROOT_START="9217MiB"; ROOT_END="100%"
            ;;
        Laptop*)
            EFI_START="1MiB"; EFI_END="1025MiB"
            SWAP_START="1025MiB"; SWAP_END="9217MiB"
            ROOT_START="9217MiB"; ROOT_END="100%"
            ;;
        Custom*)
            echo "Enter EFI start (e.g. 1MiB):"; read EFI_START
            echo "Enter EFI end (e.g. 1025MiB):"; read EFI_END
            echo "Enter swap start:"; read SWAP_START
            echo "Enter swap end:"; read SWAP_END
            echo "Enter root start:"; read ROOT_START
            echo "Enter root end (e.g. 100%):"; read ROOT_END
            ;;
    esac

    parted -s "$DISK" mkpart ESP fat32 "$EFI_START" "$EFI_END"
    parted -s "$DISK" set 1 esp on
    parted -s "$DISK" mkpart SWAP linux-swap "$SWAP_START" "$SWAP_END"
    parted -s "$DISK" mkpart ROOT ext4 "$ROOT_START" "$ROOT_END"

    mkfs.vfat -F32 "${DISK}1"
    mkswap "${DISK}2"
    mkfs.ext4 "${DISK}3"
}

mount_filesystems() {
    echo "=== Mounting filesystems ==="
    mkdir -p "$MOUNT"
    mount "${DISK}3" "$MOUNT"
    mkdir -p "$MOUNT/boot"
    mount "${DISK}1" "$MOUNT/boot"
    swapon "${DISK}2"
}

# ============================================================
# Stage3 selection
# ============================================================
get_stage3_url() {
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        echo "https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-systemd.tar.xz"
    else
        echo "https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-openrc.tar.xz"
    fi
}

extract_stage3() {
    echo "=== Downloading and extracting Stage3 ($INIT_SYSTEM) ==="
    cd "$MOUNT"
    local url
    url=$(get_stage3_url)
    wget "$url" -O stage3.tar.xz
    tar xpvf stage3.tar.xz --xattrs-include='*.*' --numeric-owner
}

prepare_chroot_mounts() {
    echo "=== Preparing chroot mounts ==="
    cp -L /etc/resolv.conf "$MOUNT/etc/"
    mount -t proc /proc "$MOUNT/proc"
    mount --rbind /sys "$MOUNT/sys"
    mount --make-rslave "$MOUNT/sys"
    mount --rbind /dev "$MOUNT/dev"
    mount --make-rslave "$MOUNT/dev"
}

# ============================================================
# make.conf generation
# ============================================================
generate_make_conf() {
    echo "=== Configuring make.conf ==="
    local video="virtio"
    case "$MACHINE_TYPE" in
        AMD\ PC|Intel\ PC|Laptop)
            video="amdgpu intel i915 nouveau"
            ;;
        Server)
            video="vesa"
            ;;
    esac

    cat > "$MOUNT/etc/portage/make.conf" <<EOF
COMMON_FLAGS="-O2 -pipe"
MAKEOPTS="-j$(nproc)"
USE="X X11 kde qt5 policykit networkmanager pipewire pulseaudio -alsa flatpak packagekit appstream"
VIDEO_CARDS="$video"
INPUT_DEVICES="libinput"
EOF
}

# ============================================================
# Desktop + features mapping
# ============================================================
desktop_packages() {
    case "$DESKTOP_ENV" in
        KDE\ Plasma\ \(X11\))
            echo "kde-plasma/plasma-meta kde-plasma/sddm kde-plasma/sddm-kcm kde-plasma/polkit-kde-agent kde-apps/dolphin kde-apps/konsole"
            ;;
        KDE\ Plasma\ \(Wayland\))
            echo "kde-plasma/plasma-meta kde-plasma/sddm kde-plasma/sddm-kcm kde-plasma/polkit-kde-agent kde-apps/dolphin kde-apps/konsole"
            ;;
        GNOME)
            echo "gnome-base/gnome gnome-base/gdm"
            ;;
        XFCE)
            echo "xfce-base/xfce4 xfce-base/xfce4-meta lxde-base/lxdm"
            ;;
        Cinnamon)
            echo "cinnamon gnome-base/gdm"
            ;;
        MATE)
            echo "mate-base/mate mate-base/mate-desktop lxde-base/lxdm"
            ;;
        LXQt)
            echo "lxqt-base/lxqt-meta lxde-base/lxdm"
            ;;
        Budgie)
            echo "budgie-desktop gnome-base/gdm"
            ;;
        i3)
            echo "x11-wm/i3 x11-misc/dmenu x11-misc/lightdm"
            ;;
        Sway)
            echo "gui-wm/sway x11-misc/lightdm"
            ;;
        Openbox)
            echo "x11-wm/openbox x11-misc/lightdm"
            ;;
        AwesomeWM)
            echo "x11-wm/awesome x11-misc/lightdm"
            ;;
        No\ Desktop*)
            echo ""
            ;;
    esac
}

feature_packages() {
    local pkgs=()
    for f in "${FEATURES[@]}"; do
        case "$f" in
            Flatpak\ +\ Flathub)
                pkgs+=("sys-apps/flatpak" "app-admin/packagekit" "dev-util/appstream")
                ;;
            Chrome)
                pkgs+=("www-client/google-chrome")
                ;;
            Firefox)
                pkgs+=("www-client/firefox")
                ;;
            PipeWire)
                pkgs+=("media-video/pipewire" "media-video/wireplumber" "media-libs/pipewire-alsa" "media-libs/pipewire-jack")
                ;;
            NetworkManager)
                pkgs+=("net-misc/networkmanager" "net-wireless/wpa_supplicant")
                ;;
            Bluetooth)
                pkgs+=("net-wireless/bluez")
                ;;
            Printing\ \(CUPS\))
                pkgs+=("net-print/cups")
                ;;
            GRUB\ EFI)
                pkgs+=("sys-boot/grub" "sys-boot/efibootmgr")
                ;;
            systemd-boot)
                pkgs+=("sys-boot/systemd-boot")
                ;;
            Timeshift)
                pkgs+=("sys-apps/timeshift")
                ;;
            Steam)
                pkgs+=("games-util/steam-launcher")
                ;;
            Lutris)
                pkgs+=("games-util/lutris")
                ;;
            MangoHUD)
                pkgs+=("games-util/mangohud")
                ;;
        esac
    done
    echo "${pkgs[*]}"
}

# ============================================================
# Chroot installation
# ============================================================
run_chroot_install() {
    echo "=== Entering chroot and installing system ==="
    chroot "$MOUNT" /bin/bash <<'CHROOTEOF'
set -e
source /etc/profile

echo "=== Syncing Portage ==="
emerge --sync

echo "=== Installing kernel ==="
emerge --ask=n sys-kernel/gentoo-kernel-bin

echo "=== Setting timezone ==="
echo "America/New_York" > /etc/timezone
emerge --config sys-libs/timezone-data

echo "=== Setting locale ==="
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set en_US.utf8

CHROOTEOF
}

# ============================================================
# Chroot: desktop + features + bootloader + networking
# ============================================================
run_chroot_config_rest() {
    local desktop_pkgs feature_pkgs
    desktop_pkgs=$(desktop_packages)
    feature_pkgs=$(feature_packages)

    chroot "$MOUNT" /bin/bash <<CHROOTEOF
set -e
source /etc/profile

echo "=== Installing desktop environment ==="
if [[ -n "$desktop_pkgs" ]]; then
    emerge --ask=n $desktop_pkgs
fi

echo "=== Installing feature packages ==="
if [[ -n "$feature_pkgs" ]]; then
    emerge --ask=n $feature_pkgs
fi

echo "=== Enabling services ==="
if [[ "$INIT_SYSTEM" == "OpenRC" ]]; then
    if echo "${FEATURES[*]}" | grep -q "NetworkManager"; then
        rc-update add NetworkManager default
    fi
    if echo "$DESKTOP_ENV" | grep -q "KDE Plasma"; then
        rc-update add sddm default || true
    elif echo "$DESKTOP_ENV" | grep -q "GNOME"; then
        rc-update add gdm default || true
    elif echo "$DESKTOP_ENV" | grep -q "XFCE"; then
        rc-update add lxdm default || true
    elif echo "$DESKTOP_ENV" | grep -q "i3"; then
        rc-update add lightdm default || true
    fi
else
    # systemd
    if echo "${FEATURES[*]}" | grep -q "NetworkManager"; then
        systemctl enable NetworkManager
    fi
    if echo "$DESKTOP_ENV" | grep -q "KDE Plasma"; then
        systemctl enable sddm || true
    elif echo "$DESKTOP_ENV" | grep -q "GNOME"; then
        systemctl enable gdm || true
    elif echo "$DESKTOP_ENV" | grep -q "XFCE"; then
        systemctl enable lxdm || true
    elif echo "$DESKTOP_ENV" | grep -q "i3"; then
        systemctl enable lightdm || true
    fi
fi

echo "=== Bootloader installation ==="
if echo "${FEATURES[*]}" | grep -q "GRUB EFI"; then
    emerge --ask=n sys-boot/grub sys-boot/efibootmgr
    grub-install --target=x86_64-efi --efi-directory=/boot
    grub-mkconfig -o /boot/grub/grub.cfg
elif echo "${FEATURES[*]}" | grep -q "systemd-boot"; then
    bootctl install
fi

echo "=== Flatpak Flathub setup ==="
if echo "${FEATURES[*]}" | grep -q "Flatpak + Flathub"; then
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

echo "=== Setting root and user passwords ==="
echo "root:11312" | chpasswd
useradd -m -G wheel,audio,video tommy
echo "tommy:11312" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

CHROOTEOF
}

# ============================================================
# Unmount and finish
# ============================================================
cleanup_unmount() {
    echo "=== Unmounting (Handbook-safe) ==="
    umount -l "$MOUNT/dev" || true
    umount -l "$MOUNT/sys" || true
    umount -l "$MOUNT/proc" || true
    umount -R "$MOUNT" || true
    echo "=== Installation complete. You can reboot now. ==="
}

# ============================================================
# Main installer flow
# ============================================================
run_install() {
    partition_disk
    mount_filesystems
    generate_make_conf
    extract_stage3
    prepare_chroot_mounts
    run_chroot_install
    run_chroot_config_rest
    cleanup_unmount
}

main_menu() {
    while true; do
        echo
        echo "Gentoo Universal Installer"
        echo "=========================="
        echo "1) Start new installation"
        echo "2) Exit"
