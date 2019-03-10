#!/bin/bash
set -e
# Check to see if the DNS server is enabled
if [ "${DISABLE_DNS_SERVER,,}" == "true" ];then
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[33m";fi # 33=Yellow
	echo "DISABLE_DNS_SERVER is set to true.  Nothing to test."
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[0m";fi # Return to normal color text
	exit 0
fi

# Create temporary chroot directory for nslookup
mkdir -p "/tmp/chroot_nslookup/bin"
cp -p "$(which nslookup)" "/tmp/chroot_nslookup/bin"
ldd "$(which nslookup)" |sed -n "s/^\t\(\/[^ ]*\) .*$/\1/p" |while read lib;do
 mkdir -p "/tmp/chroot_nslookup/$(dirname "${lib}")"
 cp -p "${lib}" "/tmp/chroot_nslookup${lib}"
done

# Run nslookup in the chroot (thus ignoring the local /etc/resolv.conf file)
if chroot "/tmp/chroot_nslookup" "/bin/nslookup" "dns.test" 2>/dev/null;then
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[32m";fi # 32=Green
	echo "Successfully Redirected DNS Lookup"
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[0m";fi # Return to normal color text
	exit 0
else
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[31m";fi # 31=Red
	echo "Error looking up test DNS entry."
	if [ "${NO_COLORS,,}" != "true" ];then echo -en "\e[0m";fi # Return to normal color text
	exit -1
fi

