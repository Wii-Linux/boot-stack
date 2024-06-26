#!/bin/ash
# shellcheck shell=bash
if ! [ -c /dev/tty0 ]; then
    mount -t devtmpfs dev /dev
    mount -t sysfs sys /sys
    mount -t proc proc /proc
    mount -t tmpfs run /run
fi
# still nothing?  probably failed
if ! [ -c /dev/tty0 ]; then
    mknod /dev/tty0    c 4 0
    mknod /dev/tty     c 5 0
    mknod /dev/console c 5 1
    mknod /dev/null    c 1 3
fi

exec < /dev/console > /dev/console 2> /dev/console

# manual version of "reset" utility, but don't erase tux
# printf "\033c\033(B\033[m"
# printf "\033[6;1H\033[J"
reset
echo "Wii Linux loader.img init v0.0.1"

cat /proc/sys/kernel/printk > /._printk_restore
printf "1\t4\t1\t7" > /proc/sys/kernel/printk

echo "loader.img starting" > /dev/kmsg

# nuke jit_setup.sh so the user can't screw up their initramfs and be forced to reboot
rm /jit_setup.sh

. /logging.sh
. /support.sh
. /network.sh
. /util.sh

printf "1\t4\t1\t7" > /proc/sys/kernel/printk
# SD Drivers
# modprobe gcn-sd
if ! (modprobe mmc_block; modprobe mmc_core; modprobe sdhci-of-hlwd); then
    error "failed to load SD modules"
    support
fi


# USB Drivers
if ! (modprobe usbcore;modprobe ehci-hcd;modprobe ohci-hcd;modprobe hid-generic;modprobe usbhid); then
    error "failed to load USB modules"
    support
fi

if ! (modprobe usb-storage; modprobe uas; modprobe sd_mod); then
	error "failed to load USB storage modules"
	recoveryShell
fi

printf "1\t4\t1\t7" > /proc/sys/kernel/printk

# Filesystem drivers
modprobe ext4
modprobe vfat

# global variables
auto_boot_partition=""
auto_boot_timeout=500

# parse cmdline
for arg in $(cat /proc/cmdline); do
    if echo "$arg" | grep 'wii_linux.loader'; then
        # parse it
        case "$arg" in
            wii_linux.loader.auto_boot_partition=*)
                auto_boot_partition=${arg//wii_linux\.loader\.auto_boot_partition=//} ;;
            wii_linux.loader.auto_boot_timeout=*)
                auto_boot_timeout=${arg//wii_linux\.loader\.auto_boot_timeout=//} ;;
            *)
                warn "Unrecognized wii_linux.loader argument: $arg"
                sleep 5
                ;;
        esac
    fi
done

while true; do
    /bin/boot_menu
    ret=$?
    if [ $ret = 0 ] && [ -f /._bootdev ]; then
        # we got a selection, let's go!
        break
    elif [ $ret = 2 ]; then
        # want recovery shell, then restart
        recoveryShell false
        continue
    elif [ $ret = 3 ]; then
        # boot_menu detected problems, but user said to boot regardless...
        warn "boot_menu found problems with your selected distro, but told us to\ncarry on anyways..."
        break
    else # probably 1 for error, or something is horribly wrong
        error "internal error - boot_menu exited with code $ret... dropping you to recoveryShell"
        recoveryShell false
    fi
done
mkdir /target

bdev=$(cat /._bootdev)
echo "mounting $bdev"
if ! mount "$bdev" /target; then
    error "failed to mount $bdev to boot it, corrupted fs?  check for errors above"
    support
fi
if ! [ -x /target/sbin/init ]; then
    error "/sbin/init isn't executable / doesn't exist in your distro..."
    error "Cannot possibly continue booting."
    support
fi
success "About to switch_root in!"
umount /run
echo $?
mountpoint /
mount -t tmpfs none /
if ! mount -n -o move /run/boot_part /target/boot; then
    support
fi

mount -o remount,rw /target/boot

cat /._printk_restore > /proc/sys/kernel/printk
exec switch_root /target /sbin/init " " "$(cat /._cmdline)"
