# Network Cache DNS/HTTP/HTTPS Docker Container

```txt
_____   __    ______________            ______
___/ | / /______/ /__/ ____/_____ _________/ /______
__/  |/ /_/ _ \/ __/  /    _/ __ `// ___/_/ __ \/ _ \
_/ /|  / /  __/ /_ / /___  / /_/ // /__ _  / / /  __/
/_/ |_/  \___/\__/ \____/  \__,_/ \___/ /_/ /_/\___/

```

## Introduction

This docker container provides a DNS server, a NGINX caching proxy server, and a SNI Proxy server for caching common CDN services.  For any network with more than one PC gamer downloading/updating games or more than one Windows PC downloading updates, this will drastically reduce internet bandwidth consumption.

This project is based off the work of [SteamCache-DNS](https://github.com/steamcache/steamcache-dns), [SteamCache](https://github.com/steamcache/steamcache)/[Generic](https://github.com/steamcache/generic)/[Monolithic](https://github.com/steamcache/monolithic), as well as [SNI Proxy](https://github.com/steamcache/sniproxy).  Please check out their [GitHub Page](https://github.com/steamcache/) for more information.

This project is a combination of my previous two projects, [NetCache-DNS](https://github.com/macgyverbass/netcache-dns) and [NetCache-Proxy](https://github.com/macgyverbass/netcache-proxy).  Those projects re-invented the process of grabbing a list of known CDN services from [uklans/cache-domains](https://github.com/uklans/cache-domains) and starting a DNS redirection server and a HTTP/HTTPS cache/proxy server for those services.

This also aims to be compatible with the same environmental variables, thus being a potential drop-in replacement, but adding additional options.  However, the cache paths & cache keys are not backwards compatible and will need to be rebuilt.  Please remember this if you are running a non-netcache caching server before switching to netcache.

In this project, an [Alpine](https://alpinelinux.org/) base image was used instead of Ubuntu to keep the resulting image size lower and more lightweight.  Additionally, all three services (Bind, NGINX, and SNI Proxy) are all executed within this container, thus eliminating the need to execute them from yet another docker.

The primary use case is gaming events, such as LAN parties, which need to be able to cope with hundreds or thousands of computers receiving an unannounced patch - without spending a fortune on internet connectivity. Other uses include smaller networks, such as Internet Cafes and home networks, where the new games are regularly installed on multiple computers; or multiple independent operating systems on the same computer.

This container is designed to support any game that uses HTTP and also supports HTTP range requests (used by Origin). This should make it suitable for:

- Steam (**Valve**)
- Origin (**EA Games**)
- Riot Games (League of Legends)
- Battle.net (**Blizzard**, Hearthstone, Starcraft 2, Overwatch)
- Frontier Launchpad (Elite Dangerous, Planet Coaster)
- Uplay (**Ubisoft**)
- Windows Updates

Note that caching of the above services is not guaranteed, as the service may switch to a HTTPS update server.  However, services could switch to HTTP when the DNS resolves to a RFC1918 private address, thus allowing caching to occur, which it currently appears Riot has done.

## Key Differences Between NetCache and Other Network-Caching Docker Solutions

- More streamlined setup.  Combines bind, nginx, and sniproxy into one container for quick and easy setups.
- Smaller image size.  Uses Alpine as it's base, thus leading to a very small installation footprint.
- Custom domain caching.  Provides the `CUSTOMCACHE` variable for providing additional CDN domains not currently listed in uklans/cache-domains.
- Faster uklans/cache-domains setup.  Uses git to clone/fetch the latest repository of service domain names.
- Colorized output to terminal.  Basic color-coding added for better informing you of warnings/errors during script execution.
- Cleaner logging to terminal.  Logs displayed in `docker logs` (or in an attached on-screen view) are prefixed to quickly identify the log file currently being appended.
- Quicker shutdown/exit.  Uses a set of trap commands to catch `ctrl+c` and the `docker stop` command, which send `SIGINT` and `SIGTERM` to the script, which calls a function to gracefully shutdown bind, nginx, and sniproxy.

## Quick Explanation

For this LAN cache to function on your network you only need this service.  Previously, separate Docker services were required to perform DNS redirection, HTTP caching, and HTTPS proxying.  This Docker images brings all those abilities together.

The caching service transparently proxies your requests for content to Steam/Origin/etc, or serves the content to you if it already has it.

The special DNS service handles DNS queries normally (recursively), except when the query is for a cached service and in that case it responds that the caching service should be used.

## Regarding HTTPS/SSL and Origin

Some publishers, including Origin, use the same hostnames we're replacing for HTTPS content as well as HTTP content. We can't cache HTTPS traffic, so SNI Proxy will be used to forward traffic on port 443.

This container comes with SNI Proxy built-in and runs alongside nginx, so while you do not need to run another docker container for sniproxy, you still need to publish the HTTPS port in addition to the HTTP port when launching docker.

This runs the SNI Proxy on the same IP address as nginx.  Any HTTPS traffic will be forwarded directly to it's destination.

## Usage

The quickest way to start up this Docker service is as follows:

```sh
docker run -d --name netcache -e LANCACHE_IP="10.0.0.10" -p "10.0.0.10:53:53/udp" -p "10.0.0.10:53:53" -p "10.0.0.10:80:80" -p "10.0.0.10:443:443" -v /netcache:/data macgyverbass/netcache:latest
```

Which can be re-written using variables to make it clearer and easier to update:

```sh
Container_Name="netcache"
LAN_IP="10.0.0.10"
docker run -d --name ${Container_Name} -e LANCACHE_IP="${LAN_IP}" -p "${LAN_IP}:53:53/udp" -p "${LAN_IP}:53:53" -p "${LAN_IP}:80:80" -p "${LAN_IP}:443:443" -v /netcache:/data macgyverbass/netcache:latest
```

The above commands runs netcache detached (in the background) on the host system IP address 192.168.0.100 for ports 53 (DNS), 80 (HTTP), and 443 (HTTPS), with cache/logs saved to `/netcache` on the host.  Please make sure no other services are using these ports on your machine for this to work.  If you are already running services on those ports, you can setup another IP address on your host system and use that new IP address in the example above.

For the cache & log files to persist you will need to mount a directory on the host machine into the container. You can do this using `-v <path on host>:/data`.
Cache folders are created within `/data/cache` for each CDN service.  (Example: `/data/cache/steam`) -- This prevents any possible cross-CDN collisions and allows for easier disk-space usage or organization between the different service caches.

For example, you may decide to dedicate a single drive to steam, but cache all other CDNs onto another drive; you can even set your system up to cache the content on drives dedicated to each service.

Note that you can still run services on a dedicated systems with alternate IP addresses.  You can specify a different IP for each service hosted within the cache; for a full list of supported services have a look at the [GitHub uklans/cache-domains Page](https://github.com/uklans/cache-domains). Set the IP for a service using `${SERVICE}CACHE_IP` environment.  For example:

```conf
LANCACHE_IP="10.0.0.10" # Default for any services without a custom ${SERVICE}CACHE_IP entry.

BLIZZARDCACHE_IP="10.0.0.11"
FRONTIERCACHE_IP="10.0.0.12"
ORIGINCACHE_IP="10.0.0.13"
RIOTCACHE_IP="10.0.0.14"
STEAMCACHE_IP="10.0.0.15"
UPLAYCACHE_IP="10.0.0.16"
```

Note that the destination IP addresses should also be running a Docker container capable of HTTP caching & HTTPS proxying.

You can also disable any of the services by setting the environment variable of `DISABLE_${SERVICE}=true`.  For example:

```conf
DISABLE_BLIZZARD=true
DISABLE_RIOT=true
DISABLE_UPLAY=true
```

## Additional Options for Custom Services

Custom services may be added using the variable CUSTOMCACHE and hosts may be specified using just the service name as a variable.

```conf
CUSTOMCACHE=MyCDN
MYCDNCACHE=cdn.example.com
```

This may also be used for ${SERVICE}CACHE_IP (mentioned previously) to specify different IP addresses for each service hosted.

```conf
CUSTOMCACHE=MyCDN
MYCDNCACHE=cdn.example.com
MYCDNCACHE_IP=10.0.0.21
```

Multiple custom services may also be added by adding unique prefixes the CUSTOMCACHE.

```conf
CUSTOMCACHE=MyCDN MyGameCDN MyBackupCDN
MYCDNCACHE=cdn.example.com
MYCDNCACHE_IP=10.0.0.21
MYGAMECDNCACHE=gamecdn.example.com
MYGAMECDNCACHE_IP=10.0.0.22
MYBACKUPCDNCACHE=backupcdn.example.com
MYBACKUPCDNCACHE_IP=10.0.0.23
```

Note that, like any Docker service, these values may either be provided in the command itself or referenced from a env file.  For example, this command has multiple custom services and may be hard to read:

```sh
Container_Name="netcache"
LAN_IP="10.0.0.10"
docker run -d --name ${Container_Name} -e LANCACHE_IP="${LAN_IP}" -p "${LAN_IP}:53:53/udp" -p "${LAN_IP}:53:53" -p "${LAN_IP}:80:80" -p "${LAN_IP}:443:443" -v /netcache:/data -e CUSTOMCACHE="MyCDN MyGameCDN MyBackupCDN" -e MYCDNCACHE="cdn.example.com" -e MYCDNCACHE_IP="10.0.0.21" -e MYGAMECDNCACHE="gamecdn.example.com" -e MYGAMECDNCACHE_IP="10.0.0.22" -e MYBACKUPCDNCACHE="backupcdn.example.com" -e MYBACKUPCDNCACHE_IP="10.0.0.23" macgyverbass/netcache:latest
```

You may also reference these environmental variables from a env file.

```sh
Container_Name="netcache"
LAN_IP="10.0.0.10"
# Command line to execute that loads "MySetup.env"
docker run -d --name ${Container_Name} --env-file="MySetup.env" -p "${LAN_IP}:53:53/udp" -p "${LAN_IP}:53:53" -p "${LAN_IP}:80:80" -p "${LAN_IP}:443:443" -v /netcache:/data
```

```conf
# Example env file referenced above
LANCACHE_IP=10.0.0.10
CUSTOMCACHE=MyCDN MyGameCDN MyBackupCDN
MYCDNCACHE=cdn.example.com
MYCDNCACHE_IP=10.0.0.21
MYGAMECDNCACHE=gamecdn.example.com
MYGAMECDNCACHE_IP=10.0.0.22
MYBACKUPCDNCACHE=backupcdn.example.com
MYBACKUPCDNCACHE_IP=10.0.0.23
```

## Restricting to Specific Services

The ONLYCACHE variable was added to quickly specify specific services to use from the [uklans/cache-domains](https://github.com/uklans/cache-domains) list.  For example:

```conf
ONLYCACHE=hirez steam windowsupdates
```

The above example would cache the hirez, steam, and windowsupdates services from the uklans/cache-domains list.

This option was primarily added for debugging purposes, so one or more space-delimited services could be tested at a time without needing to heavily rewrite the command/script.  However this option may be useful to others testing their setups or for smaller setups.

Note that specifying a service in ONLYCACHE will thus ignore the matching `DISABLE_${Service}=true` entry.

For example, both DISABLE_ORIGIN=true and ONLYCACHE=origin are specified, but it will still setup caching for only Origin:

```conf
DISABLE_ORIGIN=true
ONLYCACHE=origin
```

## Custom Upstream DNS

By default, the upstream DNS servers are set to Cloudflare's 1.1.1.1 (and 1.0.0.1) servers.  You may also use your own upstream DNS server (or servers) using the `UPSTREAM_DNS` variable:

```sh
Container_Name="netcache"
LAN_IP="10.0.0.10"
docker run -d --name ${Container_Name} -e LANCACHE_IP="${LAN_IP}" -p "${LAN_IP}:53:53/udp" -p "${LAN_IP}:53:53" -p "${LAN_IP}:80:80" -p "${LAN_IP}:443:443" -e UPSTREAM_DNS="8.8.8.8 8.8.4.4" macgyverbass/netcache:latest
```

This will add a forwarder for all requests not served/cached by netcache to be sent to the upstream DNS server, in this case Google's DNS servers.  You may also point this to another DNS on your network, such as one that catches advertisement domain names or malicious domain names.  For example, if you have another DNS server running on `10.0.0.5`, your argument would be `-e UPSTREAM_DNS="10.0.0.5"`.

This supports multiple upstream DNS servers, separated by spaces.

## Monitoring

Access logs are written to `/data/logs` inside the container.  They are tailed by default in the main window when the container is launched.  These log files can also be accessed if the `/data` volume it mounted to a given path.

You can run the following command on the host machine to view the current container output, which tails the bind, nginx, and sniproxy log files.

```sh
Container_Name="netcache"
docker logs -f ${Container_Name}
```

## Log Rotation

Log files will be rotated on a weekly basis using logrotate.  This is executed automatically using crond with CPU usage limited to 50%.

Note that if you are updating from a previous version of NetCache, some leftover Bind log files may still exist in `/data/logs/named/` and will not be automatically removed.  They can be identified by having a `.log.0` or `.log.1` or `.log.2` suffix and can be safely deleted, if you no longer need to review their contents.

Rotated log files will be compressed and logrotate will keep up to 16 of these files before being automatically deleted.

The above CPU limit and schedule can be modified by providing the following environmental variables:

* LOGROTATE_CPULIMIT
* LOGROTATE_INTERVAL
* LOGROTATE_COUNT

For example, to limit CPU usage to 25% and have the logs rotate monthly, keeping a backlog of 4 files, use the below environmental variables:

```conf
LOGROTATE_CPULIMIT="25"
LOGROTATE_INTERVAL="monthly"
LOGROTATE_COUNT="4"
```

Valid values for `LOGROTATE_CPULIMIT` are between 0 and 200.  Valid values for `LOGROTATE_INTERVAL` are "daily", "weekly", "montly", and "yearly".  `LOGROTATE_COUNT` should be 0 (zero) or higher.  If `LOGROTATE_COUNT` is 0, old versions are removed rather than rotated.

## Testing/Debugging

There are three scripts included for testing bind DNS redirection, nginx HTTP caching and sniproxy HTTPS forwarding.  These are called `dns_test.sh`, `cache_test.sh` and `https_test.sh`.

They can be executed while the docker is running:

```sh
Container_Name="netcache"
# Check bind DNS redirection:
docker exec -it ${Container_Name} /scripts/dns_test.sh
# Check nginx HTTP caching:
docker exec -it ${Container_Name} /scripts/cache_test.sh
# Check sniproxy HTTPS forwarding:
docker exec -it ${Container_Name} /scripts/https_test.sh
```

Additionally, you may want to test the speed of your cache versus a regular download.  Execute `speed_test.sh` in the same manner as above to download a 10MB file and test the results using regular downloading and using cached downloading.  Note that the cached speed will likely score higher than your network connection, as it is being ran within the image itself, but it should give a basic test of your cache setup.

The script `test.sh` is also included to test the DNS Server, HTTP Cache, and HTTPS Proxy all in sequence.  It will display success/failure message in addition to the individual test script output messages.  It gives an exit code of 0 (zero) upon success, and 1 (one) upon failure; this may later be used as part of the Docker Health-Check feature.

## Repairing Ownership Permissions on the /data/cache Folder

Originally, the /data/cache folder was checked each time the image started, however this is now omitted and provided as an external script.  This change was made as the execution of this permissions check would take a long time to complete, especially with a large amount of cached data, thus slowing down image startup.  In most setups, this check is not required if the mounted folder is never modified from an external source.

If you want to verify/fix your cache folder, execute `check_permissions.sh` within the /scripts folder.  This script can either be ran after the image has started normally or the script can be ran directly without executing the rest of the image.

To run the script after the image has started, use `docker exec` to run the script as shown below:

```sh
Container_Name="netcache"
docker exec -it ${Container_Name} /scripts/check_permissions.sh
```

To run the script directly, you may run it as shown below:

```sh
docker run --rm -it -v /netcache:/data --entrypoint /scripts/check_permissions.sh macgyverbass/netcache:latest 
```

The above command bypasses the normal startup script and only runs the permissions check script.  This may be necessary if the permissions of your destination path have changed drastically.  In the example above, once the script completes, the docker instance will automatically stop and be removed.

Note that under normal usage, this script should not be necessary to be ran.  Only external modifications to the /data/cache folder (such as editing files in your mounted folder from the host or another docker image) would possibly modify the ownership on these files.  If you never attempt to access/modify the files in your mounted folder, the ownership permissions should never be incorrect.  However, this script is still provided if you believe your mounted cache folder has incorrect permissions, as that will prevent this image from running correctly.

## Advice to Publishers

If you are a games publisher and you like LAN parties, gaming centers and other places to be able to easily cache your game updates, we recommend the following:

- If your content downloads are on HTTPS, you can do what Riot has done - try and resolve a specific hostname. If it resolves to a RFC1918 private address, switch your downloads to use HTTP instead.
- Try to use hostnames specific for your HTTP download traffic.
- Tell us the hostnames that you're using for your game traffic.  We're maintaining a list at [uklans/cache-domains](https://github.com/uklans/cache-domains) and we'll accept pull requests!
- Have your client verify the files and ensure the file it downloaded matches the file it **should** have downloaded. This cache server acts as a man-in-the-middle so it would be good to ensure the files are correct.

If you need any further advice, please contact [uklans.net](https://www.uklans.net/) for help.

## Tuning Your Cache

Steam in particular has some inherent limitations caused by the adherence to the HTTP spec connection pool. As such, Steam download speeds are highly dependent on the latency between your server and the Steam CDN servers.  In the event you find your initial download speed with the default settings is slow, this can be resolved by allocating more IP addresses to your cache.  We suggest adding one IP at a time to see how much gain can be had (4 seems to work for a number of people).

### Step 1: Adding IP Addresses to Your Docker Host

Consult your OS documentation in order to add additional IP addresses onto your docker cache host machine.

### Step 2: Adding IP Addresses to Your Cache Container

In order for this to work you need to add the port maps to your docker run command.

- Using `-p 80:80 -p 443:443` should be sufficient as per the documentation.  Do note that this will bind to all available IP addresses on your host OS.
- You may also bind just the specific IP addresses accordingly by using multiple publish commands.  For example, you may use `-p 10.10.1.11:80:80 -p 10.10.1.11:443:443 -p 10.10.1.12:80:80 -p 10.10.1.12:443:443` to your docker run command.

### Step 3: Informing netcache of the Extra IP Addresses

Finally we need to inform netcache that these services are now available on multiple IP addresses.  This can be done on the command line using the following command `-e LANCACHE_IP="10.10.1.11 10.10.1.12"`.  Note the quotes surrounding the multiple IP addresses.

If you are using alternate IP addresses for specific services, such as in a multi-server setup, you can use the `${Service}CACHE_IP` specific entries for this as well.  For example, if you run your Steam cache on 10.10.1.21 and added 10.10.1.22 to that machine, you can use `-e STEAMCACHE_IP="10.10.1.21 10.10.1.22"` in your docker run command.

### Step 4: Testing

Using Steam as an example, choose a game which has not been seen by the cache before (or clear your `/data/cache` folder) and start it downloading.  Check to see what the maximum speed seen by your Steam client is.  If necessary repeat steps 1-3 with additional IPs until you see a download equivalent to your uncached Steam client or no longer see an improvement vs the previous IP allocation.

## Special Usage

This Docker service will cache all CDN services (defined in the [uklans cache-domains repo](https://github.com/uklans/cache-domains) so multiple instances are not required.  However, you can execute multiple instances of this Docker container to function as independent services.

There are three special environmental variables available to control execution of this script:

- `DISABLE_DNS_SERVER` (Default: "false"): Disables starting bind.
- `DISABLE_HTTP_CACHE` (Default: "false"): Disables starting nginx.
- `DISABLE_HTTPS_PROXY` (Default: "false"): Disables starting sniproxy.

For example, you may want to only run the DNS server portion of this container and skip running nginx and sniproxy.  To do this, you can provide `DISABLE_HTTP_CACHE=true` and `DISABLE_HTTPS_PROXY=true` when launching the container.  From there, you can run an alternate HTTP cache service and HTTPS proxy service.

Also, you may want to run a separate HTTP cache & HTTPS proxy on a separate machine, while running the DNS elsewhere.  To disable just the DNS server, you would provide `DISABLE_DNS_SERVER=true` when launching the container.  From there, you can startup your DNS server on your other machine and point to this computer.

<details><summary>Click to hide/show examples</summary>

```sh
# Computer A - Operating as just a DNS redirection server on IP 10.0.0.10
Container_Name="netcache-dns"
ComputerA_IP="10.0.0.10"
ComputerB_IP="10.0.0.11"
docker run -d --name ${Container_Name} -e LANCACHE_IP="${ComputerB_IP}" -p "${ComputerA_IP}:53:53/udp" -p "${ComputerA_IP}:53:53" -v /netcache:/data -e DISABLE_HTTP_CACHE="true" -e DISABLE_HTTPS_PROXY="true" macgyverbass/netcache:latest

# Computer B - Operating as just a HTTP cache & HTTPS proxy server on IP 10.0.0.11
Container_Name="netcache-lancache"
ComputerB_IP="10.0.0.11"
docker run -d --name ${Container_Name} -e LANCACHE_IP="${ComputerB_IP}" -p "${ComputerB_IP}:80:80" -p "${ComputerB_IP}:443:443" -v /netcache:/data -e DISABLE_DNS_SERVER="true" macgyverbass/netcache:latest
```

A slightly more advanced example:

```sh
# Computer A - Operating as a full DNS/HTTP/HTTPS server (nothing disabled here) on IP 10.0.0.10
Container_Name="netcache"
ComputerA_IP="10.0.0.10"
ComputerB_IP="10.0.0.11"
docker run -d --name ${Container_Name} -e LANCACHE_IP="${ComputerA_IP}" -p "${ComputerA_IP}:53:53/udp" -p "${ComputerA_IP}:53:53" -p "${ComputerA_IP}:80:80" -p "${ComputerA_IP}:443:443" -v /netcache:/data -e STEAMCACHE_IP="${ComputerB_IP}" macgyverbass/netcache:latest
# Note that STEAMCACHE_IP is provided above.
# This means the above docker will cache everything except Steam content.

# Computer B - Operating as just a HTTP cache & HTTPS proxy server on IP 10.0.0.11
Container_Name="netcache-steam"
ComputerB_IP="10.0.0.11"
docker run -d --name ${Container_Name} -e STEAMCACHE_IP="${ComputerB_IP}" -p "${ComputerB_IP}:80:80" -p "${ComputerB_IP}:443:443" -v /netcache:/data -e DISABLE_DNS_SERVER="true" -e ONLYCACHE="steam" macgyverbass/netcache:latest
# Note that this will end up only caching Steam content which was DNS redirected from Computer A.
```

</details>

These are provided to give flexibility for more complex setups.  For this reason, this same Docker image can be re-used for different functionality.  Any combination of the options may be provided.  Note that if all three variables are set to true, the script will notify you and exit.

## Advanced Options

Many environmental variables are used in this project and most are pre-defined with their default values in the `Dockerfile` itself.  Here are some of the more advanced options not mentioned above.

<details><summary>Click to show/hide the additional environmental variables</summary>

- `CACHE_DOMAINS_REPO` (Default: "`https://github.com/uklans/cache-domains.git`"): This can be set to a custom git URL.  This may come in handy when you do not want to pull from uklans/cache-domains master repository or if you decide to fork it and modify it for your own usage.  Note that if this value is empty `""`, the script will skip cloning/syncing/using the repository.
- `ENABLE_DNSSEC_VALIDATION` (Default: "`false`"): Setting this to "`true`" enables DNSSEC Validation via "`dnssec-validation auto;`".  Setting this to "`enforce`" will enable DNSSEC Validation via "`dnssec-validation yes;`".  Currently, this is disabled by default and explaining this is beyond the scope of this article, but if you want to enable it, please read up first.  For more information, see [BIND DNSSEC Guide](https://ftp.isc.org/isc/dnssec-guide/html/dnssec-guide.html#dnssec-validation-explained) and [Domain Name System Security Extensions (DNSSEC) and BIND | Internet Systems Consortium](https://www.isc.org/downloads/bind/dnssec/).
- `NGINX_WORKER_PROCESSES` (Default: "`auto`"): Defines the max number of nginx workers to create.  The optimal value depends on many factors including (but not limited to) the number of CPU cores, the number of hard disk drives that store data, and load pattern. When one is in doubt, setting it to the number of available CPU cores would be a good start (the value "auto" will try to auto-detect it).  For more information, see [ngx_core_module - worker_processes](https://nginx.org/en/docs/ngx_core_module.html#worker_processes).
- `CACHE_MAX_AGE` (Default: "`3650d`"): Defines how long to keep items in cache.  For more information, see [ngx_http_proxy_module - proxy_cache_valid](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_cache_valid).
- `INACTIVE_TIME` (Default: "`365d`"): Defines how long to keep unused items in cache.  For more information, see [ngx_http_proxy_module - proxy_cache_path](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_cache_path) regarding *`inactive=time`*.
  - This variable also supports service-specific assignment when provided with the service prefixed.  For example: `STEAMINACTIVE_TIME` or `RIOTINACTIVE_TIME`
- `CACHE_MEM_SIZE` (Default: "`250m`"): Defines how much memory each service can allocate.  Please consider adjusting this value when running on systems with lower amounts of RAM.  For more information, see [ngx_http_proxy_module - proxy_cache_path](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_cache_path) regarding *`keys_zone=name:size`*.
  - This variable also supports service-specific assignment when provided with the service prefixed.  For example: `STEAMCACHE_MEM_SIZE` or `RIOTCACHE_MEM_SIZE`
- `CACHE_DISK_SIZE` (Default: ""): Defines how much disk space each service can allocate.  An empty value `""` means it will only start removing old items when the destination is full.  For more information, see [ngx_http_proxy_module - proxy_cache_path](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_cache_path) regarding *`max_size=size`*.
  - This variable also supports service-specific assignment when provided with the service prefixed.  For example: `STEAMCACHE_DISK_SIZE` or `RIOTCACHE_DISK_SIZE`
- `NO_COLORS` (Default: "`false`"): Disables colors in echo/logs on-screen.  (Logs are saved directly without any color formatting.)
- `CLEAR_LOGS` (Default: "`false`"): Clears log files on startup of container.  This clears all log files upon startup of the container.  This can either be useful for debugging or for individuals that prefer their logs to be clean when starting up the container.
- `DEFAULT_CACHE` (Default: "`_default_`"): Defines the folder path to use for the default fallback cache.  This should catch any unmatched domains going through nginx, such as the `cache_test.sh` script.  This may be changed as a personal preference or for debugging.
- `TEST_DNS` (Default: "`dnsdiagnostic`"): Defines the zone name to use when testing the DNS.  When testing `dns.test` using the `dns_test.sh` script, it should resolve to this name.  This may be changed as a personal preference or for debugging.

</details>

## Important Notes If You Run Into Problems

- Environmental variable names provided MUST be in uppercase.  To simplify the script and prevent issues reading lower/upper/mixed-case variable names, a decision was made to make provided environmental variable names uppercase-only.  If you provide lowercase or mixed case variable names, it will not be read.  For example, `STEAMCACHE_IP` will work, but `SteamCache_IP` will not work.
- Forwarding ports using `-p 53:53/udp -p 53:53 -p 80:80 -p 443:443` will work, but if you have multiple IP addresses or adapters, this format will bind to all of them, which may not be the desired outcome.  If you have other services, like a webserver, running on another IP of the same device, it will conflict and prevent the docker from launching.  However, if you only have one IP for the device on one adapter, this may work for you.  Please take this into account when starting docker.
- The `/data` volume does not require binding to a directory, but doing so will keep your cache persistent.  If you prefer to keep your cache persistent, but not the logs, you can bind just the cache directory using `-v /netcache:/data/cache` instead.  Note that the uklans/cache-domains repo is also stored in `/data`, thus to make it persistent separately, you may use `-v /cache-domains:/data/cache-domains` as well.  The examples in this document focus on binding the `/data` folder for simplicity.  Note that if you just prefer clean log files on each docker start, you can provide the `CLEAN_LOGS` variable mentioned in this document.
- While most errors will be caught by the script when it starts up, if they are not a serious error, the script will not exit and thus the docker will be running, but not responding to DNS/HTTP/HTTPS requests.  Either use `docker run -it` instead of `docker run -d` to view the output when starting the image or `docker logs` to review the on-screen information and logs.
- If you run into further problems starting the docker image itself, please review the examples above, check your variables you have provided, and review the [Docker Documentation - Run](https://docs.docker.com/engine/reference/run/) for more help.

## Running on Startup

Follow the instructions in the [Docker Documentation - Starting Containers Automatically](https://docs.docker.com/config/containers/start-containers-automatically/) to run the container at startup.

## Further information

More information can be found at the [SteamCache Homepage](http://steamcache.net) and the [SteamCache GitHub Page](https://github.com/steamcache)

## Thanks

- Based on original container setup from [steamcache/monolithic](https://github.com/steamcache/monolithic).
- Based on original configs from [ti-mo/ansible-lanparty](https://github.com/ti-mo/ansible-lanparty).
- Everyone on [/r/lanparty](https://reddit.com/r/lanparty) who has provided feedback and helped people with this.
- UK LAN Techs for all the support.

## License

[The MIT License (MIT)](LICENSE)

