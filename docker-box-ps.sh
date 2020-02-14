#!/bin/bash

# pulls down the most recent box-ps docker images and uses it to sandbox the given powershell script
# in a network-isolated environment

usage="docker-ps.sh <poweshell script path> <output JSON file path>"

# argument validation
if [ "$#" -ne 2 ]
then
	echo "[-] two arguments required. $# provided"
	echo "[-] usage: $usage"
	exit -1
fi

if [ ! -f $1 ]
then
	echo "[-] input file does not exist"
	exit -1
fi

in_script_path=$1
out_json_path=$2

# verify valid docker environment
ps_output=`docker ps 2>&1`
is_not_installed=`echo $ps_output | grep "command not found"`
bad_permissions=`echo $ps_output | grep "Got permission denied"`

if [ ! -z "$is_not_installed" ]
then
	echo "[-] you don't have docker installed"
	exit -1
fi

if [ ! -z "$bad_permissions" ]
then
	echo "[-] your user does not have docker permissions. add your user to the docker group"
	exit -1
fi

# pull latest prod box-ps image
echo "[+] pulling latest docker image of box-ps"
docker pull connorshride/box-ps:latest > /dev/null

# start container with no networking
echo "[+] starting docker container"
docker run -td --network none connorshride/box-ps:latest > /dev/null

in_script_short_name=`basename $in_script_path`
out_script_short_name=`basename $out_json_path`

# copy input script into container
container_id=$(docker ps -f status=running -f ancestor=connorshride/box-ps -l | tail -n +2 | cut -f1 -d' ')
docker cp $in_script_path "$container_id:/opt/box-ps/"

# run box-ps in docker container
echo "[+] running box-ps in container"
docker exec $container_id pwsh ./box-ps.ps1 -InFile $in_script_short_name -OutFile $out_script_short_name

# move sandbox results out of container
docker cp "$container_id:/opt/box-ps/$out_script_short_name" $out_json_path
echo "[+] moved sandbox results from container to $out_json_path"

# kill container
docker kill $container_id > /dev/null
echo "[+] killed container"
