#!/bin/bash

# pulls down the most recent box-ps docker images and uses it to sandbox the given powershell script
# in a network-isolated environment

usage1="docker-box-ps.sh <powershell script path> <output JSON file path>"
usage2="docker-box-ps.sh <powershell script path> -d <output analysis dir>"
usage3="<script content> | docker-box-ps.sh -p <output JSON file path>"
usage4="<script content> | docker-box-ps.sh -p -d <output analysis dir>"

# argument validation
if [[ "$#" -lt 2 ]] && [[ "$#" -gt 3 ]]
then
	echo "[-] two or three arguments required. $# provided"
	echo "[-] usage 1: $usage1"
	echo "[-] usage 2: $usage2"
	echo "[-] usage 3: $usage3"
	echo "[-] usage 4: $usage4"
	exit -1
fi

if [[ "$#" -eq 3 ]] && [[ $2 != "-d" ]]
then
	echo "[-] usages for three arguments..."
	echo $usage2
	echo $usage4 
	exit -1
fi

if [[ $1 != "-p" ]] && [[ ! -f $1 ]]
then
	echo "[-] input file does not exist"
	exit -1
fi

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
	docker exec $container_id pwsh ./box-ps.ps1 -InFile "./infile.ps1" -OutDir "./outdir"

	# remove the output dir if it exists
	if [[ -d $3 ]]
	then
		rm -r $3
	fi

	docker cp "$container_id:/opt/box-ps/outdir" $3

# user just wants the JSON report
else
	docker exec $container_id pwsh ./box-ps.ps1 -InFile "./infile.ps1" -OutFile "./outfile.json"
	docker cp "$container_id:/opt/box-ps/outfile.json" $2
	echo "[+] moved analysis report from container to $2"
fi

# kill container
docker kill $container_id > /dev/null
echo "[+] killed container"
