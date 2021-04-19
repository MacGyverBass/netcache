#!/bin/bash
set -e
############################################################
# Load Functions From External File
. /scripts/functions.sh

############################################################
# Check to see if the HTTPS proxy is enabled
if [ "${DISABLE_HTTPS_PROXY,,}" == "true" ];then
	echo_msg "DISABLE_HTTPS_PROXY is set to true.  Nothing to test." "warning"
	exit 0
fi

echo "Using Test URL:  http://${TEST_HTTPS_PROXY_DOMAIN}${TEST_HTTPS_PROXY_PATH}"
echo "Please wait..."

if curl -s https://${TEST_HTTPS_PROXY_DOMAIN}${TEST_HTTPS_PROXY_PATH} --location --resolve ${TEST_HTTPS_PROXY_DOMAIN}:80:127.0.0.1 --resolve ${TEST_HTTPS_PROXY_DOMAIN}:443:127.0.0.1 >/dev/null ;then
	echo_msg "Succesfully Proxied" "info"
	exit 0
else
	echo_msg "Error accessing HTTPS test page" "error"
	exit -1
fi

