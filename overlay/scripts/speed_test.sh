#!/bin/bash
set -e
# Check to see if the HTTP cache is enabled
if [ "${DISABLE_HTTP_CACHE,,}" == "true" ];then
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[33m";fi # 33=Yellow
	echo "DISABLE_HTTP_CACHE is set to true.  Nothing to test."
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[0m";fi # Return to normal color text
	exit 0
fi

SpeedTest="curl -o /dev/null -w %{speed_download} http://speedtest.wdc01.softlayer.com/downloads/test10.zip --silent"
SpeedTestResolve="--resolve speedtest.wdc01.softlayer.com:80:127.0.0.1"

awkHumanReadable () {
	awk '{split("K M G T P E Z Y", v);s=0;while( $1>1024 ){ $1/=1024; s++ } print int($1) v[s] }'
}
echoHumanReadableSpeeds () {
	echo "$(echo "${1%%.*}" |awkHumanReadable)Bps ($(expr ${1%%.*} \* 8 |awkHumanReadable)bps)"
}

if echo "Downloading directly..." && speed_download1=`${SpeedTest}` && echo "Downloading to cache... (if not already in cache)" && speed_download2=`${SpeedTest} ${SpeedTestResolve}` && echo "Pulling from cache..." && speed_download2=`${SpeedTest} ${SpeedTestResolve}`;then
	echo "Regular speed: $(echoHumanReadableSpeeds "${speed_download1}")"
	echo "Cache speed:   $(echoHumanReadableSpeeds "${speed_download2}")"
	let speed_increase=${speed_download2%%.*}/${speed_download1%%.*}
	echo "Speed increase of ${speed_increase}x"
else
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[33m";fi # 33=Yellow
	echo "There was an error when trying to download the test file."
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[0m";fi # Return to normal color text
	exit 1
fi

