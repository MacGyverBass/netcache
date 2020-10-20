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

CacheTest="curl http://www.lagado.com/tools/cache-test --silent --resolve www.lagado.com:80:127.0.0.1"

echo "Please wait..."
if pageload1=`${CacheTest}` && sleep 5 && pageload2=`${CacheTest}`;then # Load page, wait 5 seconds, load page again.
	if [ "${pageload1}" == "${pageload2}" ]; then # Check if pages match
		echo_msg "Succesfully Cached" "info"
		exit 0
	else # Pages did not match
		echo_msg "Error caching test page, pages differed" "error"
		exit -1
	fi
else # Failed to load the pages
	echo_msg "Error caching test page, make sure the HTTP cache is running" "error"
	exit 1
fi

