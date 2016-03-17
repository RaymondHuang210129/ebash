#!/usr/bin/env bash
#
# Copyright 2011-2015, SolidFire, Inc. All rights reserved.
#

__BU_OS=$(uname)


# Load configuration files
if [[ -e /etc/bashutils.conf ]]; then
    source /etc/bashutils.conf
fi

if [[ -e ${XDG_CONFIG_HOME:-${HOME:-}/.config}/bashutils.conf ]]; then
    source ${XDG_CONFIG_HOME:-${HOME:-}/.config}/bashutils.conf
fi

: ${TERM:=xterm-256color}

# PLATFORM MUST BE FIRST.  It sets up aliases.  Those aliases won't be expanded
# inside functions that are already declared, only inside those declared after
# this.
source "${BASHUTILS}/platform.sh"
source "${BASHUTILS}/efuncs.sh"
source "${BASHUTILS}/cgroup.sh"
source "${BASHUTILS}/chroot.sh"
source "${BASHUTILS}/dpkg.sh"
source "${BASHUTILS}/elock.sh"
source "${BASHUTILS}/netns.sh"
source "${BASHUTILS}/network.sh"
source "${BASHUTILS}/daemon.sh"
source "${BASHUTILS}/archive.sh"
source "${BASHUTILS}/overlayfs.sh"
