FROM	alpine:latest
LABEL	maintainer="Steven Bass"

ENV	CACHE_DOMAINS_REPO="https://github.com/uklans/cache-domains.git"	\
	ENABLE_DNSSEC_VALIDATION="false"	\
	NGINX_WORKER_PROCESSES="auto"	\
	DISABLE_DNS_SERVER="false"	\
	DISABLE_HTTP_CACHE="false"	\
	DISABLE_HTTPS_PROXY="false"	\
	UPSTREAM_DNS="1.1.1.1 1.0.0.1"	\
	RPZ_ZONE="NetCache"	\
	CACHE_MAX_AGE="3650d"	\
	INACTIVE_TIME="365d"	\
	CACHE_MEM_SIZE="250m"	\
	CACHE_DISK_SIZE=""	\
	NO_COLORS="false"	\
	CLEAR_LOGS="false"	\
	ONLYCACHE=""	\
	CUSTOMCACHE=""	\
	LANCACHE=""

RUN	apk --no-cache add	\
		bash	\
		curl	\
		jq	\
		git	\
		bind	\
		nginx	\
		sniproxy

COPY	overlay/ /

RUN	mkdir -m 755 -p /data	\
	&& rm /etc/nginx/conf.d/default.conf	\
	&& mkdir -p /var/cache/bind /etc/bind/cache /etc/nginx/conf.d/maps.d	\
	&& chown named:named /var/cache/bind	\
	&& chmod 755 /scripts/*

EXPOSE	53/udp 80 443

VOLUME	["/data"]

WORKDIR	/scripts

ENTRYPOINT	["/scripts/bootstrap.sh"]

