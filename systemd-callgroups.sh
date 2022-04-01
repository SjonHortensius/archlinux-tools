#!/bin/bash
# generate SystemCallFilter from list of syscalls
#
# run this script, type or paste a list of syscalls and this script will return the required @callgroups
## Sjon Hortensius, 2020
set -ue

# dynamically initialize callgroups
declare -A callgroup
while IFS= read -r line
do
	[[ ${#line} -eq 0 ]] && continue

	if [[ $line == @* ]]
	then
		group=${line:1}
	elif [[ $line != \ *\#* ]]
	then
		callgroup[${line##    }]=$group
	fi
done < <(systemd-analyze syscall-filter)

# now read syscalls, eg. from strace -c
while read -r syscall
do
	if [[ ${callgroup[$syscall]} ]]
	then
		echo \@${callgroup[$syscall]} $syscall
	else
		echo NO_GROUP $syscall
	fi
done | sort -u | column -t
