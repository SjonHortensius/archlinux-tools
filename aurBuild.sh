#!/bin/bash
# Author: Sjon Hortensius <sjon@hortensius.net>
# build a package from aur. Extra options will be passed to makepkg
# usage: aurBuild [--install] [package]
set -e

# verify our dependencies
which sudo makepkg >/dev/null

[[ $UID -gt 0 ]] && { echo "This script is safer when run as root, it allows us to sudo -u nobody, press <enter> to continue"; read; }
[[ "$1" == "--install" ]] && { INSTALL=1 ; shift; } || INSTALL=0

if [[ $# -eq 0 ]]
then
	# check for updates for all foreign packages
	pacman -Qm | while read pkg curr
	do
		version=`curl -sS "https://aur.archlinux.org/rpc.php?type=info&arg=$pkg" | tr , '\n' | grep '"Version":' | cut -d: -f2 | tr -d '"'`
		[[ -z $version ]] && { echo -e '\e[1;33m'$pkg' - no longer available, skipping\e[0m' >&2 ; continue ; }

		[[ `vercmp $version $curr` -lt 1 ]] && continue
		echo -e '\e[1;33m'$pkg' - update availble: '$curr' > '$version'\e[0m'
		[[ $INSTALL -eq 1 ]] && $0 --install $pkg $OPTS
	done

	exit 0
fi

PACKAGE=$1 ; shift
OPTS="--clean --log $*"
DIR=/var/tmp/aurBuild-$UID

[[ ! -d $DIR ]] && mkdir $DIR
curl -#S "https://aur.archlinux.org/packages/${PACKAGE:0:2}/$PACKAGE/$PACKAGE.tar.gz" | tar xz -C $DIR
cd $DIR/$PACKAGE

# use subshell to extract variables safely
echo -e '#!/bin/bash -r\nsource PKGBUILD\necho ${!1}'>$DIR/$PACKAGE/pkgVar.sh
chmod +x $DIR/$PACKAGE/pkgVar.sh
[[ $UID -eq 0 ]] && pkgVar='sudo -u nobody '
pkgVar="$pkgvar ./pkgVar.sh"

# install all passed dependencies
function getDeps
{
	local depInstall=() depBuild=() created=()

	for pkg in $*
	do
		# strip version requirements
		pkg=${pkg%%[>=<]*}

		# package is installed ?
		pacman -Q $pkg >/dev/null 2>&1 && continue

		# package is available ?
		pacman -Ss ^$pkg$ >/dev/null && { depInstall[${#depInstall[*]}]=$pkg ; continue; }

		depBuild[${#depBuild[*]}]=$pkg
	done

	for pkg in ${depBuild[*]}
	do
		echo -e '\e[1;33m'$PACKAGE' has unknown dependency '$pkg'; attempting to build from AUR\e[0m'
		$0 $pkg $OPTS

		created[${#created[*]}]=$DIR/$pkg'/'$pkg'-[0-9]*.pkg.tar.xz'
	done

	[[ ${#created[*]} -gt 0 ]] && pacman -U --asdep --needed ${created[*]}
	[[ ${#depInstall[*]} -gt 0 ]] && pacman -S --asdeps --needed ${depInstall[*]}

	echo 
}

deps=(`$pkgVar 'depends[*]'`)
buildDeps=(`$pkgVar 'makedepends[*]'`)
[[ `$pkgVar 'arch'` == "any" ]] && pkgArch='any' || pkgArch=`uname -m`
pkgFile=$DIR/$PACKAGE/$PACKAGE-`$pkgVar 'pkgver'`-`$pkgVar 'pkgrel'`-$pkgArch.pkg.tar.xz

[[ ! -f $pkgFile ]] && getDeps ${buildDeps[*]}
getDeps ${deps[*]}

if [[ ! -f $pkgFile ]]
then
	if [[ $UID -eq 0 ]]
	then
		chown -R nobody: ./
		sudo -u nobody makepkg $OPTS >/dev/null
	else
		makepkg $OPTS >/dev/null
	fi

	echo -e '\e[1;33m'$PACKAGE' build completed; can be found in '$DIR/$PACKAGE'\e[0m'
	[[ ${#buildDeps[*]} -gt 0 ]] && echo -e '\e[1;33mSome of these packages might no longer be required: '${buildDeps[*]}'\e[0m'
else
	echo -e '\e[1;33m'$PACKAGE' has already been build; can be found in '$DIR/$PACKAGE/'\e[0m'
fi

[[ $INSTALL -eq 1 ]] && pacman -U $pkgFile

exit 0
