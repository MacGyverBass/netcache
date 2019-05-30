#!/bin/bash

Log_Files=(/data/logs/{named/general,named/queries,sniproxy,sniproxy_error,cache,cache_error}.log)
if [ "${NO_COLORS,,}" == "true" ];then
 tail -v -F -n0 ${Log_Files[*]} |awk -f filename_prefix.awk -e '/./{print}'
else
 tail -v -F -n0 ${Log_Files[*]} |awk -f filename_prefix.awk -f colorize.awk -e '/./{print}'
fi

