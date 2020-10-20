#!/bin/bash
set -e
############################################################
# Load Functions From External File
. /scripts/functions.sh

############################################################
# Check to see if the DNS server is enabled
if [ "${DISABLE_DNS_SERVER,,}" == "true" ];then
	echo_msg "DISABLE_DNS_SERVER is set to true.  Nothing to test." "warning"
	exit 0
fi

# Create temporary chroot directory for nslookup
mkdir -p "/tmp/chroot_nslookup/bin"
cp -p "$(which nslookup)" "/tmp/chroot_nslookup/bin"
ldd "$(which nslookup)" |sed "1d;s/^\t//;s/^.* => //;s/ .*$//" |while read lib;do
 mkdir -p "/tmp/chroot_nslookup/$(dirname "${lib}")"
 cp -p "${lib}" "/tmp/chroot_nslookup${lib}"
done

# Run nslookup in the chroot (thus ignoring the local /etc/resolv.conf file)
if chroot "/tmp/chroot_nslookup" "/bin/nslookup" "dns.test" 2>/dev/null;then
	echo_msg "Successfully Redirected DNS Lookup" "info"
	exit 0
else
	echo_msg "Error looking up test DNS entry." "error"
	exit -1
fi

