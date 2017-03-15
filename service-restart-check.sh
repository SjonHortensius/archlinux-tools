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

for file in /etc/systemd/system/*.wants/*.service
do
	# inside for-loop so they align with the columns
	[[ -z $headerDone ]] && { echo -e '\e[1;33mPackage Upgraded Service Last-restart\e[0m'; headerDone=1; }

	service=`readlink $file 2>/dev/null`
	package=`pacman -Qoq $service` || continue
	file=${file##*/}

	started=`systemctl status -n0 $file | grep Active: | cut -d' ' -f8-10`
	updated=`pacman -Qi $package | grep '^Install Date' | cut -d: -f2-`

	[[ `date -d "$started" +%s` -lt `date -d "$updated" +%s` ]] || continue

	[[ $1 == '--now' ]] && systemctl restart $file && echo -n '* '

	echo $package `date -d "$updated" +'%Y-%m-%d:%H:%M:%S'` $file `date -d "$started" +'%Y-%m-%d:%H:%M:%S'`
done|column -t
