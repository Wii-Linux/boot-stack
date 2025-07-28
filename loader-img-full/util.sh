#!/bin/ash
# shellcheck shell=sh

recoveryShell() {
    echo ""
    warn '=== YOU ARE NOW ENTERING A RECOVERY SHELL! ==='
    printf '\033[1;33mIF YOU DO NOT KNOW WHAT YOU ARE DOING, PLEASE CONTACT SUPPORT!\r\n'
    printf '\033[32mYou may contact support at the Discord Server linked at \033[4;36mhttps://wii-linux.org\r\n'
    printf "\033[0mYou'll probably want to run the \"\033[1;36msupport\033[0m\" command, and follow it's steps.\r\n"
    printf '\r\n'
    printf "If you do know what you're doing, this is a Busybox ash shell, and\r\n"
    printf "there's a few basic utilities (busybox) lurking around in here.\r\n"
    printf "\033[1;33mIf that was gibberish to you, I suggest following the topmost instructions!\033[0m\r\n"
    printf "If you do understand what those are, then have at it, and send some patches!\r\n"

    # give the user a fancy-ish shell
    export PS1='[\u@wii-linux \W]\$ '

    # last minute write out /etc/passwd so bash doesn't complain that
    # the user has no name
    mkdir -p /etc
    echo 'root:x:0:0::/root:/bin/bash' > /etc/passwd
    
    # do we want to continue after this?
    if [ "$1" = "false" ]; then
        /bin/ash
    else
        exec /bin/ash
    fi
}
