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
# Load Functions From External File
. /scripts/functions.sh

############################################################
# Announce the version of Alpine we are using
echo_msg "* Running on Alpine $(cat /etc/alpine-release)"

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
chown nginx:nginx /data/logs/{cache,cache_error}.log
chown sniproxy:sniproxy /data/logs/{sniproxy,sniproxy_error}.log

# Create configuration files for logrotate
cat << EOF > /etc/logrotate.schedule.conf
# rotate log files (daily/weekly/monthly/yearly)
${LOGROTATE_INTERVAL}

# number of backlogs to keep
rotate ${LOGROTATE_COUNT}
EOF

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
        file "/data/logs/named/${channel_type}.log";
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
# Intialize the variable for counting the number of enabled services
intServices=0
intCache=0
intDNS=0


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
# Startup programs
echo_msg "* Launching processes..."
## Cron
echo_msg "* Running crond (for logrotate)" "info"
crond -L /var/log/messages
## Bind
if [ "${DISABLE_DNS_SERVER,,}" != "true" ];then
 # Test the Bind configuration
 echo_msg "* Checking Bind9 configuration"
 if ! /usr/sbin/named-checkconf -z /etc/bind/named.conf ;then
  echo_msg "# Problem with Bind9 configuration" "error"
 else
  # Execute Bind
  echo_msg "* Running Bind9" "info"
  /usr/sbin/named -u named -c /etc/bind/named.conf
 fi
fi
## SNI Proxy
if [ "${DISABLE_HTTPS_PROXY,,}" != "true" ];then
 # Execute SNI Proxy
 echo_msg "* Running SNI Proxy" "info"
 /usr/sbin/sniproxy -c /etc/sniproxy/sniproxy.conf
fi
## Nginx
if [ "${DISABLE_HTTP_CACHE,,}" != "true" ];then
 # Test the nginx configuration...
 echo_msg "* Checking nginx configuration"
 if ! /usr/sbin/nginx -t -c /etc/nginx/nginx.conf ;then
  echo_msg "# Problem with nginx configuration" "error"
 else
  # Execute Nginx
  echo_msg "* Running NGinx" "info"
  /usr/sbin/nginx -c /etc/nginx/nginx.conf
 fi
fi

# Display Logs
echo_msg "* Starting Logging"
/scripts/view_logs.sh &

# Wait for this process to receive a signal. (SIGINT/SIGTERM)
wait $!

