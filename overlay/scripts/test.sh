#!/bin/bash
set -e

Pass=true
if ! /scripts/dns_test.sh;then Pass=false;fi
if ! /scripts/cache_test.sh;then Pass=false;fi
if ! /scripts/https_test.sh;then Pass=false;fi
echo
if ${Pass};then
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[32m";fi # 32=Green
	echo "Successfully passed all tests"
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[0m";fi # Return to normal color text
	exit 0
else
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[31m";fi # 31=Red
	echo "Failed tests"
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[0m";fi # Return to normal color text
	exit 1
fi

