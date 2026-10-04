#!/bin/bash
# # ======================================================
#  Script Name: arch_install.sh
#  Author: Benevant Mathew
#  Created: 2026-10-05
#  Release: v1.0
#  Email: benevantmathewv@gmail.com
#  Purpose: # Reuse-only Arch installer. Partitioning/filesystem creation is deliberately manual.
# ======================================================
# shellcheck disable=SC1091
# ======================================================
set -euo pipefail

EFI_PART="${EFI_PART:-}"
BOOT_PART="${BOOT_PART:-}"
ROOT_PART="${ROOT_PART:-${ROOT_LUKS_PART:-}}"
SWAP_PART="${SWAP_PART:-}"
BOOT_MODE="${BOOT_MODE:-auto}"
BIOS_DISK="${BIOS_DISK:-}"
ROOT_MAPPER_NAME="${ROOT_MAPPER_NAME:-cryptroot}"
HOSTNAME="${HOSTNAME:-archlinux}"
USERNAME="${USERNAME:-benevantmathew}"
BOOTLOADER_ID="${BOOTLOADER_ID:-ARCH}"
TIMEZONE="${TIMEZONE:-Asia/Kolkata}"
LOCALE="${LOCALE:-en_IN.UTF-8}"
TARGET_MOUNT="${TARGET_MOUNT:-/mnt}"
CPU_UCODE="${CPU_UCODE:-amd-ucode}"
INSTALL_GNOME="${INSTALL_GNOME:-true}"
DRY_RUN=false
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage() {
    cat <<'HELP'
Usage: arch_install.sh [options]
Run from an Arch live ISO with working networking. MANUALLY partition and
prepare all filesystems/LUKS/swap first. This installer NEVER formats, creates
LUKS containers or initializes swap. It DOES DELETE existing root and separate
/boot contents after an exact confirmation. ESP contents are preserved (GRUB
adds/updates its selected vendor directory). Review devices carefully.

Options (also accept --option=value):
  --root DEV            Existing root: auto-detect LUKS, otherwise plain ext4
  --root-luks DEV       Backward-compatible alias for --root (also auto-detects)
  --boot DEV|NA         Existing unencrypted ext4 /boot; NA places /boot in root
  --swap DEV|NA         Existing plain swap signature; NA omits swap entirely
  --efi DEV             Existing vfat ESP, UEFI only; mounted at /boot/efi
  --boot-mode MODE      auto (firmware detection), uefi or bios
  --bios-disk DISK      BIOS only: whole disk containing root and separate /boot
  --mapper NAME         New LUKS mapper name (default cryptroot); existing rejected
  --hostname NAME       Default archlinux
  --username NAME       Default benevantmathew
  --bootloader-id NAME  Default ARCH (UEFI vendor directory)
  --timezone ZONE       Default Asia/Kolkata (must exist in live zoneinfo)
  --locale LOCALE       Default en_IN.UTF-8 (UTF-8 locales only)
  --target-mount PATH   Default /mnt; /mnt or below, no symlinks or mounted trees
  --cpu-ucode PKG|NA    amd-ucode (default), intel-ucode, or NA to omit
  --gnome               Install GNOME/GDM and Bluetooth extras (default)
  --no-gnome            Base CLI + NetworkManager; omit desktop extras
  --dry-run             Validate and print plan only; no unlock/mount/write
  -h, --help            Unprivileged help; no device or firmware probing

Environment defaults (CLI overrides):
  EFI_PART, BOOT_PART, ROOT_PART (fallback ROOT_LUKS_PART), SWAP_PART: unset
  BOOT_MODE=auto BIOS_DISK=unset ROOT_MAPPER_NAME=cryptroot
  HOSTNAME=archlinux USERNAME=benevantmathew BOOTLOADER_ID=ARCH
  TIMEZONE=Asia/Kolkata LOCALE=en_IN.UTF-8 TARGET_MOUNT=/mnt
  CPU_UCODE=amd-ucode INSTALL_GNOME=true (or false)
Unset device roles prompt for /dev/path, UUID=..., PARTUUID=..., LABEL=...,
menu number, or 'list'. Optional boot/swap prompts accept NA (blank means NA).
BIOS disk is required in BIOS mode; EFI is required only in UEFI mode.
Closed stdin (EOF) aborts, including at confirmation.

Supported layouts and boundaries:
  Root and separate /boot MUST already contain ext4 filesystems; root may be
  an existing LUKS container with ext4 inside. LUKS REQUIRES separate unencrypted
  /boot: this installer does NOT support GRUB encrypted /boot unlocking.
  Inner ext4 is checked after unlock; dry-run cannot check a closed container.
  UEFI uses x86_64-efi GRUB and efibootmgr; boot the ISO in UEFI mode.
  BIOS uses i386-pc GRUB to the whole disk (never forces blocklists). MBR needs
  suitable embedding space. GPT needs an UNFORMATTED BIOS boot partition on
  that disk, GUID 21686148-6449-6e6f-744e-656564454649 (bios_grub), typically
  1-2 MiB. BIOS CAN use GPT, contrary to the old legacy notes in docs.
  Swap must be existing plain swap, not encrypted swap. No hibernation setup.
  Only selected swap goes into fstab; host's other swaps are never imported.
  Already-mounted devices/descendants and swap-in-use are rejected except
  selected existing plain swap may be reused (not reinitialized or activated).
  Selected roles must be distinct partitions, not disks/mappers/LVM devices.
  No automatic partitioning, mkfs, luksFormat, or mkswap. Target mounts and a
  newly opened mapper remain available for inspection when finished/on error.

Examples (replace devices with your own; add --dry-run to inspect first):
  # Plain unified /boot, UEFI, no swap:
  bash arch_install.sh --root /dev/nvme0n1p2 --boot NA --swap NA \
    --boot-mode uefi --efi /dev/nvme0n1p1
  # Plain separate /boot, UEFI, existing optional swap:
  bash arch_install.sh --root /dev/sda3 --boot /dev/sda2 --swap /dev/sda4 \
    --boot-mode uefi --efi /dev/sda1 --no-gnome --cpu-ucode intel-ucode
  # Encrypted root, UEFI (existing LUKS + inner ext4):
  bash arch_install.sh --root-luks /dev/sda3 --boot /dev/sda2 --swap NA \
    --boot-mode uefi --efi /dev/sda1
  # BIOS/MBR, plain unified root:
  bash arch_install.sh --root /dev/sda2 --boot NA --swap /dev/sda1 \
    --boot-mode bios --bios-disk /dev/sda --no-gnome
  # BIOS/GPT, LUKS; sda1 must already be unformatted bios_grub:
  bash arch_install.sh --root /dev/sda3 --boot /dev/sda2 --swap NA \
    --boot-mode bios --bios-disk /dev/sda --cpu-ucode NA
HELP
}
while (($#)); do
    opt=${1%%=*}
    case "$opt" in
        -h|--help) [[ "$1" == "$opt" ]] || fail "$opt takes no value"; usage; exit 0 ;;
        --gnome|--no-gnome|--dry-run)
            [[ "$1" == "$opt" ]] || fail "$opt takes no value"
            case "$opt" in --gnome) INSTALL_GNOME=true;; --no-gnome) INSTALL_GNOME=false;; --dry-run) DRY_RUN=true;; esac
            shift; continue ;;
        --efi|--boot|--root|--root-luks|--swap|--boot-mode|--bios-disk|--mapper|--hostname|--username|--bootloader-id|--timezone|--locale|--target-mount|--cpu-ucode) ;;
        *) fail "unknown option: $1 (see --help)" ;;
    esac
    if [[ "$1" == *=* ]]; then value=${1#*=}; shift
    else
        (($# >= 2)) && [[ "$2" != --* ]] || fail "$opt requires a value"
        value=$2; shift 2
    fi
    [[ -n "$value" ]] || fail "$opt requires a nonempty value"
    case "$opt" in
        --efi) EFI_PART=$value;; --boot) BOOT_PART=$value;;
        --root|--root-luks) ROOT_PART=$value;; --swap) SWAP_PART=$value;;
        --boot-mode) BOOT_MODE=$value;; --bios-disk) BIOS_DISK=$value;;
        --mapper) ROOT_MAPPER_NAME=$value;; --hostname) HOSTNAME=$value;;
        --username) USERNAME=$value;; --bootloader-id) BOOTLOADER_ID=$value;;
        --timezone) TIMEZONE=$value;; --locale) LOCALE=$value;;
        --target-mount) TARGET_MOUNT=$value;; --cpu-ucode) CPU_UCODE=$value;;
    esac
done

[[ "$BOOT_MODE" =~ ^(auto|uefi|bios)$ ]] || fail 'boot mode must be auto, uefi or bios'
[[ "$CPU_UCODE" =~ ^(amd-ucode|intel-ucode|NA)$ ]] || fail 'invalid microcode package'
[[ "$INSTALL_GNOME" =~ ^(true|false)$ ]] || fail 'INSTALL_GNOME must be true or false'
[[ "$HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || fail 'invalid hostname'
[[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ && "$USERNAME" != root ]] || fail 'invalid username'
[[ "$ROOT_MAPPER_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$ ]] || fail 'invalid mapper name'
[[ "$BOOTLOADER_ID" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$ ]] || fail 'invalid bootloader ID'
[[ "$LOCALE" =~ ^[a-z]{2,3}_[A-Z]{2}\.UTF-8$ ]] || fail 'locale must be a language_REGION.UTF-8 locale'
[[ "$TIMEZONE" =~ ^[a-zA-Z0-9_+-]+(/[a-zA-Z0-9_+-]+)*$ && -f "/usr/share/zoneinfo/$TIMEZONE" ]] || fail 'invalid or unavailable timezone'
[[ "$TARGET_MOUNT" =~ ^/mnt(/[a-zA-Z0-9_-]+)*$ ]] || fail 'target must be /mnt or a safe path below /mnt'
[[ "$(realpath -m -- "$TARGET_MOUNT")" == "$TARGET_MOUNT" ]] || fail 'target resolves through a symlink'
p=$TARGET_MOUNT
while [[ "$p" != / ]]; do
    [[ ! -L "$p" && ( ! -e "$p" || -d "$p" ) ]] || fail "unsafe target component: $p"
    p=${p%/*}; [[ -n "$p" ]] || p=/
done
[[ "$DRY_RUN" == true || $(id -u) == 0 ]] || fail 'run installation as root from the Arch ISO'
for cmd in lsblk blkid cryptsetup findmnt swapon realpath; do
    command -v "$cmd" >/dev/null || fail "required command not found: $cmd"
done
if [[ "$BOOT_MODE" == auto ]]; then
    if [[ -d /sys/firmware/efi ]]; then BOOT_MODE=uefi; else BOOT_MODE=bios; fi
fi
if [[ "$BOOT_MODE" == uefi ]]; then
    [[ -z "$BIOS_DISK" ]] || fail '--bios-disk is BIOS only'
    [[ -d /sys/firmware/efi ]] || fail 'UEFI installation requires an ISO booted in UEFI mode'
else
    [[ -z "$EFI_PART" ]] || fail '--efi is UEFI only'
fi
lsblk -o NAME,PATH,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS,MODEL || fail 'lsblk inspection failed'
MENU=$(lsblk -pnro NAME,TYPE) || fail 'partition menu inspection failed'
PART_DEVS=()
while read -r dev type; do [[ "$type" != part ]] || PART_DEVS+=("$dev"); done <<< "$MENU"
print_menu() {
    local i
    for i in "${!PART_DEVS[@]}"; do printf '%2d) %s\n' "$((i+1))" "${PART_DEVS[$i]}" >&2; done
}
resolve_device() {
    local input=$1 dev
    case "$input" in
        /dev/*) dev=$input ;;
        UUID=*|PARTUUID=*|LABEL=*)
            dev=$(blkid -t "$input" -o device) || return 1
            [[ -n "$dev" && "$dev" != *$'\n'* ]] || return 1 ;;
        *) return 1 ;;
    esac
    dev=$(realpath -e -- "$dev") || return 1
    [[ -b "$dev" ]] || return 1
    printf '%s\n' "$dev"
}
ask_device() {
    local role=$1 optional=$2 answer idx
    while true; do
        read -r -p "$role [device/menu/list; optional roles accept NA]: " answer || { echo 'ERROR: EOF while selecting device' >&2; return 1; }
        case "$answer" in
            list) print_menu; continue;;
            NA|'') if [[ "$optional" == yes ]]; then printf 'NA\n'; return; fi;;
        esac
        if [[ "$answer" =~ ^[0-9]{1,3}$ ]]; then
            idx=$((10#$answer - 1))
            if ((idx >= 0 && idx < ${#PART_DEVS[@]})); then answer=${PART_DEVS[$idx]}; fi
        fi
        if resolve_device "$answer"; then return; fi
        echo 'Invalid device selection; required roles cannot be NA.' >&2
    done
}
select_device() {
    local var=$1 role=$2 optional=$3 value=${!1}
    if [[ -z "$value" ]]; then value=$(ask_device "$role" "$optional") || fail "device selection aborted: $role"
    elif [[ "$value" != NA || "$optional" != yes ]]; then value=$(resolve_device "$value") || fail "invalid device for $role"; fi
    printf -v "$var" '%s' "$value"
}
print_menu
select_device ROOT_PART Root no
select_device BOOT_PART 'Separate unencrypted /boot' yes
select_device SWAP_PART Swap yes
if [[ "$BOOT_MODE" == uefi ]]; then select_device EFI_PART EFI no
else select_device BIOS_DISK 'BIOS whole disk' no; fi

field() { lsblk -dnro "$1" "$2" || fail "cannot inspect $2"; }
signature() {
    local value status
    if value=$(blkid -p -s TYPE -o value "$1" 2>/dev/null); then
        printf '%s\n' "$value"
    else
        status=$?
        [[ "$status" == 2 ]] || fail "filesystem signature inspection failed: $1 (status $status)"
    fi
}
uuid() {
    local u
    u=$(blkid -s UUID -o value "$1") || fail "cannot read UUID: $1"
    [[ "$u" =~ ^[a-zA-Z0-9-]+$ ]] || fail "invalid/missing UUID: $1"
    printf '%s\n' "$u"
}
roles=("$ROOT_PART")
[[ "$BOOT_PART" == NA ]] || roles+=("$BOOT_PART")
[[ "$SWAP_PART" == NA ]] || roles+=("$SWAP_PART")
[[ "$BOOT_MODE" != uefi ]] || roles+=("$EFI_PART")
declare -A seen=()
for dev in "${roles[@]}"; do
    [[ $(field TYPE "$dev") == part ]] || fail "roles require raw partitions: $dev"
    key=$(field MAJ:MIN "$dev")
    [[ "$key" =~ ^[0-9]+:[0-9]+$ && ! ${seen[$key]+present} ]] || fail 'device roles must be distinct'
    seen[$key]=1
done
ENCRYPTED=false
if cryptsetup isLuks "$ROOT_PART"; then ENCRYPTED=true; fi
if [[ "$ENCRYPTED" == true ]]; then
    [[ "$BOOT_PART" != NA ]] || fail 'LUKS root requires separate unencrypted /boot; GRUB encrypted boot is not supported'
    [[ ! -e "/dev/mapper/$ROOT_MAPPER_NAME" && ! -L "/dev/mapper/$ROOT_MAPPER_NAME" ]] || fail 'mapper already exists; refusing reuse/collision'
else
    [[ $(signature "$ROOT_PART") == ext4 ]] || fail 'plain root must already contain ext4'
fi
[[ "$BOOT_PART" == NA || $(signature "$BOOT_PART") == ext4 ]] || fail 'separate boot must already contain unencrypted ext4'
[[ "$SWAP_PART" == NA || $(signature "$SWAP_PART") == swap ]] || fail 'selected swap must already contain a plain swap signature'
[[ "$BOOT_MODE" != uefi || $(signature "$EFI_PART") == vfat ]] || fail 'EFI must already contain vfat'
if [[ "$BOOT_MODE" == bios ]]; then
    [[ $(field TYPE "$BIOS_DISK") == disk ]] || fail 'BIOS target must be a whole disk'
    for dev in "$ROOT_PART" "$BOOT_PART"; do
        [[ "$dev" != NA ]] || continue
        ancestors=$(lsblk -snrpo NAME "$dev") || fail 'cannot inspect disk ancestry'
        found=false
        while read -r ancestor; do [[ "$ancestor" != "$BIOS_DISK" ]] || found=true; done <<< "$ancestors"
        [[ "$found" == true ]] || fail "root and boot must be on BIOS disk: $dev"
    done
    table=$(field PTTYPE "$BIOS_DISK")
    case "$table" in
        dos) ;;
        gpt)
            command -v wipefs >/dev/null || fail 'required command not found: wipefs'
            partitions=$(lsblk -nrpo NAME,TYPE,PARTTYPE "$BIOS_DISK") || fail 'cannot inspect GPT partitions'
            bios_found=false
            while read -r dev type guid; do
                if [[ "$type" == part && "${guid,,}" == 21686148-6449-6e6f-744e-656564454649 ]]; then
                    # Inspect all signatures, including a stale partition-table signature.
                    bios_signature=$(wipefs --no-act --noheadings --output TYPE "$dev") || fail 'cannot inspect BIOS boot partition signature'
                    [[ -z "$bios_signature" ]] || fail 'BIOS boot partition must be unformatted'
                    bios_found=true
                fi
            done <<< "$partitions"
            [[ "$bios_found" == true ]] || fail 'GPT BIOS requires an unformatted bios_grub partition on selected disk' ;;
        *) fail 'BIOS disk must use MBR (dos) or GPT' ;;
    esac
fi
# All mount-table queries are captured directly: process substitutions would hide failures.
mount_table() { findmnt -rn -o TARGET || fail 'mount table inspection failed'; }
assert_target_free() {
    local mounts m
    mounts=$(mount_table) || fail 'mount table inspection failed'
    while read -r m; do
        [[ "$m" != "$TARGET_MOUNT" && "$m" != "$TARGET_MOUNT/"* ]] || fail 'target or nested target already mounted'
    done <<< "$mounts"
}
assert_devices_free() {
    local mounted swaps dev rows node key swap canonical swapkey mountedkey
    mounted=$(findmnt -rn -o MAJ:MIN) || fail 'mount source inspection failed'
    swaps=$(swapon --show --raw --noheadings --output NAME) || fail 'swap inspection failed'
    local -A swapkeys=()
    while read -r swap; do
        [[ -n "$swap" ]] || continue
        # Host swap files are unrelated to raw selected partitions and are never imported.
        if [[ -b "$swap" ]]; then
            canonical=$(realpath -e -- "$swap") || fail 'cannot resolve active swap'
            swapkey=$(field MAJ:MIN "$canonical"); swapkeys[$swapkey]=1
        fi
    done <<< "$swaps"
    local -a inspect=("${roles[@]}")
    [[ "$BOOT_MODE" != bios ]] || inspect+=("$BIOS_DISK")
    for dev in "${inspect[@]}"; do
        rows=$(lsblk -nrpo NAME,MAJ:MIN "$dev") || fail 'device descendant inspection failed'
        [[ -n "$rows" ]] || fail 'empty device descendant inspection'
        while read -r node key; do
            [[ "$key" =~ ^[0-9]+:[0-9]+$ ]] || fail 'missing/invalid device identity'
            while read -r mountedkey; do [[ "$mountedkey" != "$key" ]] || fail "device/descendant already mounted: $node"; done <<< "$mounted"
            if [[ ${swapkeys[$key]+present} ]]; then
                [[ "$SWAP_PART" != NA && "$key" == "$(field MAJ:MIN "$SWAP_PART")" ]] || fail "device/descendant in swap use: $node"
            fi
        done <<< "$rows"
    done
}
assert_target_free
assert_devices_free
ROOT_UUID=$(uuid "$ROOT_PART")
[[ "$SWAP_PART" == NA ]] || SWAP_UUID=$(uuid "$SWAP_PART")
printf '\nInstall plan (NO FORMAT; root and separate boot contents WILL BE CLEARED)\n'
printf 'Mode: %s; encrypted root: %s\nRoot: %s\nBoot: %s\nSwap: %s\nEFI: %s (preserved)\nBIOS disk: %s\nTarget: %s\n' "$BOOT_MODE" "$ENCRYPTED" "$ROOT_PART" "$BOOT_PART" "$SWAP_PART" "${EFI_PART:-NA}" "${BIOS_DISK:-NA}" "$TARGET_MOUNT"
printf 'Hostname: %s; user: %s; mapper: %s; bootloader ID: %s\nTimezone: %s; locale: %s; microcode: %s; GNOME: %s\n' "$HOSTNAME" "$USERNAME" "$ROOT_MAPPER_NAME" "$BOOTLOADER_ID" "$TIMEZONE" "$LOCALE" "$CPU_UCODE" "$INSTALL_GNOME"
if [[ "$DRY_RUN" == true ]]; then
    [[ "$ENCRYPTED" != true ]] || echo 'Inner root ext4 will be validated only after unlocking during installation.'
    exit 0
fi
for cmd in mount mountpoint pacstrap genfstab arch-chroot find rm awk; do
    command -v "$cmd" >/dev/null || fail "required command not found: $cmd"
done
# Preserve the old encrypted confirmation phrase for existing users.
if [[ "$ENCRYPTED" == true ]]; then expected="INSTALL ARCH LUKS NO FORMAT $ROOT_PART"
else expected="INSTALL ARCH NO FORMAT $ROOT_PART"; fi
printf '\nType exactly this to continue: %s\n' "$expected"
read -r answer || fail 'EOF at confirmation; aborted'
[[ "$answer" == "$expected" ]] || fail 'confirmation mismatch; aborted'
# Recheck after interactive delay, before any unlocking/mounting/deleting.
assert_target_free
assert_devices_free
[[ "$(realpath -m -- "$TARGET_MOUNT")" == "$TARGET_MOUNT" ]] || fail 'target changed to symlink'
ROOT_DEV=$ROOT_PART
if [[ "$ENCRYPTED" == true ]]; then
    [[ ! -e "/dev/mapper/$ROOT_MAPPER_NAME" && ! -L "/dev/mapper/$ROOT_MAPPER_NAME" ]] || fail 'mapper collision'
    cryptsetup open "$ROOT_PART" "$ROOT_MAPPER_NAME"
    ROOT_DEV="/dev/mapper/$ROOT_MAPPER_NAME"
    [[ $(signature "$ROOT_DEV") == ext4 ]] || fail 'inner root filesystem must already be ext4'
fi
clear_mounted_directory_contents() {
    local dir=$1 source=$2 actual expected_source mounts m found=false
    [[ "$dir" == "$TARGET_MOUNT" || "$dir" == "$TARGET_MOUNT/boot" ]] || fail 'unsafe clear target'
    mountpoint -q "$dir" || fail 'refusing clear: not a mountpoint'
    actual=$(findmnt -rn -M "$dir" -o MAJ:MIN) || fail 'cannot verify mounted source'
    expected_source=$(field MAJ:MIN "$source") || fail 'cannot inspect expected mounted source'
    [[ "$expected_source" =~ ^[0-9]+:[0-9]+$ && "$actual" == "$expected_source" ]] || fail 'refusing clear: mounted source mismatch'
    mounts=$(mount_table) || fail 'mount table inspection failed before clear'
    while read -r m; do
        [[ "$m" != "$dir/"* ]] || fail "refusing clear: nested mount $m"
        [[ "$m" != "$dir" ]] || found=true
    done <<< "$mounts"
    [[ "$found" == true ]] || fail 'refusing clear: mount missing from inspected table'
    printf 'Clearing existing contents under %s\n' "$dir"
    find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
}
mkdir -p "$TARGET_MOUNT"
mount -t ext4 "$ROOT_DEV" "$TARGET_MOUNT"
clear_mounted_directory_contents "$TARGET_MOUNT" "$ROOT_DEV"
mkdir -p "$TARGET_MOUNT/boot"
if [[ "$BOOT_PART" != NA ]]; then
    mount -t ext4 "$BOOT_PART" "$TARGET_MOUNT/boot"
    clear_mounted_directory_contents "$TARGET_MOUNT/boot" "$BOOT_PART"
fi
# Mount ESP only AFTER root and boot clearing, never clear it.
if [[ "$BOOT_MODE" == uefi ]]; then
    mkdir -p "$TARGET_MOUNT/boot/efi"
    mount -t vfat "$EFI_PART" "$TARGET_MOUNT/boot/efi"
fi
base_packages=(base linux linux-firmware vim sudo networkmanager grub cryptsetup)
[[ "$BOOT_MODE" != uefi ]] || base_packages+=(efibootmgr)
[[ "$CPU_UCODE" == NA ]] || base_packages+=("$CPU_UCODE")
if [[ "$INSTALL_GNOME" == true ]]; then base_packages+=(gnome gdm bluez bluez-utils blueman ntfs-3g); fi
pacstrap "$TARGET_MOUNT" "${base_packages[@]}"
fstab=$(genfstab -U "$TARGET_MOUNT") || fail 'genfstab failed'
printf '%s\n' "$fstab" | awk 'NF == 0 || $1 ~ /^#/ || $3 != "swap"' > "$TARGET_MOUNT/etc/fstab"
if [[ "$SWAP_PART" != NA ]]; then printf 'UUID=%s none swap sw 0 0\n' "$SWAP_UUID" >> "$TARGET_MOUNT/etc/fstab"; fi
# Literal heredoc + positional args: no caller-controlled shell code interpolation.
arch-chroot "$TARGET_MOUNT" /bin/bash -s -- "$HOSTNAME" "$USERNAME" "$TIMEZONE" "$LOCALE" "$INSTALL_GNOME" "$ENCRYPTED" "$ROOT_UUID" "$ROOT_MAPPER_NAME" "$BOOT_MODE" "$BIOS_DISK" "$BOOTLOADER_ID" <<'CHROOT_EOF'
set -euo pipefail
hostname=$1 username=$2 timezone=$3 locale=$4 gnome=$5 encrypted=$6 root_uuid=$7 mapper=$8 mode=$9 disk=${10} bootloader_id=${11}
printf '%s\n' "$hostname" > /etc/hostname
printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 %s.localdomain %s\n' "$hostname" "$hostname" > /etc/hosts
# Append only a validated UTF-8 locale; existing commented entries need not be edited.
printf '%s UTF-8\n' "$locale" >> /etc/locale.gen
locale-gen
printf 'LANG=%s\n' "$locale" > /etc/locale.conf
ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
hwclock --systohc --utc
systemctl enable NetworkManager
if [[ "$gnome" == true ]]; then systemctl enable gdm; systemctl enable bluetooth; fi
groupadd -f sudo
if ! id "$username" >/dev/null 2>&1; then useradd -m -d "/home/$username" -s /bin/bash -G sudo "$username"; fi
printf '%%sudo ALL=(ALL:ALL) ALL\n' > /etc/sudoers.d/10-sudo-group
chmod 0440 /etc/sudoers.d/10-sudo-group
hooks='base udev autodetect microcode modconf kms keyboard keymap consolefont block'
if [[ "$encrypted" == true ]]; then hooks+=' encrypt'; fi
hooks+=' filesystems fsck'
sed -i "s/^HOOKS=.*/HOOKS=($hooks)/" /etc/mkinitcpio.conf
mkinitcpio -P
cmdline="root=UUID=$root_uuid"
if [[ "$encrypted" == true ]]; then cmdline="cryptdevice=UUID=$root_uuid:$mapper root=/dev/mapper/$mapper"; fi
sed -i '/^GRUB_CMDLINE_LINUX=/d' /etc/default/grub
printf 'GRUB_CMDLINE_LINUX="%s"\n' "$cmdline" >> /etc/default/grub
if [[ "$mode" == uefi ]]; then
    grub-install --target=x86_64-efi --bootloader-id="$bootloader_id" --efi-directory=/boot/efi
else
    grub-install --target=i386-pc "$disk"
fi
grub-mkconfig -o /boot/grub/grub.cfg
CHROOT_EOF
printf '\nSet root password\n'
arch-chroot "$TARGET_MOUNT" passwd
printf '\nSet password for %s\n' "$USERNAME"
arch-chroot "$TARGET_MOUNT" passwd "$USERNAME"
printf '\nInstall complete. Review %s/etc/fstab, etc/default/grub and boot/grub/grub.cfg.\nUnmount with: umount -R %s\n' "$TARGET_MOUNT" "$TARGET_MOUNT"
[[ "$ENCRYPTED" != true ]] || printf 'Then close mapper: cryptsetup close %s\n' "$ROOT_MAPPER_NAME"
echo 'Reboot only after review. Mounts/mapper are deliberately left available, also on failure.'
