#!/bin/ash
# shellcheck shell=dash
# . /logging.sh


# EXIT CODES:
# 0 - all is good, check /._problems[suffix]
#     and /._distro[suffix] for the results
#
# 1 - fatal error attempting to check
#     info about the block device.
#     check /._problems[suffix] for what happened
#
# 2 - fatal internal error, likely caused by
#     faulty intput to the script.  Check
#     /._problems for what happened (no suffix)
#
# 3 - bdev is not a linux distro, no files created.
#
# 4 - non-fatal error (we can continue checking
#     AND the distro will still boot)
#     checking for info about the block device.
#     check /._problems[suffix] and /._distro[suffix] for info
#
# 5 - non-fatal error (we can continue checking),
#     but fatal (it will prevent the distro from booting)
#     checking for info about the block device.
#     check /._problems[suffix] and /._distro[suffix] for info
#

if [ "$1" = "" ] || ! [ -b "$1" ]; then
    echo "internal error - checkBdev got invalid input for what to check" > /._problems
    exit 2
fi

if [ "$2" = "" ]; then
    echo "internal error - checkBdev got invalid input for where to store results" > /._problems
    exit 2
fi

if [ "$3" = "" ]; then
    echo "internal error - checkBdev got invalid fs type" > /._problems
    exit 2
fi

if [ "$3" = "vfat" ] || [ "$3" = "swap" ] || [ "$3" = "exfat" ] || [ "$3" = "ntfs" ]; then
    # 0 chance of being a Linux install
    exit 3
fi

haveHadProblems=false
prob() {
    if [ "$haveHadProblems" = "true" ]; then
        echo "$1" >> "$problems"
        haveHadProblems=true
    else
        echo "$1" > "$problems"
    fi
    
}
exitCode=0
distro=/._distro$2
problems=/._problems$2
colors=/._colors$2

rm -f $distro $problems $colors
tmp=$(mktemp -p / -d tmp_checkBdev_XXXXXXXXXX)
if ! mount "$1" "$tmp" -t "$3" -o ro; then
    prob "failed to mount"
    exit 1
fi

# is it even a Linux (or Android) distro?
if ! [ -d "$tmp/usr" ] || ! { [ -d "$tmp/bin" ] || [ -L "$tmp/bin" ]; }; then
    # not Normal Linux.... is it Android?
    if ! [ -d "$tmp/system" ] || ! [ -d "$tmp/system/bin" ] || ! [ -d "$tmp/system/usr" ]; then
        # neither Linux nor Android, give up
        umount "$tmp"
        rmdir "$tmp"
        exit 3
    fi

    # it is Android!
    android=true
fi

if [ "$android" != "true" ]; then
    for f in etc/os-release usr/lib/os-release usr/share/os-release; do
        if [ -f "$tmp/$f" ] && . "$tmp/$f"; then
            # we found one!
            gotOSRel=true
            break
        fi
    done
    # just in case... are we an old copy of Debian?
    # we can give more info if so.
    if [ -f "$tmp/etc/debian_version" ]; then
        # yes!  but which...
        case "$(cat "$tmp/etc/debian_version")" in
            4.*) ID="debian-etch" ;;
            5.*) ID="debian-lenny" ;;
            8.*) ID="debian-jessie" ;;
            12.*) ID="debian-bookworm" ;;
            13.*) ID="debian-trixie" ;;
            *) ID="debian" ;;
        esac
        gotOSRel=true
    fi
    # these are not a fatal errors, but we
    # still can't know what distro it is...
    if [ "$gotOSRel" != "true" ]; then

        echo "Unknown" > "$distro"
        prob "no os-release file"
        exitCode=4
    elif [ "$ID" = "" ]; then
        echo "Unknown" > "$distro"
        prob "bad os-release file"
        exitCode=4
    else
        # we have ID from an os-release file!
        case $ID in
        arch)
            ppcDistro="\e[1;36mArchPOWER"
            ppcDistroHighlighted="\e[36mArchPOWER"
            otherDistro="\e[1;31mUnknown \e[36mArch Linux"
            otherDistroHighlighted="\e[31mUnknown \e[36mArch Linux"
            ppcDistroColorLen="7 5"
            otherDistroColorLen="12 10"
            ;;
        debian-trixie)
            ppcDistro="\e[1;31mDebian-Ports 13 (trixie) PPC"
            ppcDistroHighlighted="\e[31mDebian-Ports 13 (trixie) PPC"
            otherDistro="\e[1;31mUnknown Debian 13 (trixie)"
            otherDistroHighlighted="\e[31mUnknown Debian 13 (trixie)"
            ppcDistroColorLen="7 5"
            otherDistroColorLen="7 5"
            ;;
        debian-bookworm)
            ppcDistro="\e[1;31mDebian-Ports 12 (bookworm) PPC"
            ppcDistroHighlighted="\e[31mDebian-Ports 12 (bookworm) PPC"
            otherDistro="\e[1;31mUnknown Debian 12 (bookworm)"
            otherDistroHighlighted="\e[31mUnknown Debian 12 (bookworm)"
            ppcDistroColorLen="7 5"
            otherDistroColorLen="7 5"
            ;;
        debian-jessie)
            ppcDistro="\e[1;31mDebian 8 (jessie) PPC"
            ppcDistroHighlighted="\e[31mDebian 8 (jessie) PPC"
            otherDistro="\e[1;31mUnknown Debian 8 (jessie)"
            otherDistroHighlighted="\e[31mUnknown Debian 8 (jessie)"
            ppcDistroColorLen="7 5"
            otherDistroColorLen="7 5"
            ;;
        debian-lenny)
            ppcDistro="\e[1;31mDebian 5 (lenny) PPC"
            ppcDistroHighlighted="\e[31mDebian 5 (lenny) PPC"
            otherDistro="\e[1;31mUnknown Debian 5 (lenny)"
            otherDistroHighlighted="\e[31mUnknown Debian 5 (lenny)"
            ppcDistroColorLen="7 5"
            otherDistroColorLen="7 5"
            ;;
        debian-etch)
            ppcDistro="\e[1;31mDebian 4 (etch) PPC"
            ppcDistroHighlighted="\e[31mDebian 4 (etch) PPC"
            otherDistro="\e[1;31mUnknown Debian 4 (etch)"
            otherDistroHighlighted="\e[31mUnknown Debian 4 (etch)"
            ppcDistroColorLen="7 5"
            otherDistroColorLen="7 5"
            ;;
        debian)
            ppcDistro="\e[1;31mDebian PPC (Unknown version)"
            ppcDistroHighlighted="\e[31mDebian PPC (Unknown version)"
            otherDistro="\e[1;31mUnknown Debian"
            otherDistroHighlighted="\e[31mUnknown Debian"
            ppcDistroColorLen="7 5"
            otherDistroColorLen="7 5"
            ;;
        void)
            ppcDistro="\e[1;32mVoid PPC"
            ppcDistroHighlighted="\e[32mVoid PPC"
            otherDistro="\e[1;31mUnknown \e[32mVoid Linux"
            otherDistroHighlighted="\e[31mUnknown \e[32mVoid Linux"
            ppcDistroColorLen="7 5"
            otherDistroColorLen="12 10"
            ;;
        ubuntu)
            ppcDistro="\e[33mUbuntu PPC"
            ppcDistroHighlighted="\e[31mUbuntu PPC"
            otherDistro="\e[1;31mUnknown \e[22m\e[33mUbuntu"
            otherDistroHighlighted="\e[31mUnknown Ubuntu"
            ppcDistroColorLen="5 5"
            otherDistroColorLen="16 5"
            ;;
        *) ppcDistro="Unknown"; otherDistro="Unknown";;
        esac
    fi
else
    ppcDistro="\e[1;32mPPCDroid"
    ppcDistroHighlighted="\e[32mPPCDroid"
    otherDistro="\e[1;31mUnknown \e[32mAndroid"
    otherHighlightedDistro="\e[31mUnknown \e[32mAndroid"
    ppcDistroColorLen="7 5"
    otherDistroColorLen="12 10"
fi


# do we have /sbin/init (or /init if Android)?
if [ "$android" != "true" ]; then
    if ! [ -f "$tmp/sbin/init" ] && ! [ -L "$tmp/sbin/init" ]; then
        # we may have multiple problems be this point, seperate by line.
        prob "/sbin/init does not exist"
        exitCode=5
    else
        # Resolve symlink if it exists
        if [ -L "$tmp/sbin/init" ]; then
            link="$(readlink $tmp/sbin/init)"
            if [ "${link#/}" != "$link" ]; then
                # absolute symlink
                init="${tmp}${link}"
            else
                init="${tmp}/sbin/${link}"
            fi
        else
            # regular file
            init="${tmp}/sbin/init"
        fi
    fi
else
    init="$tmp/init"
fi

if ! [ -x "$init" ]; then
    prob "/sbin/init does exist but isn't executable"
    exitCode=5
fi


# are we sure we have a PPC distro?
if [ -f "$init" ] && ! file -L "$init" | grep 'PowerPC or cisco 4500,' | grep '32-bit MSB' > /dev/null; then
    prob '/sbin/init is not for PowerPC'
    notPPC=true
    exitCode=5
fi

if [ "$android" != "true" ]; then
    # do we have a libc?
    if ! find -L "$tmp/lib/" -maxdepth 1 -name 'libc.s*' -quit; then
        prob 'no libc detected'
        exitCode=5
    fi
fi

umount "$tmp"
# in case umount failed, this won't nuke the FS
rmdir "$tmp"
printf "$distroColor" > "$colors"
if [ "$notPPC" = "true" ]; then
    printf "$otherDistro\n" > "$distro"
    printf "$otherDistroHighlighted" >> "$distro"

    printf "$otherDistroColorLen" > "$colors"
else
    printf "$ppcDistro\n" > "$distro"
    printf "$ppcDistroHighlighted" >> "$distro"

    printf "$ppcDistroColorLen" > "$colors"
fi

if [ "$android" = "true" ]; then
    touch /._android$2
fi
exit $exitCode
