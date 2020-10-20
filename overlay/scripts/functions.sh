#!/bin/bash
set -e
############################################################
#                                                          #
# NetCache Entrypoint Script Functions                     #
#                                                          #
# This file only has functions for the entrypoint script.  #
#                                                          #
############################################################


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
fnSplitStrings () { # Removes comments, splits into lines from comma/space delimited strings, and removes any blank lines.
 echo "$1" |sed "s/[, ]*#.*$//;s/[, ]/\n/g" |sed "/^$/d"
}
fnTerminate () { # Executes when CTRL+C is pressed in an interactive terminal (-it) or when SIGTERM is received when running as a daemon process
 echo
 echo_msg "* Exiting..." "info"
 if [ -e "/run/named/named.pid" ];then
  echo_msg "+ Stopping bind..."
  kill -QUIT "$(cat "/run/named/named.pid")" && rm "/run/named/named.pid"
 fi
 if [ -e "/run/sniproxy/sniproxy.pid" ];then
  echo_msg "+ Stopping sniproxy..."
  kill -QUIT "$(cat "/run/sniproxy/sniproxy.pid")" && rm "/run/sniproxy/sniproxy.pid"
 fi
 if [ -e "/run/nginx.pid" ];then
  echo_msg "+ Stopping nginx..."
  /usr/sbin/nginx -c /etc/nginx/nginx.conf -s quit # Graceful Shutdown
 fi
 echo_msg "* Finished." "info"
 exit 0
}
trap 'fnTerminate' SIGINT  # CTRL+C
trap 'fnTerminate' SIGTERM # docker stop


############################################################
# Functions that generate the configuration files
addServiceComment () { # addServiceComment "Service Name" "Comment String"
 ServiceName="$1" # Name of the given service.
 Comment="$2" # String
 Cache_DB_File="/etc/bind/cache/cache.db"
 Path_Conf_File="/etc/nginx/conf.d/20_proxy_cache_path.conf"
 RPZ_DB_File="/etc/bind/cache/rpz.db"
 Maps_Conf_File="/etc/nginx/conf.d/maps.d/${ServiceName}.conf"
 # Append the comment(s) to each generated configuration file.
 echo "${Comment}" |sed "s/^/; /" |tee -a "${Cache_DB_File}" "${RPZ_DB_File}" >/dev/null
 echo "${Comment}" |sed "s/^/# /" |tee -a "${Path_Conf_File}" "${Maps_Conf_File}" >/dev/null
}
addServiceSectionComment () { # addServiceSectionComment "Service Name" "Comment String"
 ServiceName="$1" # Name of the given service.
 Comment="$2" # String
 RPZ_DB_File="/etc/bind/cache/rpz.db"
 Maps_Conf_File="/etc/nginx/conf.d/maps.d/${ServiceName}.conf"
 # Append the comment(s) to each generated configuration file.
 echo "${Comment}" |sed "s/^/; /" >> "${RPZ_DB_File}"
 echo "${Comment}" |sed "s/^/# /" >> "${Maps_Conf_File}"
}
addService_DNS () { # addService_DNS "Service Name" "Service-IP" "Domains"
 ServiceName="$1" # Name of the given service.
 ServiceIPs="$2" # String containing the destination IP to be given back to the client PC.
 Domains="$3" # String containing domain name entries, comma/space delimited.

 if [ -z "${ServiceName}" ]||[ -z "${ServiceIPs}" ]||[ -z "${Domains}" ];then # All fields are required.
  return
 fi

 if [ "${ServiceName}" == "${TEST_DNS}" ];then # Add a comment for the DNS diagnostic service
  echo "; Diagnostic service for DNS testing" |tee -a /etc/bind/cache/cache.db /etc/bind/cache/rpz.db >/dev/null
 elif ! grep -q " IN CNAME ${ServiceName}.${RPZ_ZONE}.;$" "/etc/bind/cache/rpz.db";then # Increment intDNS once per service
  let ++intDNS
 fi

 # Bind CNAME(s)
 fnSplitStrings "${Domains}" |sed "s/$/ IN CNAME ${ServiceName}.${RPZ_ZONE}.;/" >> /etc/bind/cache/rpz.db
 # Bind IP(s)
 fnSplitStrings "${ServiceIPs}" |sed "s/^.*$/${ServiceName} IN A \0;/" >> /etc/bind/cache/cache.db
}
addService_CacheMaps () { # addService_Cache "Service Name" "Domains"
 ServiceName="$1" # Name of the given service.
 Domains="$2" # String containing domain name entries, comma/space delimited.

 if [ -z "${ServiceName}" ]||[ -z "${Domains}" ];then # All fields are required.
  return
 fi

 # Nginx service maps
 fnSplitStrings "${Domains}" |sed "s/^.*$/    \0 ${ServiceName};/" >> "/etc/nginx/conf.d/maps.d/${ServiceName}.conf"
}
addService_CachePath () { # addService_Cache "Service Name"
 ServiceName="$1" # Name of the given service.

 if [ -z "${ServiceName}" ];then # All fields are required.
  return
 fi

 # Setup and create the service-specific cache directory
 Service_Cache_Path="/data/cache/${ServiceName}"
 mkdir -p "${Service_Cache_Path}"

 # Nginx proxy_cache_path entries
 if ! grep -q " keys_zone=${ServiceName}:" "/etc/nginx/conf.d/20_proxy_cache_path.conf";then # Check to see if this proxy_cache_path has already been appended.
  if [ "${ServiceName}" == "${DEFAULT_CACHE}" ];then # Add a comment for the default cache service
   echo "# Fallback default cache service" >> "/etc/nginx/conf.d/20_proxy_cache_path.conf"
  else # Increment the intCache
   let ++intCache
  fi
  CacheMemSize="${ServiceName^^}CACHE_MEM_SIZE"; CacheMemSize="${!CacheMemSize}"; CacheMemSize="${CacheMemSize:-"${CACHE_MEM_SIZE}"}"
  InactiveTime="${ServiceName^^}INACTIVE_TIME"; InactiveTime="${!InactiveTime}"; InactiveTime="${InactiveTime:-"${INACTIVE_TIME}"}"
  CacheDiskSize="${ServiceName^^}CACHE_DISK_SIZE"; CacheDiskSize="${!CacheDiskSize}"; CacheDiskSize="${CacheDiskSize:-"${CACHE_DISK_SIZE}"}"
  echo "proxy_cache_path ${Service_Cache_Path} levels=2:2 keys_zone=${ServiceName}:${CacheMemSize} inactive=${InactiveTime} ${CacheDiskSize:+"max_size=${CacheDiskSize}"} loader_files=1000 loader_sleep=50ms loader_threshold=300ms use_temp_path=off;" >> "/etc/nginx/conf.d/20_proxy_cache_path.conf"
 fi
}
addService () { # addService "Service Name" "Service-IP" "Domains"
 ServiceName="$1" # Name of the given service.
 ServiceIPs="$2" # String containing the destination IP to be given back to the client PC.
 Domains="$3" # String containing domain name entries, comma/space delimited.

 addService_CachePath "${ServiceName}"
 addService_CacheMaps "${ServiceName}" "${Domains}"
 addService_DNS "${ServiceName}" "${ServiceIPs}" "${Domains}"
}


############################################################
# Function for displaying the addition of a service
echoAddingService () { # echoAddingService "Service Name" "Service-IP"
 ServiceName="$1" # Name of the given service.
 ServiceIPs="$2" # String containing the destination IP to be given back to the client PC.

 if [ "${DISABLE_HTTP_CACHE,,}" != "true" ]&&[ "${DISABLE_DNS_SERVER,,}" != "true" ];then
  echo "+ Adding \"${ServiceName}\" DNS/Cache service.  Will resolve to: ${ServiceIPs}"
 elif [ "${DISABLE_HTTP_CACHE,,}" == "true" ]&&[ "${DISABLE_DNS_SERVER,,}" != "true" ];then
  echo "+ Adding \"${ServiceName}\" DNS service.  Will resolve to: ${ServiceIPs}"
 elif [ "${DISABLE_HTTP_CACHE,,}" != "true" ]&&[ "${DISABLE_DNS_SERVER,,}" == "true" ];then
  echo "+ Adding \"${ServiceName}\" Cache service."
 fi
}

############################################################
# Convert Raw Bytes into More Human Readable Text Values
awkHumanReadable () {
        awk '{split("K M G T P E Z Y", v);s=0;while( $1>1024 ){ $1/=1024; s++ } print int($1) v[s] }'
}
echoHumanReadableSpeeds () {
        echo "$(echo "${1%%.*}" |awkHumanReadable)Bps ($(expr ${1%%.*} \* 8 |awkHumanReadable)bps)"
}

############################################################
