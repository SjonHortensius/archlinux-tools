#!/bin/bash
set -e

if [[ $1 == "--help" ]]
then
	cat <<-help
		service-restart-check version 1.0: Verify if any systemd services need a restart
		Author: Sjon Hortensius <sjon@hortensius.net>

		usage:
		  service-restart-check [--now] [--help]
		    <no option>  List all systemd services that have been upgraded since starting
		    --now        Restart all services that have been upgraded
		    --help       Help and information about the script
	help

	exit 0
fi

[[ $1 == '--now' ]] && systemctl daemon-reload

while read -r name x
do
	# inside for-loop so they align with the columns. Prefixed with newline to prevent first column from not being wide enough
	[[ -z $headerDone ]] && { echo -e '\e[1;33m\nPackage\tUpgraded\tService\tLast-restart\e[0m'; headerDone=1; }

	# don't restart nspawns
	[[ $name == systemd-nspawn@* ]] && continue

	path=$(systemctl show -p FragmentPath $name | cut -d= -f2)

	# services in /etc are machine-specific and not owned by a pkg
	[[ $path == /etc/systemd/system/* ]] && continue

	package=$(pacman -Qoq $path)

	started=$(systemctl show -p ActiveEnterTimestamp $name | cut -d= -f2)
	updated=$(pacman -Qi $package | grep '^Install Date' | cut -d: -f2-)

	[[ $(date -d "$started" +%s) -lt $(date -d "$updated" +%s) ]] || continue

	[[ $1 == '--now' ]] && systemctl restart $name

	printf '%s\t%s\t%s\t%s\n' $package $(date -d "$updated" +'%Y-%m-%d:%H:%M:%S') $name $(date -d "$started" +'%Y-%m-%d:%H:%M:%S')

done < <(systemctl --plain --no-legend list-units --type=service --state=running) | column -ts $'\t'
