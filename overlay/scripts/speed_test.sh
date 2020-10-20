#!/bin/bash
set -e
############################################################
# Load Functions From External File
. /scripts/functions.sh

############################################################
# Check to see if the HTTP cache is enabled
if [ "${DISABLE_HTTP_CACHE,,}" == "true" ];then
	echo_msg "DISABLE_HTTP_CACHE is set to true.  Nothing to test." "warning"
	exit 0
fi

SpeedTest="curl -o /dev/null -w %{speed_download} http://speedtest.wdc01.softlayer.com/downloads/test10.zip --silent"
SpeedTestResolve="--resolve speedtest.wdc01.softlayer.com:80:127.0.0.1"

if echo "Downloading directly..." && speed_download1=`${SpeedTest}` && echo "Downloading to cache... (if not already in cache)" && speed_download2=`${SpeedTest} ${SpeedTestResolve}` && echo "Pulling from cache..." && speed_download2=`${SpeedTest} ${SpeedTestResolve}`;then
	echo "Regular speed: $(echoHumanReadableSpeeds "${speed_download1}")"
	echo "Cache speed:   $(echoHumanReadableSpeeds "${speed_download2}")"
	let speed_increase=${speed_download2%%.*}/${speed_download1%%.*}
	echo "Speed increase of ${speed_increase}x"
else
	echo_msg "There was an error when trying to download the test file." "warning"
	exit 1
fi

