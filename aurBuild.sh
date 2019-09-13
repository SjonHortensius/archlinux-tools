#!/bin/bash
set -eu

# verify our dependencies
which sudo makepkg >/dev/null

INSTALL=0;  [[ "${1-}" == "--install" ]] && { INSTALL=1 ; shift; }
GETDEPS=1;  [[ "${1-}" == "--nodeps" || "${1-}" == "-d"  ]] && { GETDEPS=0 ; shift; }

if [[ "${1-}" == "--help" ]]
then
	cat <<-EOT
		aurBuild version 1.1: Build a package from AUR.
		Author: Sjon Hortensius <sjon@hortensius.net>

		usage: 
		  aurBuild [--install] [--help]
		    <no option>  List all locally installed AUR packages and their status
		    --install    Update all locally installed AUR packages
		    --help       Help and information about the script

		  aurBuild [--install] <package> <makepkg options>
		    <package>             Build a specific AUR package
		    --install <package>   Build and install a specific package
		                          Additional options are passed to makepkg
	EOT

	exit 0
elif [[ $# -eq 0 ]]
then
	updates=()

	# check for updates for all foreign packages
	while read pkg curr
	do
		echo -en $pkg' '$curr': \e[1;33m'
		version=$(curl -sS "https://aur.archlinux.org/rpc.php?type=info&arg=$pkg" | tr , '\n' | grep '"Version":' | cut -d: -f2 | tr -d '"')
		[[ -z $version ]] && { echo -e 'no longer available\e[0m'; continue; }
		[[ $(vercmp $version $curr) -lt 1 ]] && { echo -e '\e[0mup to date'; continue; }

		echo -e 'update available: '$version'\e[0m'
		[[ $INSTALL -eq 1 ]] && updates+=($pkg)
	done < <(pacman -Qm)

	for pkg in ${updates[*]}
	do
		# can't do this directly - read eats stdin
		$0 --install $pkg
	done

	exit 0
fi

[[ $UID -gt 0 ]] && { echo "This script is safer when run as root, it allows us to sudo -u nobody, press <enter> to continue anyway"; read; }

PACKAGE=$1 ; shift
OPTS="--clean --log $*"
DIR=/var/tmp/aurBuild-$UID

#FIXME always empty $DIR so we know all packages in it are ours? Means we can simply pacman -S *.pkg, fixes split packages. But moves install req from caller (when recursive)
mkdir -p $DIR
curl -#S "https://aur.archlinux.org/cgit/aur.git/snapshot/$PACKAGE.tar.gz" | tar xz -C $DIR
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
		pacman -Q $pkg &>/dev/null && continue

		# package is available ?
		pkgAvail=
		while read aliasPkg
		do
			# above `pacman -Q $pkg` no longer resolves aliases such as java-runtime. They do get returned from -Ss
			pacman -Q $aliasPkg &>/dev/null && continue 2

			pkgAvail=1
		done < <(pacman -Sqs ^${pkg//+/\\+}$)

		[[ $pkgAvail ]] && { depInstall[${#depInstall[*]}]=$pkg ; continue; }

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

# import variables from SRCINFO | populates from all subpackages
for k in {make,check,}depends arch pkg{ver,rel}
do
	declare -a pkg_$k
	while read v; do eval "pkg_$k+=('"$v"')"; done < <(grep ^$'\t'$k' =' $DIR/$PACKAGE/.SRCINFO | cut -d' ' -f3-)
	declare -r pkg_$k
done

pkgNames=($(grep '^pkgname =' $DIR/$PACKAGE/.SRCINFO | cut -d' ' -f3-))
pkgIsVcs=($(grep -cE ^$'\t'"source = (bzr.*|git.*|hg.*|svn.*)://" $DIR/$PACKAGE/.SRCINFO ||:))
pkgFile=$DIR/$PACKAGE/$PACKAGE-$pkg_pkgver-$pkg_pkgrel-$pkg_arch.pkg.tar.xz
[[ $pkg_arch != "any" ]] && pkgFile=$DIR/$PACKAGE/$PACKAGE-$pkg_pkgver-$pkg_pkgrel-$(uname -m).pkg.tar.xz

[[ ! -f $pkgFile ]] && getDeps ${pkg_makedepends[*]} ${pkg_checkdepends[*]}
[[ $GETDEPS ]] && getDeps ${pkg_depends[*]}

if [[ ! -f $pkgFile ]]
then
	if [[ $UID -eq 0 ]]
	then
		chown -R nobody: ./
		sudo -u nobody HOME=/tmp makepkg $OPTS >/dev/null
	else
		makepkg $OPTS >/dev/null
	fi

	uselessPkg=($(pacman -Qdttq|tr '\n' ' '))
	[[ ${#uselessPkg[*]} -gt 0 ]] && echo -ne 'Build completed, these packages are no longer required: \e[1;33m'${uselessPkg[*]}'\e[0m. '
else
	echo -ne $PACKAGE'\e[1;33m has already been build.\e[0m '
fi

createdPkg=($(find $DIR/$PACKAGE/ -name \*.pkg.tar.xz -print))
echo -ne 'Created packages: \e[1;33m'${createdPkg[*]}'\e[0m\n'

if [[ $INSTALL -eq 1 ]]; then
	[[ ! -f $pkgFile && ${#created} -eq 1 && $pkgIsVcs ]] && pkgFile=${created[0]}
	pacman --noconfirm -U $pkgFile
fi

exit 0
