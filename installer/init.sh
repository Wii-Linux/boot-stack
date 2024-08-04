#!/bin/busybox ash
# shellcheck shell=bash
if ! [ -c /dev/tty0 ]; then
	mount -t devtmpfs dev /dev
	mount -t sysfs sys /sys
	mount -t proc proc /proc
	mount -t tmpfs run /run
fi

if ! [ -f /proc/sysrq-trigger ]; then
	mount -t proc proc /proc
fi
# still nothing?  probably failed
if ! [ -c /dev/tty0 ]; then
	mknod /dev/tty0    c 4 0
	mknod /dev/tty     c 5 0
	mknod /dev/console c 5 1
	mknod /dev/null    c 1 3
fi

exec < /dev/console > /dev/console 2> /dev/console

reset
echo "Wii Linux installer init v0.0.1"
free -h

. /logging.sh
. /support.sh
. /util.sh

installer_crash_dump() {
	echo '===== Wii Linux Installer Crash ====='
	echo "Date according to Linux: $(date)"
	echo "Installer Error Code: $1"
	echo
	echo '==== /proc/cpuinfo start ===='
	cat /proc/cpuinfo
	echo '====  /proc/cpuinfo end  ===='
	echo
	echo 'Memory info:'
	free -h
	echo
	echo '==== Disk Info start ===='
	echo '== /proc/mounts start =='
	cat /proc/mounts
	echo '==  /proc/mounts end  =='
	echo '== df -h start =='
	df -h
	echo '==  df -h end  =='
	echo '====  Disk Info end  ===='
	echo
	echo '==== Kernel Log messages start ===='
	dmesg
	echo '====  Kernel Log messages end  ===='
	echo
	echo '==== Installer Log messages start ===='
	cat /var/log/installer.log
	echo '====  Installer Log messages end  ===='
}

/usr/bin/wiilinux-installer
ret=$?
if [ $ret = 0 ]; then
	# we're installed and ready to go
	# unmount everything
	umount -Rq /mnt/root
	umount -Rq /mnt/boot

	# just in case
	grep '/mnt' /proc/mounts | while read l; do
		i=0
		for f in $l; do
			i=$((i + 1))
			if [ $i = 2 ]; then
				umount $f
				break
			fi
		done
	done

	# sync filesystems
	sync

	# reboot
	echo b > /proc/sysrq-trigger
else
	# failed
	# reset the terminal, get out of TUI state
	reset
	error "Oh no!  It appears as though the installer has crashed!"
	echo -e "The error code was \e[1;31m$ret\e[0m"

	if mountpoint /mnt/boot; then
		if ! ( installer_crash_dump "$ret" > /mnt/boot/installer_crash.log 2>&1; umount /mnt/boot; sync; ); then
			error "Failed to save crash dump to disk, proceeding with manual crash dump."
		else
			success "Successfully saved crash dump to disk.  Please upload \"installer_crash.log\""
			success "to the Wii Linux discord server for support."
			echo -n "Press enter to power down."
			read dummy
			echo o > /proc/sysrq-trigger
		fi
	else
		error "Failed to save crash dump to disk, proceeding with manual crash dump."
	fi

	success "To get support, please follow the steps below carefully."
	echo "Please find some way to get a high quality recording, or multiple pictures, of"
	echo "your console.  You will need to press space to advance the text on the screen."
	echo "When the recording has started, or you are ready to take pictures, please"
	echo -n "press enter to continue."
	read -r dummy

	installer_crash_dump $ret 2>&1 | less -E

	echo -n "Installer crash dump completed.  Please enter to power down."
	read -r dummy
	echo o > /proc/sysrq-trigger

	sleep 5
	echo "Powering down the system failed."
	sleep inf
fi
