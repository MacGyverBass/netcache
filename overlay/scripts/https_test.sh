#!/bin/bash
set -e
if curl -s https://www.howsmyssl.com/a/check --resolve www.howsmyssl.com:443:127.0.0.1 >/dev/null ;then
	echo "Succesfully Proxied"
	exit 0
else
	echo "Error accessing HTTPS test page"
	exit -1
fi

