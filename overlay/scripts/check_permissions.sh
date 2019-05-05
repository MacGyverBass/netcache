#!/bin/bash

############################################################
# Helpful Functions
echo_msg () { # echo_msg "Text to display" "Type of message (info/warning/error)"
 EchoArg=""
 if [[ "$1" == "-"* ]];then # Check for any echo-related arguments to pass to the echo in this function.
  EchoArg="$1"
  shift
 fi
 Text="$1" # String
 Level="$2" # Level (info/warning/error)
 if [ "${NO_COLORS,,}" == "true" ];then
  echo ${EchoArg} "${Text}"
 else
   if [ "${Level}" == "info" ];then
  echo -en "\e[32m" # 32=Green
   elif [ "${Level}" == "warning" ];then
  echo -en "\e[33m" # 33=Yellow
  elif [ "${Level}" == "error" ];then
   echo -en "\e[31m" # 31=Red
  else
   echo -en "\e[36m" # 36=Cyan
  fi
  echo ${EchoArg} "${Text}"
  echo -en "\e[0m"
 fi
}
############################################################

# Check permissions on /data folder...
echo_msg -n "* Checking permissions (This may take a long time if the permissions are incorrect on large caches)..."
find /data/cache \! -user nginx -exec chown nginx:nginx '{}' +
echo_msg "  Done." "info"

