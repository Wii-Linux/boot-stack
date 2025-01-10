#!/bin/ash -e
# shellcheck shell=dash
# Wii Linux Just-In-Time loader.img setup script

# Sanity check!  Are we getting called via the initial loader?
if ! [ -d /target ] || [ -f /.rw-loader-img ]; then
    . /logging.sh
    error "Not getting called via initial loader, aborting!"
    warn  "Don't call scripts that you don't understand!"
    exit 1
fi

mount -t tmpfs run /target/run
mkdir -p /target/run/overlay_work /target/run/overlay_upper
# mount -t tmpfs -o size=50% tmpfs /target/run/overlay_work
mkdir /target/run/sqfs
mount -n -o move /target /target/run/sqfs
mount -t overlay -o lowerdir=/target/run/sqfs,upperdir=/target/run/overlay_upper,workdir=/target/run/overlay_work none /target

# ready?  let init switch_root in
