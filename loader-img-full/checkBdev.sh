#!/bin/ash
# shellcheck shell=dash
# . /logging.sh


# EXIT CODES:
# 0   - all is good, check /._problems[suffix]
#       and /._distro[suffix] for the results
#
# 101 - fatal error attempting to check
#       info about the block device.
#       check /._problems[suffix] for what happened
#
# 102 - fatal internal error, likely caused by
#       faulty intput to the script.  Check
#       /._problems for what happened (no suffix)
#
# 103 - bdev is not a linux distro, no files created.
#
# 104 - non-fatal error (we can continue checking
#       AND the distro will still boot)
#       checking for info about the block device.
#       check /._problems[suffix] and /._distro[suffix] for info
#
# 105 - non-fatal error (we can continue checking),
#       but fatal (it will prevent the distro from booting)
#       checking for info about the block device.
#       check /._problems[suffix] and /._distro[suffix] for info
#

if [ "$1" = "" ] || ! [ -b "$1" ]; then
    echo "internal error - checkBdev got invalid input for what to check" > /._problems
    exit 102
fi

if [ "$2" = "" ]; then
    echo "internal error - checkBdev got invalid input for where to store results" > /._problems
    exit 102
fi

case "$3" in
    "")
        echo "internal error - checkBdev got invalid fs type" > /._problems
        exit 102 ;;
    vfat|swap|exfat|ntfs|ufs)
        # 0 chance of being a Linux install
        exit 103 ;;
esac

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
    exit 101
fi

# is it even a Linux (or Android) distro?
if ! [ -d "$tmp/usr" ] || ! { [ -d "$tmp/lib" ] || [ -L "$tmp/lib" ]; }; then
    # not Normal Linux.... is it Android?
    if [ -d "$tmp/system" ] && [ -d "$tmp/system/bin" ] && [ -d "$tmp/system/usr" ]; then
        # it is Android!
        android=true
    # neither normal Linux, nor Android.... Batocera?
    elif [ -f "$tmp/boot/batocera" ]; then
        # yes!
        batoceraSquashfs=true

        # set up vars because none of the other distro detection can handle this
        notPPC=false
        ppcDistro="\e[33mBatocera"
        ppcDistroHighlighted="\e[31mBatocera"
        ppcDistroColorLen="5 5"
   else
        # neither Linux nor Android nor Batocera, give up
        umount "$tmp"
        rmdir "$tmp"
        exit 103
    fi
fi

if [ "$android" != "true" ] && [ "$batoceraSquashfs" != "true" ]; then
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
        read -r ver < "$tmp/etc/debian_version"
        case "$ver" in
            4.*) NAME="Debian 4 (etch)"; otherNAME="$NAME" ;;
            5.*) NAME="Debian 5 (lenny)"; otherNAME="$NAME" ;;
            8.*) NAME="Debian 8 (jessie)"; otherNAME="$NAME" ;;
            12.*) NAME="Debian-Ports 12 (bookworm)"; otherNAME="Debian 12 (bookworm)" ;;
            13.*) NAME="Debian-Ports 13 (trixie)"; otherNAME="Debian 13 (trixie)" ;;
            *) NAME="Debian $ver"; otherNAME="$NAME" ;;
        esac

        ppcDistro="\e[1;31m$NAME PPC"
        ppcDistroHighlighted="\e[31m$NAME PPC"
        otherDistro="\e[1;31mUnknown $otherNAME"
        otherDistroHighlighted="\e[31mUnknown $otherNAME"
        ppcDistroColorLen="7 5"
        otherDistroColorLen="7 5"
    fi

    # also... are we an old copy of Fedora?
    if [ -f "$tmp/etc/fedora-release" ]; then
        # trim out ' release' to make it fit nicer on screen
        NAME="$(sed "s/ release//" < "$tmp/etc/fedora-release")"
        ppcDistro="\e[34m$NAME PPC"
        ppcDistroHighlighted="\e[1;34m$NAME PPC"
        otherDistro="\e[1;31mUnknown \e[22m\e[34m$NAME"
        otherDistroHighlighted="\e[31mUnknown \e[22m\e[34m$NAME"
        ppcDistroColorLen="5 7"
        otherDistroColorLen="16 16"
    fi

    # also... are we an old copy of Yellow Dog?
    if [ -f "$tmp/etc/yellowdog-release" ]; then
        # assume always the same color len
        ppcDistroColorLen="7 7"
        otherDistroColorLen="12 14"

        # trim out ' Linux release' to make it fit nicer on screen
        NAME="$(sed "s/ Linux release//" < "$tmp/etc/yellowdog-release")"
        ppcDistro="\e[1;33m$NAME PPC"
        ppcDistroHighlighted="\e[1;33m$NAME PPC"
        otherDistro="\e[1;31mUnknown \e[33m$NAME"
        otherDistroHighlighted="\e[31mUnknown \e[1m\e[33m$NAME"
    fi

    # also, are we an old copy of Gentoo?
    if [ -f "$tmp/etc/gentoo-release" ]; then
        # yes!  if we have /etc/os-release too, then it's modern
        # if not, it's old
        ppcDistro="\e[1;35mGentoo PPC"
        ppcDistroHighlighted="\e[35mGentoo PPC"
        otherDistro="\e[1;31mUnknown \e[35mGentoo"
        otherDistroHighlighted="\e[31mUnknown \e[35mGentoo"
        ppcDistroColorLen="7 5"
        otherDistroColorLen="12 10"
        if [ "$gotOSRel" != "true" ]; then
            ppcDistro="$ppcDistro (old)"
            ppcDistroHighlighted="$ppcDistroHighlighted (old)"
        fi
    fi

    # these are not a fatal errors, but we
    # still can't know what distro it is...
    if [ "$gotOSRel" != "true" ] && [ "$ppcDistro" = "" ]; then
        echo "Unknown" > "$distro"
        prob "no os-release file"
        exitCode=104
    elif [ "$ID" = "" ] && [ "$ppcDistro" = "" ]; then
        echo "Unknown" > "$distro"
        prob "bad os-release file"
        exitCode=104
    elif [ "$ppcDistro" = "" ]; then
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
        artix)
            initLabel=""
            if   [ -x "$tmp/sbin/openrc-init" ] || [ -d "$tmp/etc/openrc" ] || [ -d "$tmp/etc/init.d" ]; then
                initLabel=" (OpenRC)"
            elif [ -x "$tmp/sbin/runit-init" ]  || [ -d "$tmp/etc/runit" ] || [ -d "$tmp/etc/sv" ]; then
                initLabel=" (Runit)"
            elif [ -x "$tmp/sbin/dinit" ] || [ -x "$tmp/bin/dinit" ] || [ -d "$tmp/etc/dinit.d" ]; then
                initLabel=" (Dinit)"
            fi
            ppcDistro="\e[1;36mArtixPOWER${initLabel}"
            ppcDistroHighlighted="\e[36mArtixPOWER${initLabel}"
            otherDistro="\e[1;31mUnknown \e[36mArtix Linux${initLabel}"
            otherDistroHighlighted="\e[31mUnknown \e[36mArtix Linux${initLabel}"
            ppcDistroColorLen="7 5"
            otherDistroColorLen="12 10"
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
        adelie)
            ppcDistro="\e[34mAdelie PPC"
            ppcDistroHighlighted="\e[1;34mAdelie PPC"
            otherDistro="\e[1;31mUnknown \e[22m\e[34mAdelie"
            otherDistroHighlighted="\e[31mUnknown \e[22m\e[34mAdelie"
            ppcDistroColorLen="5 7"
            otherDistroColorLen="16 16"
            ;;
        chimera)
            ppcDistro="\e[33mChimera PPC"
            ppcDistroHighlighted="\e[31mChimera PPC"
            otherDistro="\e[1;31mUnknown \e[22m\e[33mChimera"
            otherDistroHighlighted="\e[31mUnknown Chimera"
            ppcDistroColorLen="5 5"
            otherDistroColorLen="16 5"
            ;;
        buildroot)
            # check the name
            case "$NAME" in
                Batocera.linux)
                    ppcDistro="\e[33mBatocera"
                    ppcDistroHighlighted="\e[31mBatocera"
                    otherDistro="\e[1;31mUnknown \e[33mBatocera"
                    otherDistroHighlighted="\e[31mUnknown Batocera"
                    ppcDistroColorLen="5 5"
                    otherDistroColorLen="12 10"
                    ;;
                *)
                    ppcDistro="\e[1;32mBuildroot PPC"
                    ppcDistroHighlighted="\e[32mBuildroot PPC"
                    otherDistro="\e[1;31mUnknown \e[32mBuildroot"
                    otherDistroHighlighted="\e[31mUnknown Buildroot"
                    ppcDistroColorLen="7 5"
                    otherDistroColorLen="12 10"
                    ;;
            esac
            ;;
        *) ppcDistro="Unknown"; otherDistro="Unknown";;
        esac
    fi
elif [ "$batoceraSquashfs" != "true" ]; then
    ppcDistro="\e[1;32mPPCDroid"
    ppcDistroHighlighted="\e[32mPPCDroid"
    otherDistro="\e[1;31mUnknown \e[32mAndroid"
    otherHighlightedDistro="\e[31mUnknown \e[32mAndroid"
    ppcDistroColorLen="7 5"
    otherDistroColorLen="12 10"
fi


# do we have /sbin/init (or /init if Android)?
if [ "$android" != "true" ] && [ "$batoceraSquashfs" != "true" ]; then
    if ! [ -f "$tmp/sbin/init" ] && ! [ -L "$tmp/sbin/init" ]; then
        # we may have multiple problems be this point, seperate by line.
        prob "/sbin/init does not exist"
        exitCode=105
    else
        init="$tmp/$(realpath $tmp/sbin/init)"
    fi
else
    init="$tmp/init"
fi

if ! [ -x "$init" ] && [ "$batoceraSquashfs" != "true" ]; then
    prob "/sbin/init does exist but isn't executable"
    exitCode=105
fi

# what init is this copy of ArtixPOWER and set name on Menu accordingly
if [ "$isArtix" = "true" ] && [ -x "$init" ] && [ "$batoceraSquashfs" != "true" ]; then
    case "$(basename "$init")" in
        openrc-init)        initLabel=" (OpenRC)";;
        runit-init)         initLabel=" (Runit)";;
        dinit|dinit-init)   initLabel=" (Dinit)";;
    esac
    ppcDistro="${ppcDistro}${initLabel}"
    ppcDistroHighlighted="${ppcDistroHighlighted}${initLabel}"
    otherDistro="${otherDistro}${initLabel}"
    otherDistroHighlighted="${otherDistroHighlighted}${initLabel}"
fi

# are we sure we have a PPC distro?
if [ -f "$init" ] && [ "$batoceraSquashfs" != "true" ]; then
    out=$(file -L "$init")
    case "$out" in
        *"PowerPC or cisco 4500,"* | *"execline script text executable"* | *"POSIX shell script, ASCII text executable"*) ;;
        *) prob '/sbin/init is not for PowerPC'; notPPC=true; exitCode=105 ;;
    esac
fi


umount "$tmp"
# in case umount failed, this won't nuke the FS
rmdir "$tmp"
if [ "$notPPC" = "true" ]; then
    printf "$otherDistro\n$otherDistroHighlighted" > "$distro"
    printf "$otherDistroColorLen" > "$colors"
else
    printf "$ppcDistro\n$ppcDistroHighlighted" > "$distro"
    printf "$ppcDistroColorLen" > "$colors"
fi

[ "$android" = "true" ] && touch /._android$2
[ "$batoceraSquashfs" = "true" ] && touch /._batocera$2

exit $exitCode
