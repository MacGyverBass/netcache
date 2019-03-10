#!/bin/bash
set -e
pageload1=`curl http://www.lagado.com/tools/cache-test --resolve www.lagado.com:80:127.0.0.1`
sleep 5
pageload2=`curl http://www.lagado.com/tools/cache-test --resolve www.lagado.com:80:127.0.0.1`

if [ "$pageload1" == "$pageload2" ]; then
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[32m";fi # 32=Green
	echo "Succesfully Cached"
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[0m";fi # Return to normal color text
	exit 0
else
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[31m";fi # 31=Red
	echo "Error caching test page, pages differed"
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[0m";fi # Return to normal color text
	exit -1
fi
