#!/bin/ash
# shellcheck shell=bash



# Wii Linux Initrd Loader init script
#
# XXX: Contains garbage hacks to be able to load the installer despite
# several kernel bugs making that theoretically impossible.  They need to be
# worked around in incredibly unconventional and annoying ways.
#
# They're marked with "XXX: installer hack #[number]"
#
# The most egregious of which being the following 2:
#   - Load the entire thing, uncompressed, via FAT32.
#     Copying from a squashfs just doesn't work due to kernel bugs.
#     The issue lies in the SD Card driver, not an issue with sqfs itself.
#     It's something about waiting on buffers, that just never get filled iirc
#
#   - Since FAT32 doesn't have permissions support, generate, at build time, a
#     script to apply the correct permissions.  Copy to RAM, and apply them
#     at runtime (via jit_loader.sh), in RAM, where we can have permissions.


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

exec > /dev/console 2> /dev/console

echo -en "\033[6;1H\033[J"
echo "Wii Linux Initrd Loader v0.2.0"

echo "initrd starting" > /dev/kmsg
. /logging.sh

if cat /proc/version | grep -q '\-wii-ios'; then
	is_ios_kernel=true
	warn "Running on experimental IOS kernel!  Beware of bugs!"
else
	# SD
	# modprobe gcn-sd
	modprobe mmc_block
	modprobe mmc_core
	modprobe sdhci-of-hlwd


	# FS
	modprobe vfat
	modprobe squashfs
	echo "modules loaded" > /dev/kmsg
fi

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
    "Linux version 2.6"*) ver=installer ;;
    "Linux version 3.15.10"*) ver=installer ;;
    "Linux version 4.4.302-cip80-wii-ios"*) ver=v4_4_302;;
    "Linux version 4.5"*) ver=v4_5_0;;
    "Linux version 4.20"*) ver=v4_20_0;;
    "Linux version 6.6"*) ver=v6_6_0;;
    *) error "Unknown kernel version, Techflash messed up!"; support ;;
esac

if [ "$is_ios_kernel" = "true" ] && [ "${#ver}" -lt "8" ]; then
	ver="${ver}i"
fi

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
	
	# XXX: Installer hack #1 - check for raw dir in case of installer
        if mount "$part" /boot_part -t vfat -o ro && { [ -f "/boot_part/wiilinux/$ver.ldr" ] || [ -d "/boot_part/wiilinux/$ver" ]; }; then
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

# XXX: Installer hack #2 - skip mounting if installer
if [ "$ver" = "installer" ]; then
	mount --bind /boot_part/wiilinux/installer /target
else
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
fi

# XXX: Installer hack #3 - since we can't have symlinks on FAT32, /sbin/init,
# actually won't exist yet, so this check will always fail.
# It'll be generated below when we run jit_setup.sh, which will relocate
# everything to a tmpfs and create all symlinks and perms at runtime,
# however, at this point, /sbin/init just won't exist.

if [ "$ver" != "installer" ]; then
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
fi

# XXX: Installer hack #4 - we can't rely on overlayfs to exist.  Manually mount /run.
if [ "$ver" = "installer" ]; then
	mount -n -o move /run /target/run
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

if [ "$ver" != "installer" ]; then
	echo "making dir" > /dev/kmsg
	mkdir /target/run/boot_part
	echo "moving mount" > /dev/kmsg
	if ! mount -n -o move /boot_part /target/run/boot_part && umount /boot_part && rmdir /boot_part; then
	    error "failed to move /boot_part"
	    support
	fi
fi

echo "about to exec" > /dev/kmsg
exec /bin/busybox switch_root /target /sbin/init

echo "exec failed" > /dev/kmsg
error "switch_root failed..."
support
