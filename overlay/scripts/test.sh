#!/bin/bash
set -e
############################################################
# Load Functions From External File
. /scripts/functions.sh

############################################################
Pass=true
if ! /scripts/dns_test.sh;then Pass=false;fi
if ! /scripts/cache_test.sh;then Pass=false;fi
if ! /scripts/https_test.sh;then Pass=false;fi
echo
if ${Pass};then
	echo_msg "Successfully passed all tests" "info"
	exit 0
else
	echo_msg "Failed tests" "error"
	exit 1
fi

