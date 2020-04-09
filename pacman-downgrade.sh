#!/bin/sh

[[ $# -lt 2 ]] && { echo "usage: $0 PACKAGE VERSION [RELEASE]" >&2; exit 2; }

if [[ -f /var/cache/pacman/pkg/$1-$2-${3:-1}-x86_64.pkg.tar.* ]]; then
	exec pacman -U /var/cache/pacman/pkg/$1-$2-${3:-1}-x86_64.pkg.tar.*
else
	exec pacman -U https://archive.archlinux.org/packages/${1:0:1}/$1/$1-$2-${3:-1}-x86_64.pkg.tar.zst
fi
