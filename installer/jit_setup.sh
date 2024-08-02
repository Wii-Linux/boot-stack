#!/bin/ash -e
# shellcheck shell=dash
# Wii Linux Just-In-Time loader.img setup script

if [ "$1" = "installer-step2" ]; then
	# welcome back!  We just came back from the bottom of the script.
	# we've relocated ourselves to /installer_bootstrap, now let's clean up.
	#
	# Just in case our CWD is screwed, get out of there.
	cd /
	umount /target

	# we're now inside of an ext4 fs that lives on zram.
	# we should be good to migrate the new fs to /target,
	# do a little bit more cleanup, and gtfo, to let init take us over to
	# the loader.
	mount -n -o move /installer_bootstrap /target
	rm -r /installer_bootstrap

	# set up symlinks and perms, since we're now in a real fs
	cd /target
	./setup-fs.sh

	# nuke ourselves
	rm /run/jit_setup.sh

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

# We are clear for takeoff, go setup zram, make an FS on it, and chuck the installer bootstrap over there, since it needs to restart even during SD Card partitioning.
#insmod /target/lib/modules/$(/target/bin/uname -r)/kernel/drivers/block/zram/zram.ko

# loaded, set it up
# XXX: should really check, but this will always return 0, as the module was JUST loaded.
#cat /sys/class/zram-control/hot_add

# 100MB size, just a guess that it should be fine
echo 104857600 > /sys/block/zram0/disksize

# make swap on the zram dev and turn it on, we should now have plenty of space
# to store the new rootfs
# XXX: need to chroot here since the installer uses glibc, while the
# in-kernel ramfs uses uclibc.  Can't exec busybox directly, so need to
# run it in the context of the new root so it can pull in glibc

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
mkdir -p /target/lib/modules/$(uname -r)/kernel/fs
cd /target/usr/lib/modules/$(uname -r)/
dest="/target/lib/modules/$(uname -r)"
cp modules.* $dest/
cp -r kernel/fs/ext4 $dest/kernel/fs/ext4
cp -r kernel/fs/jbd2 $dest/kernel/fs/jbd2
cp kernel/fs/mbcache.ko $dest/kernel/fs/
# no need for a journal when in RAM, it just slows it down
# XXX: Kernel 3.15 is so damn old that it doesn't support the
# "metadata_csum_seed" feature.
LD_LIBRARY_PATH=/target/lib /target/usr/lib/ld.so.1 /target/usr/sbin/mke2fs -t ext4 -O ^has_journal,^metadata_csum_seed /dev/zram0
chroot /target /usr/bin/busybox modprobe ext4
rm -rf /target/lib/*
umount /target/lib
unset LD_LIBRARY_PATH dest

# let's copy everything out to fs
mkdir /installer_bootstrap
mount /dev/zram0 /installer_bootstrap

echo "Copying everything to fs"

# everything but /usr
files=$(ls /target | grep -v '^usr$')
for file in $files; do
    cp -avr /target/$file /installer_bootstrap/ | while read l; do echo $l > /dev/kmsg; done
done

# everything in /usr except for lib
files=$(ls /target/usr | grep -v '^lib$')
mkdir -p /installer_bootstrap/usr
for file in $files; do
    cp -avr /target/usr/$file /installer_bootstrap/usr/ | while read l; do echo $l > /dev/kmsg; done
done

# everything in /usr/lib except for modules
files=$(ls /target/usr/lib | grep -v '^modules$')
mkdir -p /installer_bootstrap/usr/lib
for file in $files; do
    cp -avr /target/usr/lib/$file /installer_bootstrap/usr/lib/ | while read l; do echo $l > /dev/kmsg; done
done

mkdir -p /installer_bootstrap/usr/lib/modules/$(uname -r)

# everything in /usr/lib/modules/$(uname -r) except for kernel
files=$(ls /target/usr/lib/modules/$(uname -r) | grep -v '^kernel$')
mkdir -p /installer_bootstrap/usr/lib/modules/$(uname -r)
for file in $files; do
    cp -avr /target/usr/lib/modules/$(uname -r)/$file /installer_bootstrap/usr/lib/modules/$(uname -r)/ | while read l; do echo $l > /dev/kmsg; done
done

# everything in /usr/lib/modules/$(uname -r)/kernel except for fs
files=$(ls /target/usr/lib/modules/$(uname -r)/kernel | grep -v '^fs$')
mkdir -p /installer_bootstrap/usr/lib/modules/$(uname -r)/kernel
for file in $files; do
    cp -avr /target/usr/lib/modules/$(uname -r)/kernel/$file /installer_bootstrap/usr/lib/modules/$(uname -r)/kernel/ | while read l; do echo $l > /dev/kmsg; done
done


cp /target/jit_setup.sh /run/

exec > /dev/console

echo "Done copying everything to fs"

# get out of here so we release the file handle for jit_setup.sh under /target
# however, pass an arg so we know to pick up where we left off
echo "Exec start"
exec bash /run/jit_setup.sh installer-step2
