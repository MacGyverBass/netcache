#!/bin/bash
set -e
# Check to see if the HTTPS proxy is enabled
if [ "${DISABLE_HTTPS_PROXY,,}" == "true" ];then
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[33m";fi # 33=Yellow
	echo "DISABLE_HTTPS_PROXY is set to true.  Nothing to test."
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[0m";fi # Return to normal color text
	exit 0
fi

if curl -s https://www.howsmyssl.com/a/check --resolve www.howsmyssl.com:443:127.0.0.1 >/dev/null ;then
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[32m";fi # 32=Green
	echo "Succesfully Proxied"
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[0m";fi # Return to normal color text
	exit 0
else
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[31m";fi # 31=Red
	echo "Error accessing HTTPS test page"
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[0m";fi # Return to normal color text
	exit -1
fi

