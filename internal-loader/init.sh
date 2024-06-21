#!/bin/ash
# shellcheck shell=bash
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

exec > /dev/console 2>&1

printf "\033[6;1H\033[J"
echo "Wii Linux Initrd Loader v0.0.1"

# modprobe gcn-sd
modprobe mmc_block
modprobe mmc_core
modprobe sdhci-of-hlwd
modprobe vfat
modprobe squashfs

. /logging.sh
. /support.sh

# global variables
auto_boot_partition=""
sd_detect_timeout=500

# parse cmdline
for arg in $(cat /proc/cmdline); do
    if echo "$arg" | grep 'wii_linux.loader'; then
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

sec=$(($sd_detect_timeout / 100))
echo "Waiting ${sec}s for SD Card to show up"

i=0
num=0
while [ $i != $(($sd_detect_timeout / 5)) ]; do
    if ls /dev/mmc* >/dev/null 2>&1; then
        num=$(ls -l /dev/mmc* | wc -l)
        # account for base device
        num=$(($num - 1))
        break
    fi

    i=$(($i + 1))
    usleep 50000
done

if [ $num = 0 ]; then
    error "Waited $sec seconds, but an SD Card with partitions did not show up!"
    support
fi

success "Found SD Card with $num partitions."
parts=$(ls /dev/mmc*)

mkdir /boot_part /target -p

case $(cat /proc/version) in
    "Linux version 4.5"*) ver=45 ;;
    *) error "Unknown kernel version, Techflash messed up!"; support ;;
esac

if [ "$auto_boot_partition" != "" ] && ! [ -b "$auto_boot_partition" ]; then
    warn "Specified auto_boot_partition does not exist!  Fix your boot config!!"
    warn "*sigh*... trying to autodetect a boot partition so you can still boot..."

elif [ -b "$auto_boot_partition" ]; then
    echo "Found manually specified partition $auto_boot_partition!"
    if mount $auto_boot_partition /boot_part -t vfat -o ro && [ -f /boot_part/gumboot/loader$ver.img ]; then
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
        if [ "$part" = "/dev/mmcblk0" ]; then
            # skip raw block dev
            continue
        fi
        echo "Trying partition $part..."
        if mount $part /boot_part -t vfat -o ro && [ -f /boot_part/gumboot/loader$ver.img ]; then
            boot_part=$part
            break
        fi
    done
fi

if [ "$boot_part" = "" ]; then
    error "While there is an SD Card in your Wii, nothing mountable contains loader$ver.img!"
    error "Your Wii Linux install is unbootable until you fix this."
    error "Bad system update perhaps?"
    support
fi

success "Found $boot_part with loader$ver.img!  Pivoting..."
if ! mount /boot_part/gumboot/loader$ver.img /target -t squashfs -o ro; then
    error "Uh oh, found loader$ver.img, but failed to mount it...."
    echo "This is likely the result of an interrupted update mangling it beyond usability."
    umount /boot_part
    support
fi

if ! [ -x /target/sbin/init ]; then
    error "Uh oh, found and mounted loader$ver.img, but /sbin/init either doesn't"
    error "exist there, or isn't executable!"
    echo "This is likely the result of an interrupted update mangling it beyond usability."
    echo "Please include the following debug info:"
    ls -l /target/sbin/init
    ls -l /target/linuxrc
    umount /target
    umount /boot_part
    support
fi

# mkdir /target_inram
# mount -t tmpfs tmpfs /target_inram
# cp -ar /target/* /target_inram/
# umount /target
# exec /bin/busybox switch_root /target_inram /sbin/init
/target/jit_setup.sh
err=$?
if [ $err != 0 ]; then
    error "Uh oh!  Just-in-Time setup for loader$ver.img failed with error code $err!"
    umount /target
    umount /boot_part
    echo "Please include any errors that occured above"
    support
fi
mkdir /target/run/boot_part
if ! mount -n -o move /boot_part /target/run/boot_part; then
    error "failed to move /boot_part"
    support
fi
exec /bin/busybox switch_root /target /sbin/init
error "switch_root failed..."
support