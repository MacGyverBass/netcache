# Set base image for image.
FROM	alpine:latest

# Apply image labels
LABEL	maintainer="Steven Bass"

# Set default environmental variables
ENV	CACHE_DOMAINS_REPO="https://github.com/uklans/cache-domains.git"	\
	CACHE_DOMAINS_BRANCH="master"	\
	ENABLE_DNSSEC_VALIDATION="false"	\
	NGINX_WORKER_PROCESSES="auto"	\
	DISABLE_DNS_SERVER="false"	\
	DISABLE_HTTP_CACHE="false"	\
	DISABLE_HTTPS_PROXY="false"	\
	UPSTREAM_DNS="1.1.1.1 1.0.0.1"	\
	DEFAULT_CACHE="_default_"	\
	TEST_DNS="dnsdiagnostic"	\
	RPZ_ZONE="NetCache"	\
	CACHE_MAX_AGE="3650d"	\
	INACTIVE_TIME="365d"	\
	CACHE_MEM_SIZE="250m"	\
	CACHE_DISK_SIZE=""	\
	NO_COLORS="false"	\
	CLEAR_LOGS="false"	\
	LOGROTATE_CPULIMIT="50"	\
	LOGROTATE_INTERVAL="weekly"	\
	LOGROTATE_COUNT="16"	\
	ONLYCACHE=""	\
	CUSTOMCACHE=""	\
	LANCACHE_IP=""

# Install required packages.
RUN	apk --no-cache --repository http://dl-cdn.alpinelinux.org/alpine/v3.7/main add jq~=1.5	\
	&& apk --no-cache add	\
		bash	\
		curl	\
		git	\
		bind	\
		nginx	\
		sniproxy	\
		cpulimit	\
		logrotate

# Copy the pre-made files into the image.
COPY	overlay/ /

# Create the necessary folders with the required permissions and cleanup default files.
RUN	mkdir -m 755 -p /data	\
	&& rm /etc/nginx/conf.d/default.conf	\
	&& mkdir -p /var/cache/bind /etc/bind/cache /etc/nginx/conf.d/maps.d	\
	&& chown named:named /var/cache/bind	\
	&& chmod 755 /scripts/*.sh	\
	&& chmod 755 /etc/periodic/*/*

# Exposed ports:
# Port 53 (DNS) is used by bind.
# Port 80 (HTTP) is used by nginx.
# Port 443 (HTTPS) is used by sniproxy.
EXPOSE	53/udp 53/tcp 80/tcp 443/tcp

# This is the shared data folder, which will store the cache data, cache-domains lists, and logs.
# It is recommended to mount this folder to the host machine so it does not get lost if the container is removed.
VOLUME	["/data"]

# Set the default working directory to the /scripts/ folder.
WORKDIR	/scripts

# Set bootstrap.sh as the entrypoint.
ENTRYPOINT	["/scripts/bootstrap.sh"]

