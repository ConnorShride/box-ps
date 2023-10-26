#!/bin/bash

# pulls down the most recent box-ps docker images and uses it to sandbox the given powershell script
# in a network-isolated environment

# USAGE
# For the first argument, either give a path to a powershell script file, or the -p option to tell
# this script to read the powershell from stdin. Then, either give a path to put the output JSON
# file only or give "-d <path>" to give a path to an output directory containing the full analysis
# results. If a timeout for sandboxing is desired, give that last.

# return codes: see README.md

usage1="docker-box-ps.sh <powershell script path> <output JSON file path>"
usage2="docker-box-ps.sh <powershell script path> -d <output analysis dir>"
usage3="<script content> | docker-box-ps.sh -p <output JSON file path> -t <timeout>"
usage4="<script content> | docker-box-ps.sh -p -d <output analysis dir>"
usage5="docker-box-ps.sh <powershell script path> -d <output analysis dir> -t <timeout>"

if [[ $# == 0 ]]
then
	>&2 echo "[-] example 1: $usage1"
	>&2 echo "[-] example 2: $usage2"
	>&2 echo "[-] example 3: $usage3"
	>&2 echo "[-] example 4: $usage4"
	>&2 echo "[-] example 5: $usage5"
	exit 0
fi

# argument validation
if [[ "$#" -lt 2 ]] || [[ "$#" -gt 5 ]]
then
	>&2 echo "[-] example 1: $usage1"
	>&2 echo "[-] example 2: $usage2"
	>&2 echo "[-] example 3: $usage3"
	>&2 echo "[-] example 4: $usage4"
	>&2 echo "[-] example 5: $usage5"
	exit 1
fi

if [[ $1 != "-p" ]] && [[ ! -f $1 ]]
then
	>&2 echo "[-] input file does not exist"
	exit 3
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
	exit 2
fi

if [ ! -z "$bad_permissions" ]
then
	>&2 echo "[-] your user does not have docker permissions. add your user to the docker group"
	exit 2
fi

# param: container ID
kill_container() {
	docker kill $1 > /dev/null
	echo "[+] killed container"
}

return_code=0

# pull latest prod box-ps image
echo "[+] pulling latest docker image of box-ps"
docker pull connorshride/box-ps:latest > /dev/null
#docker pull connorshride/box-ps:develop > /dev/null

if [[ $? != 0 ]]
then
	>&2 echo "[-] failed to pull the box-ps container from dockerhub"
	return_code=5
fi

# start container with no networking
echo "[+] starting docker container"
docker run -td --network none connorshride/box-ps:latest > /dev/null
#docker run -td --network none connorshride/box-ps:develop > /dev/null

if [[ $? != 0 ]]
then
	>&2 echo "[-] failed to run the box-ps docker container"
	return_code=5
fi

# bug out if we've already failed
if [[ $return_code != 0 ]]
then
	exit $return_code
fi

container_id=$(docker ps -f status=running -f ancestor=connorshride/box-ps -l | tail -n +2 | cut -f1 -d' ')
#container_id=$(docker ps -f status=running -f ancestor=connorshride/box-ps:develop -l | tail -n +2 | cut -f1 -d' ')

# pipe the input into a file in the docker container
if [[ $1 == "-p" ]]
then
	docker exec -i $container_id /bin/bash -c "cat - > /opt/box-ps/infile.ps1" < /dev/stdin

	if [[ $? != 0 ]]
	then
		>&2 echo "[-] failed to pipe the script into container"
		return_code=5
	fi

# copy input script into container
else
	docker cp $1 "$container_id:/opt/box-ps/infile.ps1"

	if [[ $? != 0 ]]
	then
		>&2 echo "[-] failed to copy the script into container"
		return_code=5
	fi
fi

# bug out if we've already failed
if [[ $return_code != 0 ]]
then
	kill_container $container_id
	exit $return_code
fi

# run box-ps in docker container
echo "[+] running box-ps in container"

# user wants the whole analysis dir
if [[ $2 == "-d" ]]
then

	if [[ $timeout ]]
	then
		docker exec $container_id pwsh ./box-ps.ps1 -InFile "./infile.ps1" -OutDir "./outdir" -Timeout $timeout
	else
		docker exec $container_id pwsh ./box-ps.ps1 -InFile "./infile.ps1" -OutDir "./outdir"
	fi

	return_code=$?

	# don't try to copy the analysis results out if sandboxing failed
	if [[ $return_code == 0 ]]
	then

		# remove the output dir if it exists
		if [[ -d $3 ]]
		then
			rm -r $3
		fi

		docker cp "$container_id:/opt/box-ps/outdir" $3

		if [[ $? != 0 ]]
		then
			return_code=5
			>&2 echo "[-] failed to copy analysis directory out of container"
		else
			echo "[+] copied analysis directory from container to $3"
		fi
	fi

# user just wants the JSON report
else

	if [[ $timeout ]]
	then
		docker exec $container_id pwsh ./box-ps.ps1 -InFile "./infile.ps1" -OutFile "./outfile.json" -Timeout $timeout
	else
		docker exec $container_id pwsh ./box-ps.ps1 -InFile "./infile.ps1" -OutFile "./outfile.json"
	fi

	return_code=$?

	# don't try to copy the analysis results out if sandboxing failed
	if [[ $return_code == 0 ]]
	then

		docker cp "$container_id:/opt/box-ps/outfile.json" $2

		if [[ $? != 0 ]]
		then
			return_code=5
			>&2 echo "[-] failed to copy analysis report out of container"
		else
			echo "[+] copied analysis report from container to $2"
		fi
	fi
fi

if [[ $return_code == 124 ]]
then
	echo ""
	>&2 echo "[-] sandboxing timed out"
fi

kill_container $container_id

# pass on the return code from the docker exec sandboxing call
exit $return_code
