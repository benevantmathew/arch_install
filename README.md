# Arch Install Script

Interactive Arch Linux installer for **existing, manually prepared partitions**. Supports plain ext4 or an existing LUKS container with ext4 inside, UEFI or BIOS boot, and an optional GNOME desktop.

The entry point in this repository is `arch_install.sh`.

## Safety: no formatting does not mean no data loss

**Installation deletes all existing contents of the selected root filesystem and, when selected, the separate `/boot` filesystem. Back up their contents first.** This includes home directories stored inside root.

The script does not partition disks, create filesystems, create LUKS containers, or initialize swap. Prepare these yourself before running it.

- The EFI system partition (ESP) is preserved, but GRUB adds or updates the selected bootloader vendor directory and may change firmware boot entries. Choose a distinct `--bootloader-id` when sharing an ESP with another installation.
- BIOS installation writes GRUB to the selected whole disk and its embedding area. It is not a read-only operation.
- Mounted selected devices or descendants, conflicting device roles, and existing mapper-name collisions are rejected. An already-active selected plain swap partition may be reused.
- Deletion checks verify the mounted source and reject nested mounts before clearing root or boot.
- An exact confirmation is required before unlocking, mounting, deleting, or installing. Closed stdin aborts.
- Mounts and a newly opened LUKS mapper are deliberately left available on success or failure. There is no automatic rollback or cleanup.

## Requirements

Run installation as root from a current **Arch Linux live ISO**, with working networking and access to Arch package mirrors. For UEFI installation, boot the ISO in UEFI mode.

The live environment must provide Bash, `lsblk`, `blkid`, `cryptsetup`, `findmnt`, `swapon`, `realpath`, `mount`, `mountpoint`, `pacstrap`, `genfstab`, `arch-chroot`, `find`, `rm`, and `awk`. BIOS/GPT validation also requires `wipefs`. The chroot uses standard Arch configuration tools, including `sed`.

Device preparation is manual:

| Role | Required preparation |
| --- | --- |
| Root | Raw partition containing ext4, or an existing LUKS container containing ext4 |
| Separate `/boot` | Optional unencrypted ext4 partition; mandatory for LUKS root |
| ESP | Existing vfat partition, required only for UEFI; mounted at `/boot/efi` |
| Swap | Optional existing plain swap partition |
| BIOS disk | Whole disk containing root and any separate boot partition |
| BIOS boot partition | For BIOS on GPT: an unformatted `bios_grub` partition on the selected disk, typically 1–2 MiB |

BIOS can use either MBR (`dos`) or GPT. MBR must have suitable GRUB embedding space. The GPT BIOS boot partition type GUID is `21686148-6449-6e6f-744e-656564454649`.

Not supported: encrypted `/boot`, encrypted swap, hibernation setup, root/boot filesystems other than ext4, or device roles supplied as LVM volumes or existing mapper devices. Supply the raw LUKS partition for encrypted root, not `/dev/mapper/...`.

## Get started

```bash
git clone https://github.com/benevantmathew/arch_install.git
cd arch_install
bash arch_install.sh --help
```

Inspect your devices before choosing them:

```bash
lsblk -o NAME,PATH,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS,MODEL
```

Start an interactive validation-only run:

```bash
bash arch_install.sh --dry-run
```

Or start the real interactive installer from the live ISO as root:

```bash
bash arch_install.sh
```

Unset device roles prompt for a device path, `UUID=...`, `PARTUUID=...`, `LABEL=...`, a partition-menu number, or `list`. Optional boot and swap prompts accept `NA`; a blank answer also means `NA`. CLI device arguments accept paths and the identifier forms, but not menu numbers.

`--dry-run` validates devices and prints the plan without unlocking, mounting, deleting, or installing. It may run unprivileged, but device/signature inspection can still require root permissions. It cannot validate ext4 inside a closed LUKS container, package downloads, or whether the resulting system will boot.

## Examples

**All device names below are placeholders. Replace them with your own. Add `--dry-run` first, review the plan, then remove it only when ready to erase the selected root/boot contents.**

### UEFI, plain root, `/boot` inside root, no swap

```bash
bash arch_install.sh --root /dev/nvme0n1p2 --boot NA --swap NA \
  --boot-mode uefi --efi /dev/nvme0n1p1 --cpu-ucode intel-ucode
```

### UEFI, plain root, separate boot, existing swap, no desktop

```bash
bash arch_install.sh --root /dev/sda3 --boot /dev/sda2 --swap /dev/sda4 \
  --boot-mode uefi --efi /dev/sda1 --no-gnome --cpu-ucode intel-ucode
```

### UEFI, existing LUKS root, separate unencrypted boot

```bash
bash arch_install.sh --root /dev/sda3 --boot /dev/sda2 --swap NA \
  --boot-mode uefi --efi /dev/sda1 --mapper cryptarch \
  --bootloader-id ARCH_LUKS
```

The script detects LUKS automatically. `--root-luks` is a backward-compatible alias for `--root`, not an instruction to create encryption. A LUKS root with `--boot NA` is rejected.

### BIOS/MBR, plain root, unified boot

```bash
bash arch_install.sh --root /dev/sda2 --boot NA --swap /dev/sda1 \
  --boot-mode bios --bios-disk /dev/sda --no-gnome
```

### BIOS/GPT, existing LUKS root

Here `/dev/sda1` must already be an unformatted `bios_grub` partition, `/dev/sda2` ext4 boot, and `/dev/sda3` LUKS with ext4 inside.

```bash
bash arch_install.sh --root /dev/sda3 --boot /dev/sda2 --swap NA \
  --boot-mode bios --bios-disk /dev/sda --cpu-ucode NA
```

## Options and defaults

Value-taking options accept either `--option VALUE` or `--option=VALUE`. CLI values override environment defaults.

| Option | Default / behavior | Environment variable |
| --- | --- | --- |
| `--root DEV` | Prompt; detects plain ext4 or LUKS | `ROOT_PART`, fallback `ROOT_LUKS_PART` |
| `--root-luks DEV` | Alias for `--root` | Same as root |
| `--boot DEV\|NA` | Prompt; `NA` keeps boot inside root | `BOOT_PART` |
| `--swap DEV\|NA` | Prompt; `NA` omits swap | `SWAP_PART` |
| `--efi DEV` | Prompt in UEFI mode only | `EFI_PART` |
| `--boot-mode MODE` | `auto`, detects current firmware; also `uefi` or `bios` | `BOOT_MODE` |
| `--bios-disk DISK` | Required in BIOS mode only | `BIOS_DISK` |
| `--mapper NAME` | `cryptroot`; must not already exist | `ROOT_MAPPER_NAME` |
| `--hostname NAME` | `archlinux` | `HOSTNAME` |
| `--username NAME` | `benevantmathew` | `USERNAME` |
| `--bootloader-id NAME` | `ARCH` | `BOOTLOADER_ID` |
| `--timezone ZONE` | `Asia/Kolkata`; must exist in live zoneinfo | `TIMEZONE` |
| `--locale LOCALE` | `en_IN.UTF-8`; UTF-8 locale syntax required | `LOCALE` |
| `--target-mount PATH` | `/mnt`; must be `/mnt` or a safe path below it | `TARGET_MOUNT` |
| `--cpu-ucode PKG\|NA` | `amd-ucode`; also `intel-ucode` or `NA` | `CPU_UCODE` |
| `--gnome` / `--no-gnome` | GNOME enabled | `INSTALL_GNOME=true` or `false` |
| `--dry-run` | Validate and print plan only | None |
| `-h`, `--help` | Show help without device/firmware probing | None |

`HOSTNAME` may already be exported by your shell; pass `--hostname` explicitly if you want a predictable target hostname. Choose the microcode package appropriate for your CPU; the script does not auto-detect the CPU vendor.

## What installation configures

1. Validates the topology, existing signatures, target path, and device use; prints the install plan.
2. Requires one of these exact phrases, using the actual selected raw root path:
   - Plain root: `INSTALL ARCH NO FORMAT /dev/your-root-partition`
   - LUKS root: `INSTALL ARCH LUKS NO FORMAT /dev/your-root-partition`
3. Rechecks device use, opens LUKS if applicable, and validates its inner ext4 filesystem.
4. Mounts and clears root and any separate boot filesystem, then mounts the preserved ESP for UEFI.
5. Installs `base`, `linux`, `linux-firmware`, `vim`, `sudo`, `networkmanager`, `grub`, and `cryptsetup`. UEFI adds `efibootmgr`; selected microcode is also installed.
6. With GNOME enabled, adds `gnome`, `gdm`, `bluez`, `bluez-utils`, `blueman`, and `ntfs-3g`.
7. Generates UUID-based fstab entries and includes only the explicitly selected swap partition, not unrelated host swaps.
8. Configures hostname, hosts, locale, timezone, and UTC hardware clock. Enables NetworkManager and, for desktop installs, GDM and Bluetooth.
9. Creates the requested user with a home directory and Bash shell, adds it to the `sudo` group, and enables password-authenticated sudo for that group.
10. Configures mkinitcpio, adding `encrypt` before `filesystems` for LUKS root, and regenerates initramfs images.
11. Installs UEFI GRUB (`x86_64-efi`) or BIOS GRUB (`i386-pc`) and generates `/boot/grub/grub.cfg`. LUKS kernel arguments use `cryptdevice=UUID=...:mapper` and the mapper root path.
12. Prompts to set root and user passwords interactively.

The installed Arch system uses systemd. This is an Arch installer, not the separate Bene-LFS SysV installer.

## Review and cleanup

Before rebooting, inspect the installed configuration (substitute your target mount if not `/mnt`):

```bash
less /mnt/etc/fstab
less /mnt/etc/default/grub
less /mnt/boot/grub/grub.cfg
```

Leave the target directory and close any shells using it before unmounting:

```bash
cd /
umount -R /mnt
# For encrypted root only, after successful unmount:
cryptsetup close cryptroot
```

Use your selected mapper name if different. Do not reboot until installation, password setup, and configuration review are complete. If unmount fails, investigate the busy mounts/processes rather than closing an in-use mapper.

## Troubleshooting

- **LUKS requires separate boot:** supply an existing unencrypted ext4 boot partition; unified encrypted boot is intentionally unsupported.
- **Device already mounted or mapper already exists:** inspect current mounts and close/unmount only resources you own. The installer does not automatically take over an active installation.
- **Target or nested target already mounted:** unmount the old target safely, or select a different unused path below `/mnt`.
- **UEFI firmware check fails:** reboot the Arch ISO in UEFI mode. Specifying `--boot-mode uefi` does not change the live firmware mode.
- **GPT BIOS validation fails:** prepare the unformatted BIOS boot partition manually before retrying.
- **Download/pacstrap failure:** restore networking or mirror access first. Root and boot may already have been cleared; a failed run is not rolled back.
- **Rerunning after failure:** first inspect the deliberately retained target mounts and mapper. The script has no resume mode; another accepted installation starts by clearing the selected root/boot again.

For documentation/syntax checks without performing an installation:

```bash
bash -n arch_install.sh
bash arch_install.sh --help
```

These checks do not replace a complete installation test in a disposable VM.
