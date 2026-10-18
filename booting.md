# Booting polpo

polpo can be the whole user space of a Linux machine: the kernel starts `loksh` as its first
process, `boot.Init` prepares the system, and the Oberon desktop takes the screen. There is no
shell, no libc and no init system besides polpo itself; the kernel, an initramfs holding polpo,
and a few kernel modules are enough. This note builds such an initramfs, tries it in qemu, and
boots a real machine with it.

## What the first process does

The kernel runs the program named by `rdinit=` in the initramfs, with the words after `--` on
the kernel command line as its arguments:

    rdinit=/polpo/bin/x86/loksh -- boot.Init

`boot.Init` (src/cli/boot.Mod) then

- mounts `/proc`, `/sys`, `/dev` (devtmpfs, where the kernel puts the device files) and `/tmp`;
- opens `/dev/tty1` as standard input, output and error, and makes it the controlling terminal,
  which the desktop reads the keyboard from;
- loads the kernel modules listed in `boot.modules` of the polpo directory;
- runs `System.Init`, the desktop, or the command given after it (`boot.Init Hello.Open`).

The first process of a Linux system may not end: the kernel stops with a panic when it does.
When the desktop quits (`System.Quit`) or the command returns, `boot` writes the disk caches
back and powers the machine off.

The desktop draws on the screen through `/dev/fb0` when the kernel has it, and through KMS
(`/dev/dri/card0`) otherwise; it takes the keyboard from the console and the mouse from
`/dev/input/mice`. See desktop.md, the Linux console.

## What the kernel needs

Most distribution kernels have all of it, part of it as modules:

- an initramfs: `CONFIG_BLK_DEV_INITRD`;
- `CONFIG_DEVTMPFS`, `CONFIG_VT`, `CONFIG_INPUT_MOUSEDEV` (`/dev/input/mice`) and the
  keyboard and mouse drivers: PS/2 (`CONFIG_KEYBOARD_ATKBD`, `CONFIG_MOUSE_PS2`), or USB
  (`CONFIG_USB_HID` and the USB host controller drivers, often modules: `xhci_hcd`,
  `ehci_hcd`);
- a driver for the graphics card: a DRM driver (`i915`, `amdgpu`, `nouveau`, `bochs`,
  `virtio-gpu`, ...) or a framebuffer device (`CONFIG_FB_DEVICE` gives `/dev/fb0`);
- for polpo's x86 port (32-bit) on a 64-bit kernel: `CONFIG_IA32_EMULATION`.

`grep CONFIG_DRM_BOCHS /boot/config-$(uname -r)` and the like tell what a kernel has: `=y` is
built in, `=m` a module that `boot.modules` must list.

## Finding the modules

On the machine that is to run polpo, with its usual system running:

    readlink /sys/class/drm/card0/device/driver      # the graphics driver, e.g. .../i915
    modinfo -F depends i915                          # the modules it needs, load those first
    modinfo -F filename i915                         # where the module file is
    modinfo -F firmware i915                         # the firmware files it may load

Follow the dependencies down until a module needs no other module; `boot.modules` lists them
from the bottom up. Modules that are built into the kernel (`modinfo` says `(builtin)`) need no
line. Compressed modules (`.ko.xz`, `.ko.zst`) must be decompressed (`xz -d`, `zstd -d`):
`boot` loads plain `.ko` files. The firmware files go to `/lib/firmware/` in the initramfs, at
the same path below it as on the running system; the kernel loads them from there.

For qemu with `-vga std`, the graphics driver is `bochs`, and on the kernels tried so far it
needed

    drm_kms_helper
    drm_shmem_helper
    drm_client_lib
    bochs

## Building the initramfs

The initramfs is a cpio archive of a small directory tree: polpo below `/polpo`, the modules,
and the firmware if any. No device files and no other programs are needed; `boot` makes the
directories it mounts. As an ordinary user, from the polpo directory:

    K=7.2.9-gentoo-dist                  # the kernel version (uname -r on that machine)
    M=/lib/modules/$K/kernel/drivers/gpu/drm
    R=/tmp/polpo-root                    # the tree of the initramfs
    rm -rf $R && mkdir -p $R/polpo/bin/x86 $R/polpo/obj $R/polpo/modules
    cp bin/x86/loksh $R/polpo/bin/x86/
    cp -r obj/x86 $R/polpo/obj/
    cp -r fonts share tools texts Oberon.Text VERSION $R/polpo/
    cp $M/drm_kms_helper.ko $M/drm_shmem_helper.ko $M/clients/drm_client_lib.ko \
       $M/tiny/bochs.ko $R/polpo/modules/
    cat > $R/polpo/boot.modules <<EOF
    # kernel modules for the screen, in the order of their dependencies
    modules/drm_kms_helper.ko
    modules/drm_shmem_helper.ko
    modules/drm_client_lib.ko
    modules/bochs.ko
    EOF
    (cd $R && find . | cpio -o -H newc | gzip -1) > /tmp/polpo-initrd.gz

The image is about 8 MB. Packages installed with portia have their objects in `obj/x86/` and
their data in `share/` and `tools/`, so they come along. For one of the other ports, copy
`bin/<arch>/loksh` and `obj/<arch>/` instead, name that loksh in `rdinit=`, and use a kernel for
that processor.

The initramfs lives in memory: whatever is written while polpo runs (stored texts, panels) is
gone after the power off. `boot` mounts no disks.

## Trying it in qemu

    qemu-system-x86_64 -m 1024 -vga std \
      -kernel /boot/vmlinuz-7.2.9-gentoo-dist -initrd /tmp/polpo-initrd.gz \
      -append "rdinit=/polpo/bin/x86/loksh -- boot.Init"

The qemu window shows the desktop after a few seconds (half a minute or more without KVM).
Click into the qemu window to give it the mouse and keyboard; Ctrl+Alt+G releases them. Middle-
click `System.Quit` in a text to power the virtual machine off. With `-vga virtio`, the driver
is `virtio-gpu` (its module and dependencies instead of bochs').

To watch the kernel messages in the terminal, add `-serial stdio` to the qemu command and
`console=ttyS0` to the kernel command line. `boot` prints what it does, and which modules
failed to load, on the screen (tty1), before the desktop takes it.

## Booting a real machine

Copy the kernel and the initramfs to `/boot` and give the boot loader an entry for them. With
GRUB, in `/etc/grub.d/40_custom` (then `grub-mkconfig -o /boot/grub/grub.cfg`):

    menuentry "polpo" {
        linux  /boot/vmlinuz-7.2.9-gentoo-dist rdinit=/polpo/bin/x86/loksh -- boot.Init
        initrd /boot/polpo-initrd.gz
    }

The paths are those GRUB sees: when `/boot` is a partition of its own, they start without
`/boot`. Choose the entry when the machine starts; the desktop comes up on the whole screen in
the preferred mode of the first connected monitor. `System.Quit` powers the machine off.

The usual system on the disk is untouched, and choosing its own entry at the next start brings
it back.

## When it does not come up

- **The screen keeps the kernel's text, and no desktop appears**: the graphics driver is
  missing. Look at what `boot` printed on tty1 (a module "not found" or "failed, error n"), add
  the missing module or firmware, and build the image again.
- **"Can't open '/dev/fb0' nor '/dev/dri/card0'"**: no graphics driver loaded at all.
- **The desktop shows, but the mouse or the keyboard does nothing**: the USB host controller or
  HID modules are missing (`xhci_hcd`, `usbhid`, `hid_generic`), or the mouse is not on
  `/dev/input/mice` (`CONFIG_INPUT_MOUSEDEV`).
- **Kernel panic "No working init found"**: the kernel could not start loksh: `rdinit=` names a
  path that is not in the initramfs, the loksh is for another processor, or a 64-bit kernel
  lacks `CONFIG_IA32_EMULATION` for the 32-bit x86 loksh.
- **Kernel panic "Attempted to kill init"**: loksh started and ended, for instance after a trap
  in the command given to `boot.Init` before the desktop was running.
