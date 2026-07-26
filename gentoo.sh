#!/bin/bash
set -e

DISK=""
MACHINE_TYPE=""
INIT_SYSTEM=""
STORAGE_LAYOUT=""
DESKTOP_ENV=""
FEATURES=()
MOUNT="/mnt/gentoo"
ROOT_PASSWORD=""
USER_NAME=""
USER_PASSWORD=""

flush_input() {
    # aggressively clear any buffered input (BusyBox-safe)
    read -r -N 999999 discard 2>/dev/null || true
}

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
        flush_input
        read -rp "#? " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
            echo "${options[choice-1]}"
            return 0
        fi
        echo "Invalid choice, try again."
    done
}

select_disk() {
    local options=("/dev/sda" "/dev/vda" "/dev/nvme0n1" "Custom")
    DISK=$(select_option "Select installation disk:" "${options[@]}")
    if [[ "$DISK" == "Custom" ]]; then
        read -rp "Enter disk path (e.g. /dev/sdb): " DISK
    fi
    echo "Selected disk: $DISK"
}

select_machine_type() {
    local options=("Virtual Machine" "AMD PC" "Intel PC" "Laptop" "Server")
    MACHINE_TYPE=$(select_option "Machine Type:" "${options[@]}")
    echo "Selected machine type: $MACHINE_TYPE"
}

select_init_system() {
    local options=("OpenRC" "systemd")
    INIT_SYSTEM=$(select_option "Init System:" "${options[@]}")
    echo "Selected init system: $INIT_SYSTEM"
}

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

select_optional_features() {
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
    flush_input
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

select_credentials() {
    echo
    echo "Credentials"
    echo "==========="
    read -rp "Enter root password (visible): " ROOT_PASSWORD
    read -rp "Confirm root password: " ROOT_CONFIRM
    if [[ "$ROOT_PASSWORD" != "$ROOT_CONFIRM" ]]; then
        echo "Root passwords do not match. Try again."
        select_credentials
        return
    fi
    read -rp "Enter username: " USER_NAME
    read -rp "Enter user password (visible): " USER_PASSWORD
    read -rp "Confirm user password: " USER_CONFIRM
    if [[ "$USER_PASSWORD" != "$USER_CONFIRM" ]]; then
        echo "User passwords do not match. Try again."
        select_credentials
        return
    fi
}

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
    echo "Root password:  (visible) $ROOT_PASSWORD"
    echo "User:           $USER_NAME"
    echo "User password:  (visible) $USER_PASSWORD"
    echo
}

confirm_install() {
    local ans
    while true; do
        flush_input
        read -rp "Proceed with installation? (yes/no) " ans
        case "$ans" in
            yes|y|Y) return 0 ;;
            no|n|N)  return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

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
            echo "Enter EFI start:"; read EFI_START
            echo "Enter EFI end:"; read EFI_END
            echo "Enter swap start:"; read SWAP_START
            echo "Enter swap end:"; read SWAP_END
            echo "Enter root start:"; read ROOT_START
            echo "Enter root end:"; read ROOT_END
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

get_stage3_url() {
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        echo "https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-systemd.tar.xz"
    else
        echo "https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-openrc.tar.xz"
    fi
}

extract_stage3() {
    echo "=== Downloading and extracting Stage3 ==="
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

desktop_packages() {
    case "$DESKTOP_ENV" in
        KDE\ Plasma*) echo "kde-plasma/plasma-meta kde-plasma/sddm kde-plasma/sddm-kcm kde-apps/dolphin kde-apps/konsole" ;;
        GNOME) echo "gnome-base/gnome gnome-base/gdm" ;;
        XFCE) echo "xfce-base/xfce4 xfce-base/xfce4-meta lxde-base/lxdm" ;;
        Cinnamon) echo "cinnamon gnome-base/gdm" ;;
        MATE) echo "mate-base/mate mate-base/mate-desktop lxde-base/lxdm" ;;
        LXQt) echo "lxqt-base/lxqt-meta lxde-base/lxdm" ;;
        Budgie) echo "budgie-desktop gnome-base/gdm" ;;
        i3) echo "x11-wm/i3 x11-misc/dmenu x11-misc/lightdm" ;;
        Sway) echo "gui-wm/sway x11-misc/lightdm" ;;
        Openbox) echo "x11-wm/openbox x11-misc/lightdm" ;;
        AwesomeWM) echo "x11-wm/awesome x11-misc/lightdm" ;;
        No\ Desktop*) echo "" ;;
    esac
}

feature_packages() {
    local pkgs=()
    for f in "${FEATURES[@]}"; do
        case "$f" in
            Flatpak*) pkgs+=("sys-apps/flatpak" "app-admin/packagekit" "dev-util/appstream") ;;
            Chrome) pkgs+=("www-client/google-chrome") ;;
            Firefox) pkgs+=("www-client/firefox") ;;
            PipeWire) pkgs+=("media-video/pipewire" "media-video/wireplumber") ;;
            NetworkManager) pkgs+=("net-misc/networkmanager") ;;
            Bluetooth) pkgs+=("net-wireless/bluez") ;;
            Printing*) pkgs+=("net-print/cups") ;;
            GRUB*) pkgs+=("sys-boot/grub" "sys-boot/efibootmgr") ;;
            systemd-boot) pkgs+=("sys-boot/systemd-boot") ;;
            Timeshift) pkgs+=("sys-apps/timeshift") ;;
            Steam) pkgs+=("games-util/steam-launcher") ;;
            Lutris) pkgs+=("games-util/lutris") ;;
            MangoHUD) pkgs+=("games-util/mangohud") ;;
        esac
    done
    echo "${pkgs[*]}"
}

run_chroot_install() {
    echo "=== Entering chroot and installing base system ==="
    chroot "$MOUNT" /bin/bash <<'CHROOTEOF'
set -e
source /etc/profile

emerge --sync
emerge --ask=n sys-kernel/gentoo-kernel-bin

echo "America/New_York" > /etc/timezone
emerge --config sys-libs/timezone-data

echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set en_US.utf8

CHROOTEOF
}

run_chroot_config_rest() {
    local desktop_pkgs feature_pkgs
    desktop_pkgs=$(desktop_packages)
    feature_pkgs=$(feature_packages)

    chroot "$MOUNT" /bin/bash <<CHROOTEOF
set -e
source /etc/profile

if [[ -n "$desktop_pkgs" ]]; then
    emerge --ask=n $desktop_pkgs
fi

if [[ -n "$feature_pkgs" ]]; then
    emerge --ask=n $feature_pkgs
fi

echo "root:${ROOT_PASSWORD}" | chpasswd
useradd -m -G wheel,audio,video "${USER_NAME}"
echo "${USER_NAME}:${USER_PASSWORD}" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

CHROOTEOF
}

cleanup_unmount() {
    echo "=== Unmounting ==="
    umount -l "$MOUNT/dev" || true
    umount -l "$MOUNT/sys" || true
    umount -l "$MOUNT/proc" || true
    umount -R "$MOUNT" || true
    echo "=== Installation complete. You can reboot now. ==="
}

run_install() {
    echo "=== Starting installation ==="
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
        echo "==========================="
        echo "1) Start new installation"
        echo "2) Exit"
        flush_input
        read -rp "#? " choice
        case "$choice" in
            1)
                select_disk
                select_machine_type
                select_init_system
                select_storage_layout
                select_desktop_env
                select_optional_features
                select_credentials
                show_summary
                if confirm_install; then
                    run_install
                else
                    echo "Installation cancelled. Returning to main menu."
                fi
                ;;
            2)
                echo "Exiting installer."
                exit 0
                ;;
            *)
                echo "Invalid choice."
                ;;
        esac
    done
}

main_menu
