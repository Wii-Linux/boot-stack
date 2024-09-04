#!/bin/ash -e
# shellcheck shell=dash
# Wii Linux Just-In-Time loader.img setup script


logfile=/run/installer_log
datefmt() {
	date '+[%H:%M:%S]'
}
inst_log() {
	echo "$(datefmt) $*" >> $logfile
	echo "$(datefmt) $*" >> /dev/kmsg
}
inst_log_stdin() {
	while read -r l; do
		echo "$(datefmt) $l" >> $logfile
		echo "$(datefmt) $l" >> /dev/kmsg
	done
}
if [ "$1" = "installer-step2" ]; then
	# welcome back!  We just came back from the bottom of the script.
	# we've relocated ourselves to /installer_bootstrap, now let's clean up.
	#
	# Just in case our CWD is screwed, get out of there.
	cd /

	inst_log "jit_setup.sh step 2 begin"
	inst_log "unmounting /target"

	umount /target/run
	umount /target


	inst_log "unmounting /boot_part"
	umount /boot_part

	# we're now inside of an ext4 fs that lives on zram.
	# we should be good to migrate the new fs to /target,
	# do a little bit more cleanup, and gtfo, to let init take us over to
	# the loader.
	inst_log "moving /installer_boostrap mnt to /target"
	mount -n -o move /installer_bootstrap /target
	umount /installer_bootstrap
	rm -r /installer_bootstrap


	echo -ne "\rLoading... 95% done   "

	# set up symlinks and perms, since we're now in a real fs
	inst_log "setting up perms"
	cd /target
	./setup-fs.sh


	# fix shlibs
	inst_log "fixing libraries"
	rm -r lib
	ln -s usr/lib lib

	# nuke ourselves
	rm /run/jit_setup.sh

	# copy the log over
	inst_log "jit_setup.sh about to exit, copying log file over"
	mkdir -p /target/var/log
	cp $logfile /target/var/log/installer.log

	mkdir -p /target/mnt/boot
	mount "$2" "/target/mnt/boot"

	echo -ne "\rLoading... 100% done   "

	# Exit to not only release our lock on /target (our CWD), but also
	# let init know it's fine to continue booting in /target.
	# if everything worked out successfully, we should continue in the
	# the installer's init.sh.  See ya on the other side!
	exit 0
fi

# Sanity check!  Are we getting called via the initial loader?
if ! [ -d /target ] || [ -f /.rw-loader-img ]; then
	. /logging.sh
	error "Not getting called via initial loader, aborting!"
	warn  "Don't call scripts that you don't understand!"
	exit 1
fi


echo -n "" > $logfile
inst_log "jit_setup.sh step 1 begin"
inst_log "setting up zram"

# 100MB size, just a guess that it should be fine
echo 104857600 > /sys/block/zram0/disksize

# make an ext4 fs on the zram dev and mount it, should now have plenty of
# space to store the new rootfs.
# XXX: need to chroot here since the installer uses glibc, while the
# in-kernel ramfs uses uclibc.  Can't exec busybox directly, so need to
# run it in the context of the new root so it can pull in glibc

inst_log "setting up ext4 filesystem on it"
export LD_LIBRARY_PATH=/target/usr/lib/
# XXX: hack, force shared libs to exist temporarily
mount -t tmpfs tmpfs /target/lib
cd /target/usr/lib
cp libc* ld.so.1 libblkid* libuuid* libe2p* libext2fs* libcom* ../../lib
cd ../../lib
ln -s libext2fs.so.2.4 libext2fs.so.2
ln -s libcom_err.so.2.1 libcom_err.so.2
ln -s libblkid.so.1.1.0 libblkid.so.1
ln -s libuuid.so.1.3.0 libuuid.so.1
ln -s libe2p.so.2.3 libe2p.so.2

# no need for a journal when in RAM, it just slows it down
# XXX: Kernel 3.15 is so damn old that it doesn't support the
# "metadata_csum_seed" feature.
LD_LIBRARY_PATH=/target/lib /target/usr/lib/ld.so.1 /target/usr/sbin/mke2fs -t ext4 -O ^has_journal,^metadata_csum_seed /dev/zram0 2>&1 | inst_log_stdin
cd /
rm -rf /target/lib/*
umount /target/lib
unset LD_LIBRARY_PATH dest

# let's copy everything out to fs
inst_log "Mounting & copying everything to fs"

mkdir /installer_bootstrap
mount /dev/zram0 /installer_bootstrap -o discard

# log any errors
max=$(ls /target /target/usr | wc -l)
max=$((max + 1))
cur=0

for f in /target/*; do
	percent=$(((cur * 100) / max))
	if [ $percent -gt 90 ]; then percent=90; fi

	cur=$((cur + 1))

	echo -ne "\rLoading... $percent% done  "
	inst_log "copying $f"
	cp -ar "$f" /installer_bootstrap/ 2>&1 | inst_log_stdin
done

for f in /target/usr/*; do
	percent=$(((cur * 100) / max))
	if [ $percent -gt 90 ]; then percent=90; fi

	cur=$((cur + 1))

	echo -ne "\rLoading... $percent% done  "
	inst_log "copying $f"
	cp -ar "$f" /installer_bootstrap/usr/ 2>&1 | inst_log_stdin
done
cp -a /target/jit_setup.sh /run/

echo "Done copying everything to fs"

# get out of here so we release the file handle for jit_setup.sh under /target
# however, pass an arg so we know to pick up where we left off
inst_log "Exec step2"
exec /run/jit_setup.sh installer-step2 "$boot_part"
