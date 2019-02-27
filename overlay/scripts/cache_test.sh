#!/bin/bash
set -e
pageload1=`curl http://www.lagado.com/tools/cache-test --resolve www.lagado.com:80:127.0.0.1`
sleep 5
pageload2=`curl http://www.lagado.com/tools/cache-test --resolve www.lagado.com:80:127.0.0.1`

if [ "$pageload1" == "$pageload2" ]; then
	echo "Succesfully Cached"
	exit 0
else
	echo "Error caching test page, pages differed"
	exit -1
fi
