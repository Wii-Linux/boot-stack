#!/bin/ash
# shellcheck shell=bash



# Wii Linux Initrd Loader init script

mount -t devtmpfs dev /dev
mount -t sysfs sys /sys
mount -t proc proc /proc
mount -t run run /run

# still nothing?  probably failed
if ! [ -c /dev/tty0 ]; then
    mknod /dev/tty0    c 4 0
    mknod /dev/tty     c 5 0
    mknod /dev/console c 5 1
    mknod /dev/null    c 1 3
fi

if ! [ -c /dev/kmsg ]; then
    mknod /dev/kmsg    c 1 11
fi

exec > /dev/console 2> /dev/console

echo -en "\033[6;1H\033[J"
echo "Wii Linux Initrd Loader v0.2.3"

echo "initrd starting" > /dev/kmsg
. /logging.sh
. /support.sh

# global variables
auto_boot_partition=""
sd_detect_timeout=500

# parse cmdline
for arg in $(cat /proc/cmdline); do
    if echo "$arg" | grep -q 'wii_linux.loader'; then
        # parse it
        case "$arg" in
            wii_linux.init.auto_boot_partition=*)
                auto_boot_partition=${arg//wii_linux\.init\.auto_boot_partition=//} ;;
            wii_linux.init.sd_detect_timeout=*)
                sd_detect_timeout=${arg//wii_linux\.init\.sd_boot_timeout=//} ;;
            *)
                warn "Unrecognized wii_linux.loader argument: $arg"
                sleep 5
                ;;
        esac
    fi
done
echo "parsed args" > /dev/kmsg

sec=$((sd_detect_timeout / 100))
echo "Waiting ${sec}s for SD Card to show up"

i=0
num=0
while [ $i != $((sd_detect_timeout / 5)) ]; do
    if ls /dev/mmc* >/dev/null 2>&1; then
        card="mmc"
        num=$(ls -l /dev/mmc* | wc -l)

        # account for base device
        num=$((num - 1))
        break
    fi
    if ls /dev/rvlsd* >/dev/null 2>&1; then
        card="rvlsd"
        num=$(ls -l /dev/rvlsd* | wc -l)

        # account for base device
        num=$((num - 1))
        break
    fi

    i=$((i + 1))
    usleep 50000
done

echo -n "waited for devs... " > /dev/kmsg
if [ $num = 0 ]; then
    error "Waited $sec seconds, but an SD Card with partitions did not show up!"
    echo "fail" > /dev/kmsg
    support
fi
echo "success" > /dev/kmsg

success "Found SD Card with $num partitions."
parts=$(ls "/dev/$card"*)

mkdir /boot_part /target -p

case $(cat /proc/version) in
    "Linux version 4.5.0-wii-ppcdroid"*) ver=v4_5_0a;;
    "Linux version 4.5"*) ver=v4_5_0;;
    "Linux version 4.6"*) ver=v4_6_0;;
    "Linux version 4.9.337"*) ver=v4_9_337;;
    "Linux version 4.9"*) ver=v4_9_0;;
    "Linux version 4.14.336"*) ver=v4_14336;;
    "Linux version 4.14.275"*) ver=v4_14275;;
    "Linux version 4.14"*) ver=v4_14_0;;
    "Linux version 4.19.325"*) ver=v4_19325;;
    "Linux version 4.19"*) ver=v4_19_0;;
    "Linux version 4.20"*) ver=v4_20_0;;
    "Linux version 5.4"*) ver=v5_4_0;;
    "Linux version 6.6"*) ver=v6_6_0;;
    *) error "Unknown kernel version, Techflash messed up!"; support ;;
esac

if [ "$auto_boot_partition" != "" ] && ! [ -b "$auto_boot_partition" ]; then
    warn "Specified auto_boot_partition does not exist!  Fix your boot config!!"
    warn "*sigh*... trying to autodetect a boot partition so you can still boot..."

elif [ -b "$auto_boot_partition" ]; then
    echo "Found manually specified partition $auto_boot_partition!"
    if mount "$auto_boot_partition" /boot_part -t vfat -o ro && [ -f "/boot_part/wiilinux/$ver.ldr" ]; then
        boot_part=$auto_boot_partition
        umount /boot_part
    else
        warn "Manually specified auto_boot_partition is unmountable"
        warn "or doesn't contain a loader$ver.img!  Fix your boot config!!"
        warn "*sigh*... trying to autodetect a boot partition so you can still boot..."
    fi
fi

if [ "$boot_part" = "" ]; then
    for part in $parts; do
        if [ "$part" = "/dev/mmcblk0" ] || [ "$part" = "/dev/rvlsda" ]; then
            # skip raw block dev
            continue
        fi
        echo "Trying partition $part..."

        if mount "$part" /boot_part -t vfat -o ro && [ -f "/boot_part/wiilinux/$ver.ldr" ]; then
            boot_part=$part
            break
        fi
    done
fi

if [ "$boot_part" = "" ]; then
    error "While there is an SD Card in your Wii, nothing mountable contains $ver.ldr!"
    error "Your Wii Linux install is unbootable until you fix this."
    error "Bad system update perhaps?"
    support
fi

name=/boot_part/wiilinux/$ver.ldr
fname=$ver.ldr

success "Found $boot_part with $fname!  Pivoting..."
echo "mounting squashfs" > /dev/kmsg
if ! mount "$name" /target -t squashfs -o ro; then
    error "Uh oh, found $fname, but failed to mount it...."
    echo "This is likely the result of an interrupted update mangling it beyond usability."
    umount /boot_part
    support
fi
echo "checking /sbin/init" > /dev/kmsg
if ! [ -x /target/sbin/init ]; then
    error "Uh oh, found and mounted $fname, but /sbin/init either doesn't"
    error "exist there, or isn't executable!"
    echo "This is likely the result of an interrupted update mangling it beyond usability."
    echo "Please include the following debug info:"
    ls -l /target/sbin/init
    ls -l /target/linuxrc
    umount /target
    umount /boot_part
    support
fi

echo "running jit setup" > /dev/kmsg
export boot_part
/target/jit_setup.sh
err=$?
echo "exit with ret=$err" > /dev/kmsg
if [ $err != 0 ]; then
    error "Uh oh!  Just-in-Time setup for $ver.ldr failed with error code $err!"
    umount /target
    umount /boot_part
    echo "Please include any errors that occured above"
    support
fi

echo "making dir" > /dev/kmsg
mkdir /target/run/boot_part
echo "moving mount" > /dev/kmsg
if ! mount -n -o move /boot_part /target/run/boot_part && umount /boot_part && rmdir /boot_part; then
    error "failed to move /boot_part"
    support
fi

echo "about to exec" > /dev/kmsg
exec /bin/busybox switch_root /target /sbin/init

echo "exec failed" > /dev/kmsg
error "switch_root failed..."
support
