#!/bin/bash
set -e

if [[ "$1" == "--help" ]]
then
	cat <<-help

		aurBuild version 1.1: Build a package from AUR.
		Author: Sjon Hortensius <sjon@hortensius.net>

		usage: 
			aurBuild
			aurBuild [--install] <package> <makepkg options>

		<no option>			All locally installed AUR packages will be listed
		--install			All locally installed AUR packages will be updated
		<package>			Build a specific AUR package
		--install <package>	Build and install a specific package
		--help				Help and information about the script

		Additional options are passed to makepkg; type "makepkg --help" for makepkg options

	help

	exit 0
fi

# verify our dependencies
which sudo makepkg >/dev/null

[[ "$1" == "--install" ]] && { INSTALL=1 ; shift; } || INSTALL=0

if [[ $# -eq 0 ]]
then
	# check for updates for all foreign packages
	pacman -Qm | while read pkg curr
	do
		version=`curl -sS "https://aur4.archlinux.org/rpc.php?type=info&arg=$pkg" | tr , '\n' | grep '"Version":' | cut -d: -f2 | tr -d '"'`
		[[ -z $version ]] && { echo -e '\e[1;33m'$pkg'\e[0m - no (longer) available, skipping' >&2 ; continue ; }
		[[ `vercmp $version $curr` -lt 1 ]] && continue

		echo -e '\e[1;33m'$pkg'\e[0m - update available: '$curr' > '$version
		[[ $INSTALL -eq 1 ]] && $0 --install $pkg
	done

	exit 0
fi

[[ $UID -gt 0 ]] && { echo "This script is safer when run as root, it allows us to sudo -u nobody, press <enter> to continue"; read; }

PACKAGE=$1 ; shift
OPTS="--clean --log $*"
DIR=/var/tmp/aurBuild-$UID

[[ ! -d $DIR ]] && mkdir $DIR
curl -#S "https://aur4.archlinux.org/cgit/aur.git/snapshot/$PACKAGE.tar.gz" | tar xz -C $DIR
cd $DIR/$PACKAGE

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
		pacman -Ss ^${pkg//+/\\+}$ >/dev/null && { depInstall[${#depInstall[*]}]=$pkg ; continue; }

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

# extract variables from SRCINFO
     deps=(`grep "^	depends =" $DIR/$PACKAGE/.SRCINFO | cut -d' ' -f3- | tr '\n' ' '`)
buildDeps=(`grep "^	makedepends =" $DIR/$PACKAGE/.SRCINFO | cut -d' ' -f3- | tr '\n' ' '`)
  pkgArch=(`grep "^	arch =" $DIR/$PACKAGE/.SRCINFO | cut -d' ' -f3- | tr '\n' ' '`)
   pkgVer=(`grep "^	pkgver =" $DIR/$PACKAGE/.SRCINFO | cut -d' ' -f3- | tr '\n' ' '`)
   pkgRel=(`grep "^	pkgrel =" $DIR/$PACKAGE/.SRCINFO | cut -d' ' -f3- | tr '\n' ' '`)

[[ $pkgArch == "any" ]] && pkgArch='any' || pkgArch=`uname -m`
pkgFile=$DIR/$PACKAGE/$PACKAGE-$pkgVer-$pkgRel-$pkgArch.pkg.tar.xz

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
