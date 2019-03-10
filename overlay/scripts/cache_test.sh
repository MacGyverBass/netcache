#!/bin/bash
set -e
# Check to see if the HTTP cache is enabled
if [ "${DISABLE_HTTP_CACHE,,}" == "true" ];then
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[33m";fi # 33=Yellow
	echo "DISABLE_HTTP_CACHE is set to true.  Nothing to test."
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[0m";fi # Return to normal color text
	exit 0
fi

CacheTest="curl http://www.lagado.com/tools/cache-test --silent --resolve www.lagado.com:80:127.0.0.1"

echo "Please wait..."
if pageload1=`${CacheTest}` && sleep 5 && pageload2=`${CacheTest}`;then # Load page, wait 5 seconds, load page again.
	if [ "${pageload1}" == "${pageload2}" ]; then # Check if pages match
		if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[32m";fi # 32=Green
		echo "Succesfully Cached"
		if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[0m";fi # Return to normal color text
		exit 0
	else # Pages did not match
		if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[31m";fi # 31=Red
		echo "Error caching test page, pages differed"
		if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[0m";fi # Return to normal color text
		exit -1
	fi
else # Failed to load the pages
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[33m";fi # 33=Yellow
	echo "Error caching test page, make sure the HTTP cache is running"
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[0m";fi # Return to normal color text
	exit 1
fi

