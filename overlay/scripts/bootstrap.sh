#!/bin/bash
set -e
if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[96m";fi # Colorize the banner (96=Light Cyan)
cat << 'BANNER'

_____   __    ______________            ______
___  | / /______  /__  ____/_____ _________  /______
__   |/ /_  _ \  __/  /    _  __ `/  ___/_  __ \  _ \
_  /|  / /  __/ /_ / /___  / /_/ // /__ _  / / /  __/
/_/ |_/  \___/\__/ \____/  \__,_/ \___/ /_/ /_/\___/

BANNER
if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[0m";fi # Return to normal color text


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
fnTailLog () { # fnTailLog "Prefix text" "File to log in background" [ "Regular Expression" "Replacement String" ... ]
 Prefix="$1" # String to prefix on each line
 LogFile="$2" # File to log (in background)
 PrefixColor="\e[1m"
 ResetColor="\e[0m"
 if [ "${NO_COLORS,,}" == "true" ];then
  tail -f "${LogFile}" |awk "{print \"${Prefix}: \" \$0}" &
 else
  AwkScript="gsub(/^/, \"${PrefixColor}${Prefix}: ${ResetColor}\");"
  while [ $# -ge 4 ];do # Check for a RegExp and String pair
   RegExp="$3" # Regular Expression
   Replacement="${4//\"/\\\"}" # Replacement String
   AwkScript="${AwkScript} gsub(${RegExp},\"${Replacement}\");"
   shift 2 # Shift the arguments by two before checking for another pair.
  done
  tail -f "${LogFile}" |awk "{${AwkScript} print}" &
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
# Start by verifying that UPSTREAM_DNS is provided.
if [ -z "${UPSTREAM_DNS}" ];then
 echo_msg "# UPSTREAM_DNS environment variable is not set.  This is required to be set." "error"
 exit 1
fi

# Create destination paths before generating configuration files
mkdir -p /data/logs/named /data/cache
chown named:named /data/logs/named
chown nginx:nginx /data/cache

# Clear logs if requested
if [ "${CLEAR_LOGS,,}" == "true" ];then
 echo_msg "* Clearing previous log files"
 rm -f /data/logs/*.log /data/logs/named/*.log
fi

# Create nginx/sniproxy log files if they don't yet exist.
touch /data/logs/{cache,cache_error,sniproxy,sniproxy_error}.log

# Create empty 20_proxy_cache_path.conf file.
rm -f /etc/nginx/conf.d/20_proxy_cache_path.conf
touch /etc/nginx/conf.d/20_proxy_cache_path.conf


# Setup DNS Entries
DNS_List="$(fnSplitStrings "${UPSTREAM_DNS}")"
echo "${DNS_List}" |sed "s/^/+ Adding nameserver: /"
DNS_String="$(echo "${DNS_List}" |paste -sd ' ' - )" # Space delimited DNS IPs for sniproxy.conf and resolver.conf and named.conf.options
## Setup /etc/resolv.conf
echo "${DNS_List}" |sed "s/^/nameserver /" > /etc/resolv.conf
## Setup nginx resolver.conf
echo "  resolver ${DNS_String} ipv6=off;" > /etc/nginx/sites-available/conf.d/resolver.conf
## Setup /etc/sniproxy/sniproxy.conf
sed "s/\${DNS_NAMESERVERS}/${DNS_String}/Ig" /etc/sniproxy/sniproxy.conf.template > /etc/sniproxy/sniproxy.conf
## Setup /etc/bind/named.conf.options
DNSSEC_Validation="no"
if [ "${ENABLE_DNSSEC_VALIDATION,,}" == "true" ];then
 echo_msg "* Enabling DNSSEC Validation (dnssec-validation=auto)"
 DNSSEC_Validation="auto"
elif [ "${ENABLE_DNSSEC_VALIDATION,,}" == "enforce" ];then
 echo_msg "* Enabling DNSSEC Validation (dnssec-validation=yes)"
 DNSSEC_Validation="yes"
fi
sed "s/\${DNS_NAMESERVERS}/${DNS_String// /;}/Ig;s/\${DNSSEC_VALIDATION}/${DNSSEC_Validation}/Ig" /etc/bind/named.conf.options.template > /etc/bind/named.conf.options


# Setup Bind
## Generate /etc/bind/named.conf.logging
Logging_Channels="default general database security config resolver xfer-in xfer-out notify client unmatched queries network update dispatch dnssec lame-servers"
echo "logging {" > /etc/bind/named.conf.logging
for channel_type in ${Logging_Channels};do
 cat << SECTION >> /etc/bind/named.conf.logging
    channel ${channel_type}_file {
        file "/data/logs/named/${channel_type}.log" versions 3 size 5m;
        severity dynamic;
        print-time yes;
    };
    category ${channel_type} {
        ${channel_type}_file;
    };
SECTION
 touch "/data/logs/named/${channel_type}.log" && chown named:named "/data/logs/named/${channel_type}.log"
done
echo "};" >>  /etc/bind/named.conf.logging


# Setup NGinx
## Setup /etc/nginx/workers.conf 
echo "worker_processes ${NGINX_WORKER_PROCESSES};" > /etc/nginx/workers.conf
## Setup /etc/nginx/sites-available/root.d/20_cache.conf
sed "s/\${CACHE_MAX_AGE}/${CACHE_MAX_AGE}/g" /etc/nginx/sites-available/root.d/20_cache.conf.template > /etc/nginx/sites-available/root.d/20_cache.conf
## Setup /etc/nginx/conf.d/30_maps.conf with default cache name
sed "s/\${DEFAULT_CACHE}/${DEFAULT_CACHE}/g" /etc/nginx/conf.d/30_maps.conf.template > /etc/nginx/conf.d/30_maps.conf
## Cleanup files from a container restart
rm -f /etc/nginx/conf.d/maps.d/*.conf

# Setup Bind RPZ Zone and Start of Authority Resource Record (SOA RR)
SOA_Serial=`date +%Y%m%d%H` #yyyymmddHH (year,month,day,hour)
sed "s/\${RPZ_ZONE}/${RPZ_ZONE}/Ig;s/\${SOA_Serial}/${SOA_Serial}/Ig" /etc/bind/cache/cache.db.template > /etc/bind/cache/cache.db
sed "s/\${RPZ_ZONE}/${RPZ_ZONE}/Ig" /etc/bind/cache.conf.template > /etc/bind/cache.conf
cp /etc/bind/cache/rpz.db.template /etc/bind/cache/rpz.db


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
# Intialize the variable for counting the number of enabled services
intServices=0
intCache=0
intDNS=0


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
# Add a fallback default cache service in case a domain entry does not match
if [ "${DISABLE_HTTP_CACHE,,}" != "true" ];then
 echo_msg "* Adding fallback default cache."
 addService_CachePath "${DEFAULT_CACHE}" # Just the Cache Path needs to be set for the default service.
fi

# UK-LANs Cache-Domain Lists
if [ "${DISABLE_DNS_SERVER,,}" != "true" ]||[ "${DISABLE_HTTP_CACHE,,}" != "true" ]&&[ ! -z "${CACHE_DOMAINS_REPO}" ];then
 if [ -d "/data/cache-domains/.git" ]&&[ "${CACHE_DOMAINS_REPO}" != "$(git -C "/data/cache-domains" remote get-url origin)" ];then
  echo_msg -n "* Repository URL has changed.  Clearing repo directory..."
  rm -rf "/data/cache-domains"
  echo_msg "  Done." "info"
 fi
 if [ ! -d "/data/cache-domains/.git" ];then
  echo_msg "* Cloning branch ${CACHE_DOMAINS_BRANCH} in repository from ${CACHE_DOMAINS_REPO}"
  git clone -b "${CACHE_DOMAINS_BRANCH}" "${CACHE_DOMAINS_REPO}" "/data/cache-domains" # Download repo/branch
 else
  echo_msg "* Updating branch ${CACHE_DOMAINS_BRANCH} in repository from ${CACHE_DOMAINS_REPO}"
  git -C "/data/cache-domains" fetch # Update repo
  git -C "/data/cache-domains" checkout "${CACHE_DOMAINS_BRANCH}" # Change to branch
  git -C "/data/cache-domains" reset --hard # Reset any files that were changed locally
  git -C "/data/cache-domains" clean -df # Remove any untracked files
  git -C "/data/cache-domains" merge # Merge files with remote repo
 fi
 echo_msg "* Adding repository services..."
 while IFS=$'\t' read -r Service_Name Service_Desc Service_Domain_Files;do
  if [ -z "${ONLYCACHE}" ];then # "ONLYCACHE" variable is not provided, so check for "DISABLE_${SERVICE}" variable and store it's value.
   Disabled="DISABLE_${Service_Name^^}"; Disabled="${!Disabled}"
  elif [[ " ${ONLYCACHE^^} " == *" ${Service_Name^^} "* ]];then # "ONLYCACHE" contains this service.
   Disabled="false"
  else # "ONLYCACHE" is not blank and this service was not found within the "ONLYCACHE" variable.
   Disabled="true"
  fi
  if [ "${Disabled,,}" != "true" ];then
   let ++intServices
   Cache_IP="${Service_Name^^}CACHE_IP"; Cache_IP="${!Cache_IP}"; Cache_IP="${Cache_IP:-"${LANCACHE_IP}"}"
   if [ -z "${Cache_IP}" ]&&[ "${DISABLE_DNS_SERVER,,}" != "true" ];then # Cache_IP not provided
    echo_msg "# ${Service_Name^^}CACHE_IP not provided.  Service not added." "warning"
   else
    echoAddingService "${Service_Name}" "${Cache_IP}"
    addServiceComment "${Service_Name}" "${Service_Name}"
    if [ ! -z "${Service_Desc}" ]&&[ "${Service_Desc}" != "null" ];then
     addServiceComment "${Service_Name}" "${Service_Desc}"
    fi
    while read -r -d $'\t' domain_file || [ -n "${domain_file}" ];do
     addServiceSectionComment "${Service_Name}" " (${domain_file})"
     addService "${Service_Name}" "${Cache_IP}" "$(cat "/data/cache-domains/${domain_file}")"
    done <<<"${Service_Domain_Files}"
   fi
  fi
 done < <(jq -r '.cache_domains[] | "\(.name)\t\(.description)\t\(.domain_files | join("\t"))"' "/data/cache-domains/cache_domains.json")
fi


# Custom Domain Lists
if [ "${DISABLE_DNS_SERVER,,}" != "true" ]||[ "${DISABLE_HTTP_CACHE,,}" != "true" ]&&[ ! -z "${CUSTOMCACHE}" ];then
 echo_msg "* Adding custom services..."
 for Service_Name in ${CUSTOMCACHE};do
  let ++intServices
  Cache_IP="${Service_Name^^}CACHE_IP"; Cache_IP="${!Cache_IP}"; Cache_IP="${Cache_IP:-"${LANCACHE_IP}"}"
  Cache_Domains="${Service_Name^^}CACHE"; Cache_Domains="${!Cache_Domains}"
  if [ -z "${Cache_IP}" ]&&[ -z "${Cache_Domains}" ]&&[ "${DISABLE_DNS_SERVER,,}" != "true" ];then # No domains and Cache_IP not provided
   echo_msg "# ${Service_Name^^}CACHE_IP and ${Service_Name^^}CACHE not provided.  Service not added." "warning"
  elif [ -z "${Cache_IP}" ]&&[ "${DISABLE_DNS_SERVER,,}" != "true" ];then # Cache_IP not provided (but domains were provided)
   echo_msg "# ${Service_Name^^}CACHE_IP not provided.  Service not added." "warning"
  elif [ -z "${Cache_Domains}" ];then # Domains not provided (but either DNS server is disabled or Cache_IP was provided)
   echo_msg "# ${Service_Name^^}CACHE not provided.  Service not added." "warning"
  else
   echoAddingService "${Service_Name}" "${Cache_IP}"
   addServiceComment "${Service_Name}" "${Service_Name}"
   addService "${Service_Name}" "${Cache_IP}" "${Cache_Domains}"
  fi
 done
fi


############################################################
# Add a diagnostic service for DNS tests
Diag_IP="${TEST_DNS^^}CACHE_IP"; Diag_IP="${!Diag_IP}"; Diag_IP="${Diag_IP:-"${LANCACHE_IP}"}"
if [ "${DISABLE_DNS_SERVER,,}" != "true" ]&&[ ! -z "${Diag_IP}" ];then
 addService_DNS "${TEST_DNS}" "${Diag_IP}" "dns.test"
 echo_msg "* Adding DNS Diagnostic service."
fi

# Notify if the user selected to disable all programs or if none of the services were started.
if [ "${DISABLE_HTTP_CACHE,,}" == "true" ]&&[ "${DISABLE_HTTPS_PROXY,,}" == "true" ]&&[ "${DISABLE_DNS_SERVER,,}" == "true" ];then
 echo_msg "* Nothing to run.  Please check your variables provided. (DISABLE_HTTP_CACHE, DISABLE_HTTPS_PROXY, DISABLE_DNS_SERVER)" "warning"
 exit 0
elif [ "${DISABLE_HTTP_CACHE,,}" != "true" ]&&[ "${DISABLE_DNS_SERVER,,}" != "true" ]&&[ "${intCache}" == "0"  ]&&[ "${intDNS}" == "0" ];then
 echo_msg "# No DNS/Cache services enabled.  Please check your configuration.  Verify that you have the correct variables applied to this docker." "error"
 echo_msg "# Note that at a minimum, LANCACHE_IP=\"IP Address\" is required for DNS.  Check the documentation for more information." "error"
 exit 1
elif [ "${DISABLE_HTTP_CACHE,,}" != "true" ]&&[ "${intCache}" == "0"  ];then
 echo_msg "# No Cache services enabled.  Please check your configuration.  Verify that you have the correct variables applied to this docker." "error"
 exit 1
elif [ "${DISABLE_DNS_SERVER,,}" != "true" ]&&[ "${intDNS}" == "0" ];then
 echo_msg "# No DNS services enabled.  Please check your configuration.  Verify that you have the correct variables applied to this docker." "error"
 echo_msg "# Note that at a minimum, LANCACHE_IP=\"IP Address\" is required for DNS.  Check the documentation for more information." "error"
 exit 1
fi

# Enable all Nginx configurations found in sites-available...
mkdir -p /etc/nginx/sites-enabled
if [ "$(ls /etc/nginx/sites-available/*.conf 2>/dev/null |wc -l)" != "0" ];then # Check for files in /etc/nginx/sites-available
 # Copy found sites-available as symbolic links to sites-enabled
 cp -s /etc/nginx/sites-available/*.conf /etc/nginx/sites-enabled/
fi

# Notify the user of how many services were enabled
if [ "${DISABLE_DNS_SERVER,,}" != "true" ];then
 Message_Level="info";if [ "${intDNS}" != "${intServices}" ];then Message_Level="warning";fi
 echo_msg "* DNS Services enabled: ${intDNS}/${intServices}" "${Message_Level}"
fi
if [ "${DISABLE_HTTP_CACHE,,}" != "true" ];then
 Message_Level="info";if [ "${intCache}" != "${intServices}" ];then Message_Level="warning";fi
 echo_msg "* Cache Service enabled: ${intCache}/${intServices}" "${Message_Level}"
fi


############################################################
# Startup programs w/logging
## Bind
if [ "${DISABLE_DNS_SERVER,,}" != "true" ];then
 # Test the Bind configuration
 echo_msg "* Checking Bind9 configuration"
 if ! /usr/sbin/named-checkconf -z /etc/bind/named.conf ;then
  echo_msg "# Problem with Bind9 configuration" "error"
 else
  # Display logs and Execute Bind
  echo_msg "* Running Bind9 w/logging" "info"
  fnTailLog "named/general" /data/logs/named/general.log
  fnTailLog "named/queries" /data/logs/named/queries.log "/ ([0-9]{1,3}\.){3}[0-9]{1,3}#/" "\e[95m&\e[0m" "/#\e\[0m/" "\e[0m#"
  /usr/sbin/named -u named -c /etc/bind/named.conf
 fi
fi
## SNI Proxy
if [ "${DISABLE_HTTPS_PROXY,,}" != "true" ];then
 # Display logs and Execute SNI Proxy
 echo_msg "* Running SNI Proxy w/logging" "info"
 fnTailLog "sniproxy" /data/logs/sniproxy.log "/ ([0-9]{1,3}\.){3}[0-9]{1,3}/" "\e[95m&\e[0m" "/:[0-9]* ->\e\[95m/" "&\e[0m" "/\e\[95m\e\[0m/" "" "/:443 -> ([0-9]{1,3}\.){3}[0-9]{1,3}/" "\e[96m&\e[0m" "/\e\[96m:443 ->/" ":443 ->\e[96m"
 fnTailLog "sniproxy_error" /data/logs/sniproxy_error.log
 /usr/sbin/sniproxy -c /etc/sniproxy/sniproxy.conf
fi
## Nginx
if [ "${DISABLE_HTTP_CACHE,,}" != "true" ];then
 # Check permissions on /data folder...
 echo_msg -n "* Checking permissions (This may take a long time if the permissions are incorrect on large caches)..."
 find /data/cache \! -user nginx -exec chown nginx:nginx '{}' +
 echo_msg "  Done." "info"
 # Test the nginx configuration...
 echo_msg "* Checking nginx configuration"
 if ! /usr/sbin/nginx -t -c /etc/nginx/nginx.conf ;then
  echo_msg "# Problem with nginx configuration" "error"
 else
  # Display logs and Execute Nginx
  echo_msg "* Running NGinx w/logging" "info"
  fnTailLog "cache" /data/logs/cache.log "/ ([0-9]{1,3}\.){3}[0-9]{1,3} /" "\e[95m&\e[0m" '/"MISS"/' '"\e[93mMISS\e[0m"' '/"HIT"/' '"\e[92mHIT\e[0m"'
  fnTailLog "cache_error" /data/logs/cache_error.log
  /usr/sbin/nginx -c /etc/nginx/nginx.conf
 fi
fi

# Wait for this process to receive a signal. (SIGINT/SIGTERM)
wait $!

