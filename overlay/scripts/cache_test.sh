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

TEST_HTTP_CACHE_DOMAIN="njrusmc.net"
TEST_HTTP_CACHE_PATH="/cache/rand128k_public.test"

TempLoad1="$(mktemp)"
TempLoad2="$(mktemp)"
CacheTest="curl http://${TEST_HTTP_CACHE_DOMAIN}${TEST_HTTP_CACHE_PATH} --silent --location --resolve ${TEST_HTTP_CACHE_DOMAIN}:80:127.0.0.1 --resolve ${TEST_HTTP_CACHE_DOMAIN}:443:127.0.0.1"

echo "Using Test URL:  http://${TEST_HTTP_CACHE_DOMAIN}${TEST_HTTP_CACHE_PATH}"
echo "Please wait..."
if `${CacheTest} --output ${TempLoad1}` && sleep 5 && `${CacheTest} --output ${TempLoad2}`;then # Load URL, wait 5 seconds, load URL again.
	if diff -q "${TempLoad1}" "${TempLoad2}" >/dev/null; then # Check if pages match
		echo_msg "Succesfully Cached" "info"
		ExitCode="0"
	else # Pages did not match
		echo_msg "Error caching test page, pages differed" "error"
		ExitCode="2"
	fi
else # Failed to load the pages
	echo_msg "Error caching test page, make sure the HTTP cache is running" "error"
	ExitCode="1"
fi
rm ${TempLoad1} ${TempLoad2}
exit ${ExitCode}

