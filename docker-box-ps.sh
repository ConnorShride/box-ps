#!/bin/bash

# pulls down the most recent box-ps docker images and uses it to sandbox the given powershell script
# in a network-isolated environment

# USAGE
# For the first argument, either give a path to a powershell script file, or the -p option to tell
# this script to read the powershell from stdin. Then, either give a path to put the output JSON
# file only or give "-d <path>" to give a path to an output directory containing the full analysis  
# results. If a timeout for sandboxing is desired, give that last.

usage1="docker-box-ps.sh <powershell script path> <output JSON file path>"
usage2="docker-box-ps.sh <powershell script path> -d <output analysis dir>"
usage3="<script content> | docker-box-ps.sh -p <output JSON file path> -t <timeout>"
usage4="<script content> | docker-box-ps.sh -p -d <output analysis dir>"
usage5="docker-box-ps.sh <powershell script path> -d <output analysis dir> -t <timeout>"

# argument validation
if [[ "$#" -lt 2 ]] || [[ "$#" -gt 5 ]]
then
	>&2 echo "[-] example 1: $usage1"
	>&2 echo "[-] example 2: $usage2"
	>&2 echo "[-] example 3: $usage3"
	>&2 echo "[-] example 4: $usage4"
	>&2 echo "[-] example 5: $usage5"
	exit -1
fi

if [[ $1 != "-p" ]] && [[ ! -f $1 ]]
then
	>&2 echo "[-] input file does not exist"
	exit -1
fi

# get timeout if given
timeout_args="${@: -2}"
if [[ $timeout_args == -t* ]]
then
	timeout="${@: -1}"
fi

# verify valid docker environment
ps_output=`docker ps 2>&1`
is_not_installed=`echo $ps_output | grep "command not found"`
bad_permissions=`echo $ps_output | grep "Got permission denied"`

if [ ! -z "$is_not_installed" ]
then
	>&2 echo "[-] you don't have docker installed"
	exit -1
fi

if [ ! -z "$bad_permissions" ]
then
	>&2 echo "[-] your user does not have docker permissions. add your user to the docker group"
	exit -1
fi

# pull latest prod box-ps image
echo "[+] pulling latest docker image of box-ps"
docker pull connorshride/box-ps:latest > /dev/null

# start container with no networking
echo "[+] starting docker container"
docker run -td --network none connorshride/box-ps:latest > /dev/null

container_id=$(docker ps -f status=running -f ancestor=connorshride/box-ps -l | tail -n +2 | cut -f1 -d' ')

# pipe the input into a file in the docker container
if [[ $1 == "-p" ]]
then
	docker exec -i $container_id /bin/bash -c "cat - > /opt/box-ps/infile.ps1" < /dev/stdin

# copy input script into container
else
	docker cp $1 "$container_id:/opt/box-ps/infile.ps1"
fi

# run box-ps in docker container
echo "[+] running box-ps in container"

# user wants the whole analysis dir
if [[ $2 == "-d" ]]
then

	# TODO support capturing stderr from this exec call so we can tell when sandboxing failed better
	if [[ $timeout ]]
	then
		docker exec $container_id timeout $timeout pwsh ./box-ps.ps1 -InFile "./infile.ps1" -OutDir "./outdir"

		# send a message to stderr saying we've timed out
		if [[ $? -eq "124" ]]
		then
			echo ""
			>&2 echo "[-] sandboxing timed out"
			timed_out="true"
		fi
	else
		docker exec $container_id pwsh ./box-ps.ps1 -InFile "./infile.ps1" -OutDir "./outdir"
	fi

	# don't try to copy the analysis results out if we've timed out
	if [[ $timed_out != "true" ]]
	then
		# remove the output dir if it exists
		if [[ -d $3 ]]
		then
			rm -r $3
		fi

		docker cp "$container_id:/opt/box-ps/outdir" $3
		echo "[+] moved analysis directory from container to $3"
	fi

# user just wants the JSON report
else

	if [[ $timeout ]]
	then
		docker exec $container_id timeout $timeout pwsh ./box-ps.ps1 -InFile "./infile.ps1" -OutFile "./outfile.json"
		
		# send a message to stderr saying we've timed out
		if [[ $? -eq "124" ]]
		then
			echo ""
			>&2 echo "[-] sandboxing timed out"
			timed_out="true"
		fi

	else
		echo "HERE"
		docker exec $container_id pwsh ./box-ps.ps1 -InFile "./infile.ps1" -OutFile "./outfile.json"
		echo "$?"
	fi

	# don't try to copy the analysis results out if we've timed out
	if [[ $timed_out != "true" ]]
	then
		echo "HERE2"
		docker cp "$container_id:/opt/box-ps/outfile.json" $2
		echo "$?"
		echo "[+] moved analysis report from container to $2"
	fi
fi

# kill container
docker kill $container_id > /dev/null
echo "[+] killed container"
