#!/bin/ash
# shellcheck shell=sh


# bring up networking should the user request it
net_up() {
    echo "Would you like to bring up WiFi?"
    # XXX: Not supported yet
    case "$input" in
        y) up=1 ;;
        yes) up=1 ;; 
        Y) up=1 ;;
        YES) up=1 ;;
        n) up=0 ;;
        no) up=0 ;;
        N) up=0 ;;
        NO) up=0 ;;
        *) up="?" ;;
    esac

    if [ "$up" = "?" ]; then
        warn "Unknown answer, assuming no.  Run this again to try again."
    elif [ "$up" = "1" ]; then
        modprobe b43
        echo "not supported"
    elif [ "$up" = "0" ]; then
        # XXX: bring up ethernet instead
        echo "should bring up ethernet here"
    fi
}