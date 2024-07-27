#!/bin/ash
# shellcheck shell=dash

support() {
    echo "Please go to the Wii Linux Discord (found on the website at wii-linux.org)"
    echo "and ask for support there!"
    echo "== System info =="
    printf "/proc/version: "
    cat /proc/version
    echo "SD Card devices:"
    ls -l /dev/mmc* /dev/rvlsd*
    while true; do
        sleep 100
    done
}
