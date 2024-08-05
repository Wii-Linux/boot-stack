#!/bin/ash
# shellcheck shell=sh

warn() {
	echo -e "\x1b[1;33mWARNING!! $1\x1b[0m"
}

error() {
	echo -e "\x1b[1;31mERROR!! $1\x1b[0m"
}

success() {
	echo -e "\x1b[32m$1\x1b[0m"
}

logfile=/var/log/installer.log
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
