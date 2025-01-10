#!/bin/ash
# shellcheck shell=bash
if ! [ -c /dev/tty0 ]; then
	mount -t devtmpfs dev /dev
	mount -t sysfs sys /sys
	mount -t proc proc /proc
fi
# still nothing?  probably failed
if ! [ -c /dev/tty0 ]; then
	mknod /dev/tty0	c 4 0
	mknod /dev/tty	 c 5 0
	mknod /dev/console c 5 1
	mknod /dev/null	c 1 3
fi

exec < /dev/console > /dev/console 2> /dev/console

reset
echo "Wii Linux loader.img init v0.4.0"

cat /proc/sys/kernel/printk > /._printk_restore
printf "1\t4\t1\t7" > /proc/sys/kernel/printk

echo "loader.img starting" > /dev/kmsg

# nuke jit_setup.sh so the user can't screw up their initramfs
rm /jit_setup.sh

. /logging.sh
. /support.sh
. /network.sh
. /util.sh

printf "1\t4\t1\t7" > /proc/sys/kernel/printk

# Filesystem drivers
modprobe ext4

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

if grep -q -- '-ppcdroid' /proc/version; then
	warn "PPCDroid-only kernel detected.  Be warned, this is not stable!"
	sleep 2
	ppcdroid_only=true
	bootmenu_args="--ppcdroid"
fi

while true; do
	if ! [ -f /run/boot_part/wiilinux/migrate.mii ]; then
		break
	fi

	mount -o remount,rw /run/boot_part

	clear
	echo "ENTERING MIGRATION ASSISTANT"
	migratePart="$(cat /run/boot_part/wiilinux/migrate.mii)"

	if ! [ -b "$migratePart" ]; then
		error "$migratePart does not exist for migration!"
		recoveryShell false
	fi

	if ! mount -o rw "$migratePart" /mnt; then
		error "failed to mount $migratePart for migration!"
		support
	fi

	if ! [ -d "/mnt/.wii-linux-migrate" ] || ! [ -d "/mnt/usr/bin" ]; then
		error "Something is very wrong with this rootfs, refusing to migrate."
		support
	fi

	echo "Now DELETING old rootfs!"

	ls -1A /mnt | grep -v '.wii-linux-migrate' | while read -r l; do
		echo "now deleting /$l..."
		rm -rf "/mnt/$l"
	done

	echo "old rootfs DELETED!"
	echo "moving new rootfs into place!"
	ls -1A /mnt/.wii-linux-migrate/new_rootfs | while read -r l; do
		echo "moving /$l"
		mv "/mnt/.wii-linux-migrate/new_rootfs/$l" "/mnt/$l"
	done

	echo "done!"
	echo "deleting temporary folder"
	rmdir /mnt/.wii-linux-migrate

	echo "unmounting"
	umount /mnt

	echo "deleting marker"
	rm -f /run/boot_part/wiilinux/migrate.mii
	if [ $? != 0 ]; then
		error "MIGRATION FAILED - DO __NOT__ REBOOT UNTIL GETTING HELP"
		support
	fi
	success "MIGRATION COMPLETE"
	sleep 5
done


while true; do
	/bin/boot_menu "$bootmenu_args"
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

bdev=$(cat /._bootdev 2>/dev/null)
if [ "$bdev" = "" ]; then
	error "internal error - bootMenu returned empty bdev"
	support
fi

android=$(cat /._isAndroid 2>/dev/null)

echo "mounting $bdev"
if ! mount "$bdev" /target; then
	error "failed to mount $bdev to boot it, corrupted fs?  check for errors above"
	support
fi
#if ! [ -x /target/sbin/init ]; then
#	error "/sbin/init isn't executable / doesn't exist in your distro..."
#	error "Cannot possibly continue booting."
#	support
#fi

echo "fixing up filesystems"
mount -t tmpfs none /

if [ "$android" != "true" ]; then
	if [ "$ppcdroid_only" = "true" ]; then
		error "Trying to boot a Linux distro on an Android kernel!!!"
		error "This WILL backfire horribly, but letting you try anyways..."
		sleep 5
	fi
	if ! mount -n -o move /run/boot_part /target/boot; then
		support
	fi
	mount -o remount,rw /target/boot

	# XXX: systemd wants more space in /run than it actually gets by default.
	# Fix this here by giving it just a little bit over what it wants (16MB).
	# It's only 2MB more than the default.
	mount -t tmpfs run /target/run -o size=20M
fi


cat /._printk_restore > /proc/sys/kernel/printk
success "About to switch_root in!"

if [ "$android" != "true" ]; then
	# XXX: switch_root is dumb and requires a /init to do... something, with.
	# create it here in RAM just so that it's happy
	touch /init
	exec switch_root '/target' '/sbin/init'
else
	exec switch_root '/target' '/init'
fi
