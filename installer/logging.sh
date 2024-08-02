#!/bin/ash
# shellcheck shell=sh

warn() {
    printf "\x1b[1;33mWARNING!! $1\x1b[0m\n"
}

error() {
    printf "\x1b[1;31mERROR!! $1\x1b[0m\n"
}

success() {
    printf "\x1b[32m$1\x1b[0m\n"
}
