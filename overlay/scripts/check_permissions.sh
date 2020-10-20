#!/bin/bash
set -e
############################################################
# Load Functions From External File
. /scripts/functions.sh

############################################################
# Check permissions on /data folder...
echo_msg -n "* Checking permissions (This may take a long time if the permissions are incorrect on large caches)..."
find /data/cache \! -user nginx -exec chown nginx:nginx '{}' +
echo_msg "  Done." "info"

