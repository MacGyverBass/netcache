#!/bin/bash
# Create temporary chroot directory for nslookup
mkdir -p "/tmp/chroot_nslookup/bin"
cp -p "$(which nslookup)" "/tmp/chroot_nslookup/bin"
ldd "$(which nslookup)" |sed -n "s/^\t\(\/[^ ]*\) .*$/\1/p" |while read lib;do
 mkdir -p "/tmp/chroot_nslookup/$(dirname "${lib}")"
 cp -p "${lib}" "/tmp/chroot_nslookup${lib}"
done

# Run nslookup in the chroot (thus ignoring the local /etc/resolv.conf file)
chroot "/tmp/chroot_nslookup" "/bin/nslookup" "dns.test" 2>/dev/null
Result=$?

# Clean up the temporary chroot directory
rm -rf "/tmp/chroot_nslookup"

# Display the result
if [ ${Result} -eq 0 ];then
 echo "Successfully Redirected DNS Lookup"
 exit 0
else
 echo "Error looking up test DNS entry."
 exit -1
fi

