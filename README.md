# Caddy Proxy

![GitHub release (latest by date)](https://img.shields.io/github/v/release/bfren/docker-caddy-proxy) ![Docker Pulls](https://img.shields.io/endpoint?url=https%3A%2F%2Fbfren.dev%2Fdocker%2Fpulls%2Fcaddy-proxy) ![Docker Image Size](https://img.shields.io/endpoint?url=https%3A%2F%2Fbfren.dev%2Fdocker%2Fsize%2Fcaddy-proxy) ![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/bfren/docker-caddy-proxy/build.yml?branch=main)

[Docker Hub](https://hub.docker.com/r/bfren/caddy-proxy) - [Quay.io](https://quay.io/repository/bfren/caddy-proxy) - [bfren ecosystem](https://github.com/bfren/docker)

## Introduction

A reverse proxy for your other containers, built on [Caddy](https://caddyserver.com) and configured using one simple JSON file. Caddy requests and renews Let's Encrypt certificates automatically, using the HTTP challenge or the DNS challenge (via [Hetzner](https://github.com/caddy-dns/hetzner)) for wildcards and private servers.

It is built on [Alpine + S6](https://github.com/bfren/docker-alpine-s6), and adds:

* Caddy, compiled with the Hetzner DNS module
* `bf-proxy`, a Nushell module that turns `conf.json` into Caddy's JSON configuration, with secure defaults
* helper commands to regenerate configuration, manage basic auth users and check or renew certificates

This is the successor to [bfren/nginx-proxy](https://github.com/bfren/docker-nginx-proxy) - see [Migrating from nginx-proxy](#migrating-from-nginx-proxy).

## Quickstart

`docker-compose.yml`:

```yaml
services:
  proxy:
    image: quay.io/bfren/caddy-proxy:2.0
    restart: unless-stopped
    ports:
      - "0.0.0.0:80:80"
      - "0.0.0.0:443:443"
      - "0.0.0.0:443:443/udp"
    environment:
      - BF_PROXY_DOMAIN=proxy.example.com
      - BF_PROXY_LETS_ENCRYPT_EMAIL=you@example.com
      - BF_PROXY_LETS_ENCRYPT_LIVE=0
    volumes:
      - ./ssl:/ssl
      - ./sites:/sites
      - ./www:/www

  app:
    image: traefik/whoami
```

`ssl/conf.json`:

```json
{
    "$schema": "https://raw.githubusercontent.com/bfren/docker-caddy-proxy/main/proxy-conf-schema.json",
    "domains": [
        { "primary": "app.example.com", "aliases": [ "www.app.example.com" ], "upstream": "http://app:80" }
    ]
}
```

Point the DNS records for each host name at your server, run `docker compose up -d`, and check `docker compose logs proxy`. Certificates come from Let's Encrypt's staging server (which browsers don't trust) until you set `BF_PROXY_LETS_ENCRYPT_LIVE=1` - do that once everything works, because the live server is rate limited.

## Features

* 🔒 Automatic HTTPS - certificates are requested and renewed for every host name, and HTTP is redirected to HTTPS
* 🌐 HTTP or DNS challenge per domain, with wildcard certificates and CNAME delegation for domains hosted elsewhere
* 📄 One `conf.json` file, with a JSON schema for validation and autocomplete
* ⚖️ Multiple upstreams with load balancing, extra routes (proxy, redirect or static files) per path
* 🛡️ Secure headers, optional TLS 1.3 only, HTTP basic auth, and AI training crawlers blocked by default
* 🗜️ zstd / gzip compression, HTTP/3 and WebSockets
* 🔧 Maintenance page when an upstream is down
* 🔄 Optional automatic reload when configuration changes, without dropping connections
* 🧩 Add your own Caddy routes per domain, or take complete control of a domain's configuration
* 🩺 Health check using a local server that isn't logged
* 👤 Caddy runs as `www` (UID 1000), not root

## Tags

Images are published to Docker Hub (`bfren/caddy-proxy`) and Quay.io (`quay.io/bfren/caddy-proxy`) for `linux/amd64`, `linux/arm/v7` and `linux/arm64`.

| Tag       | Example | Use when                                   |
| --------- | ------- | ------------------------------------------ |
| `latest`  |         | You always want the newest image           |
| `MAJOR`   | `2`     | You want updates, but not breaking changes |
| `MINOR`   | `2.0`   | You want fixes only - **recommended**      |
| `VERSION` | `2.0.0` | You want to pin this image exactly         |

## Configuration

### Ports

| Port      | Purpose                                       |
| --------- | --------------------------------------------- |
| `80`      | HTTP challenge, and redirecting HTTP to HTTPS |
| `443`     | HTTPS                                         |
| `443/udp` | HTTP/3 (optional)                             |

Caddy runs as `www` and needs no extra capabilities: Docker lets unprivileged users bind to ports below 1024 inside a container. With `network_mode: host` the host's setting applies instead, so set `net.ipv4.ip_unprivileged_port_start=80` (or lower) on the host.

### Volumes

| Volume   | Purpose                                                                          |
| -------- | -------------------------------------------------------------------------------- |
| `/ssl`   | `conf.json`, `users.json` (basic auth), and Caddy's certificates (`/ssl/caddy`). |
| `/sites` | Per-domain Caddy configuration - see [below](#custom-domain-configuration).      |
| `/www`   | `/www/public` is served for `BF_PROXY_DOMAIN`, with the maintenance page.        |

Everything in the volumes is owned by `www` (UID / GID 1000), and `/ssl` is readable only by its owner. On the host, edit the files as UID 1000 (usually the first user account) or with `sudo`.

### Environment Variables

| Variable                               | Values        | Description                                                     | Default    |
| -------------------------------------- | ------------- | --------------------------------------------------------------- | ---------- |
| `BF_PROXY_DOMAIN`                      | domain        | **Required.** The proxy's domain - unknown hosts redirect here. |            |
| `BF_PROXY_LETS_ENCRYPT_EMAIL`          | email         | **Required.** Let's Encrypt account email.                      |            |
| `BF_PROXY_LETS_ENCRYPT_LIVE`           | `0`, `1`      | Use the live server - `0` uses staging.                         | `0`        |
| `BF_PROXY_USE_INTERNAL_CA`             | `0`, `1`      | Use Caddy's internal (untrusted) CA - for testing.              | `0`        |
| `BF_PROXY_ACME_CHALLENGE`              | `http`, `dns` | Default challenge - can be set per domain.                      | `http`     |
| `BF_PROXY_DNS_PROVIDER`                | `hetzner`     | DNS provider for the DNS challenge.                             | `hetzner`  |
| `BF_PROXY_HETZNER_TOKEN`               | token         | Hetzner API token for the DNS challenge.                        |            |
| `BF_PROXY_DNS_TTL`                     | duration      | TTL of DNS challenge records, e.g. `60s`.                       | provider's |
| `BF_PROXY_DNS_PROPAGATION_DELAY`       | duration      | Wait before a DNS challenge record is checked.                  | `60s`      |
| `BF_PROXY_DNS_PROPAGATION_TIMEOUT`     | duration      | How long to wait for DNS propagation, e.g. `5m`.                |            |
| `BF_PROXY_DNS_RESOLVERS`               | IPs           | Space-separated resolvers to check propagation.                 |            |
| `BF_PROXY_DNS_OVERRIDE_ZONE`           | domain        | Delegate DNS challenges to `<primary>.<zone>`.                  |            |
| `BF_PROXY_SSL_REDIRECT_TO_CANONICAL`   | `0`, `1`      | Default for `redirectToPrimary`.                                | `0`        |
| `BF_PROXY_UPSTREAM_RETRY`              | duration      | Default for `retry` (`0s` to disable).                          | `5s`       |
| `BF_PROXY_AUTO_RELOAD`                 | `0`, `1`      | Regenerate and reload when configuration changes.               | `0`        |
| `BF_PROXY_HARDEN`                      | `0`, `1`      | Allow only TLS 1.3 (older devices may fail).                    | `0`        |
| `BF_PROXY_BLOCK_AI_BOTS`               | `0`, `1`      | Return 403 to AI training crawlers.                             | `1`        |
| `BF_PROXY_ACCESS_LOG`                  | `0`, `1`      | Write access logs to the container output.                      | `0`        |
| `BF_PROXY_CLEAN_INSTALL`               | `0`, `1`      | Delete all configuration and certificates on start.             | `0`        |
| `BF_PROXY_AUTO_PRIMARY`                | domain        | With `BF_PROXY_AUTO_UPSTREAM`, generate a missing `conf.json`.  |            |
| `BF_PROXY_AUTO_UPSTREAM`               | URL           | Upstream for the generated domain.                              |            |
| `BF_PROXY_AUTO_ALIASES`                | names         | Aliases for the generated domain.                               |            |
| `BF_PROXY_AUTO_CUSTOM`                 | `0`, `1`      | Mark the generated domain as `custom`.                          | `0`        |
| `BF_PROXY_MAINTENANCE_REFRESH_SECONDS` | integer       | Maintenance page refresh interval.                              | `6`        |

See [Alpine + S6](https://github.com/bfren/docker-alpine-s6#environment-variables) for `BF_DEBUG`, `BF_TZ` and the other base image variables.

### Build Arguments

| Argument                | Description                | Default                     |
| ----------------------- | -------------------------- | --------------------------- |
| `CADDY_VERSION`         | Caddy release to build.    | `2.11.7`                    |
| `CADDY_HETZNER_VERSION` | caddy-dns/hetzner release. | `2.0.1`                     |
| `CADDY_BUILDER`         | xcaddy build image.        | `caddy:2.11-builder-alpine` |
| `AI_ROBOTS_VERSION`     | ai.robots.txt release.     | `v2.0`                      |

## How It Works

On start-up, `conf.json` is read (or converted from nginx-proxy format, or generated from the `BF_PROXY_AUTO_*` variables), checked, and turned into one Caddy configuration file. Each domain's part is kept in `/sites/<primary>.json`. Caddy then runs under S6. The health check uses a server on `127.0.0.1:2020` with no access log, so it doesn't fill the container log.

### conf.json

Domains are defined in `/ssl/conf.json` - see [`proxy-conf-sample.json`](proxy-conf-sample.json) for an example and [`proxy-conf-schema.json`](proxy-conf-schema.json) for the full definition. Add `$schema` (as in the Quickstart) for validation and autocomplete.

| Property            | Description                                                                    |
| ------------------- | ------------------------------------------------------------------------------ |
| `primary`           | **Required.** The primary domain name.                                         |
| `aliases`           | Other host names - wildcards need the DNS challenge.                           |
| `upstream`          | **Required** (unless `custom`). e.g. `http://app:5000` - a list load balances. |
| `lb`                | Load balancing policy (default `random`) - see below.                          |
| `retry`             | How long to retry an unreachable upstream, e.g. `10s`.                         |
| `challenge`         | `http` or `dns` - defaults to `BF_PROXY_ACME_CHALLENGE`.                       |
| `dnsOverrideDomain` | Where to create DNS challenge records (`""` to disable).                       |
| `redirectToPrimary` | Redirect aliases to the primary domain.                                        |
| `auth`              | Basic auth: `true` for all users, or a list of names.                          |
| `headers`           | Response headers to add or override - `null` stops the proxy adding one.       |
| `routes`            | Extra routes, before the default upstream - see below.                         |
| `compress`          | `false` to turn off compression.                                               |
| `clacks`            | `false` to remove the `X-Clacks-Overhead` header.                              |
| `tlsSkipVerify`     | `true` to accept self-signed `https` upstreams.                                |
| `custom`            | See [below](#custom-domain-configuration).                                     |

`lb` can be `random`, `round_robin`, `least_conn`, `first`, `ip_hash`, `uri_hash` or `client_ip_hash`.

Each route can have a `path` (e.g. `/api/*` - without one it matches everything) and exactly one action:

| Action     | Description                                                        |
| ---------- | ------------------------------------------------------------------ |
| `upstream` | Proxy here (or a list, with `lb`). `stripPrefix` removes a prefix. |
| `redirect` | Redirect here (301, or set `status`). Caddy placeholders work.     |
| `root`     | Serve static files from this (mounted) directory.                  |

```json
"routes": [
    { "path": "/api/*", "upstream": [ "http://api1:8080", "http://api2:8080" ], "lb": "round_robin", "stripPrefix": "/api" },
    { "path": "/old/*", "redirect": "https://example.com/new{http.request.uri.path}" },
    { "path": "/files/*", "root": "/www/files" }
]
```

### Defaults

For every domain:

* HTTP is redirected to HTTPS, and certificates are requested and renewed automatically.
* Responses are compressed with zstd or gzip. Images and other compressed formats, responses under 512 bytes and responses the upstream has already compressed are left alone.
* `Strict-Transport-Security`, `X-Frame-Options`, `X-Content-Type-Options` and `Referrer-Policy` are added, and `X-Clacks-Overhead: GNU Terry Pratchett` - [because he was a legend](http://www.gnuterrypratchett.com).
  To stop one being added, set it to `null` in the domain's `headers` - e.g. `"X-Frame-Options": null` for Vaultwarden, which sets it itself.
* `X-Real-IP` and Caddy's `X-Forwarded-*` headers are sent upstream. WebSockets work automatically.
* If the upstream can't be reached (after `retry`, so a quick restart isn't noticed), or returns 502, 503 or 504, an auto-refreshing maintenance page is shown. It is regenerated on every start, so don't edit `/www/public/maintenance.html`. `index.html` is only created when `/www/public` doesn't exist, so your own is kept.
* Requests for unknown hosts are redirected to `BF_PROXY_DOMAIN`, which serves `/www/public` (static files cached for a year, `/favicon.ico` returning 204 unless you add one).

### AI crawlers

With `BF_PROXY_BLOCK_AI_BOTS=1`, crawlers that collect AI training data get 403 Forbidden. The list comes from [ai.robots.txt](https://github.com/ai-robots-txt/ai.robots.txt) when the image is built, keeping only crawlers whose `function` is training data collection - AI search crawlers, assistants and user-triggered agents (e.g. `OAI-SearchBot`, `ChatGPT-User`) are not blocked. It is saved to `/usr/share/caddy-proxy/ai-bots.txt`.

### Custom domain configuration

Each domain's Caddy configuration is stored in `/sites/<primary>.json`: its `route`, its `errors` route (the maintenance page) and its `tls` policy (including the ACME challenge). What happens to it depends on `custom`:

* `false` (default) - the file is regenerated on every start and by `proxy-regenerate`, so don't edit it. To add to it, put `*.json` files in `/sites/<primary>.d`, each holding a Caddy [route](https://caddyserver.com/docs/json/apps/http/servers/routes/) or an array of routes. They are added after the security headers and basic auth (so they can't bypass them), and before `routes` and the default upstream.
  * Files ending `.before.json` are added first instead - before alias redirects, AI bot blocking, security headers, compression and basic auth. Use them only for routes that must **not** be protected, e.g. a public `/health` endpoint on a site that otherwise needs a login. A warning is logged when they are loaded.
  * Files load in natural sort order - use lower case names with a two-digit prefix, e.g. `10-health.before.json`, `20-api.json`.
  * Nginx `*.conf` files from nginx-proxy are ignored, with a warning.
* `true` - an existing file is left alone, giving you complete control. Run `proxy-regenerate -d <primary> -f` to regenerate it.

### DNS challenge

Use the DNS challenge for wildcard aliases, and for servers that are not reachable from the internet (e.g. only over a VPN).

1. In the Hetzner Console project that holds your zones, create an API token with read / write permission (the module uses the Cloud DNS API).
2. Set `BF_PROXY_HETZNER_TOKEN` to the token - see [keeping the token out of your compose file](#how-do-i-keep-the-hetzner-token-out-of-my-compose-file). It is never written to the generated configuration: Caddy reads it from the environment.
3. Set `BF_PROXY_ACME_CHALLENGE=dns`, or `"challenge": "dns"` on each domain.

Caddy waits `BF_PROXY_DNS_PROPAGATION_DELAY` (60 seconds) after creating each record, so Let's Encrypt doesn't ask a nameserver that hasn't got it yet - the missing record would be cached, and retries would fail too. The wait is once per batch of certificates, only when they are issued or renewed. Set `BF_PROXY_DNS_TTL=60s` (Hetzner's lowest) so stale challenge values don't stay cached either.

#### Domains hosted with another DNS provider

Delegate the challenge to a zone Hetzner hosts using CNAME records. Caddy doesn't follow the CNAME, so it has to be told where to create the record:

1. Create a zone in the token's Hetzner project, e.g. `acme.example.net` - either a separate domain with its nameservers set to Hetzner's, or a subdomain delegated with NS records at your registrar's DNS.
2. Set `BF_PROXY_DNS_OVERRIDE_ZONE=acme.example.net`. Each domain using the DNS challenge now creates its records at `<primary>.acme.example.net` - including the proxy domain.
3. At the domain's own DNS provider, add a CNAME for every host name in the domain (primary **and** aliases) pointing to the primary's name. For wildcards drop the `*.`:

| Record                                 | Type  | Value                                |
| -------------------------------------- | ----- | ------------------------------------ |
| `_acme-challenge.send.example.com`     | CNAME | `send.example.com.acme.example.net.` |
| `_acme-challenge.www.send.example.com` | CNAME | `send.example.com.acme.example.net.` |
| `_acme-challenge.files.example.com`    | CNAME | `send.example.com.acme.example.net.` |

That example is a domain with primary `send.example.com` and aliases `www.send.example.com` and `*.files.example.com`. Using a separate name for each domain stops requests for different domains overwriting each other's records.

Set `"dnsOverrideDomain"` on a domain to use a different name, or `""` for a domain Hetzner hosts directly, which needs no delegation. Check the records before requesting certificates:

```sh
dig +short CNAME _acme-challenge.send.example.com   # send.example.com.acme.example.net.
dig +short NS acme.example.net                      # Hetzner's nameservers
```

### Automatic reload

Run `proxy-regenerate` after changing `conf.json`, `users.json` or files in `/sites`, or set `BF_PROXY_AUTO_RELOAD=1` to do it automatically. Files are checked every 5 seconds, and once they have been unchanged for 5 seconds configuration is regenerated and Caddy reloads without dropping connections.

If the new configuration is not valid, the errors are written to the container log and Caddy keeps running with the current configuration.

### Helper commands

Run these with `docker exec <container> <command>`. Basic auth passwords are stored as bcrypt hashes, but `proxy-adduser` takes the password as an argument, so it may be kept in your shell history.

| Command            | Arguments                  | Description                                                    |
| ------------------ | -------------------------- | -------------------------------------------------------------- |
| `proxy-regenerate` | -d: only domain, -f: force | Regenerate configuration and reload (force includes `custom`). |
| `proxy-reload`     |                            | Validate the configuration and reload Caddy.                   |
| `proxy-validate`   |                            | Validate `conf.json` and the current Caddy configuration.      |
| `proxy-certs`      |                            | List certificates and days left (flagged at 14 or fewer).      |
| `proxy-renew`      | -a: all, or -d: domain     | Delete certificates and restart Caddy to request new ones.     |
| `proxy-pem`        |                            | Create or update PEM files for other containers now.           |
| `proxy-cleanup`    | -l: live mode              | Remove domains not in `conf.json` (dry run unless `-l`).       |
| `proxy-token`      |                            | Verify the Hetzner token and check it can manage your zones.   |
| `proxy-adduser`    | 0: username, 1: password   | Add or update a basic auth user.                               |
| `proxy-deluser`    | 0: username                | Remove a basic auth user.                                      |

## Migrating from nginx-proxy

1. Copy `/ssl/conf.json` to the new `/ssl` volume - it is converted on start-up. The original is kept as `/ssl/conf.json.nginx-proxy`, and anything that can't be converted is reported in the log.
2. Change the image to `bfren/caddy-proxy` and rename variables from `PROXY_*` to `BF_PROXY_*` (old names are ignored). These are no longer used: `PROXY_ENABLE_AUTO_UPDATE` (Caddy renews automatically), `PROXY_ENABLE_NAXSI`, `PROXY_SSL_KEY_BITS`, `PROXY_SSL_DHPARAM_BITS`, `PROXY_GETSSL_SKIP_HTTP_TOKEN_CHECK` and `PROXY_UPSTREAM_DNS_RESOLVER`.
3. Custom Nginx configuration in `/sites` can't be converted - rewrite it as Caddy JSON in `/sites/<primary>.d`.
4. Existing certificates are not reused. Caddy requests one certificate per host name (getssl used one per primary domain), so check [Let's Encrypt rate limits](https://letsencrypt.org/docs/rate-limits/) if you have many, and keep `BF_PROXY_LETS_ENCRYPT_LIVE=0` until everything works.
5. `nginx-adduser` is replaced by `proxy-adduser` - users are stored in `/ssl/users.json` and enabled per domain with `auth`.

## Testing

```sh
./test.nu        # builds the image and runs /test
./run.sh         # builds the image and opens a shell, using the internal CA on 127.0.0.1:8080 and :8443
```

`/test` runs this image's tests alongside the base images' tests.

## Troubleshooting

### Browsers say the certificate isn't trusted

`BF_PROXY_LETS_ENCRYPT_LIVE` is `0`, so certificates come from Let's Encrypt's staging server. Set it to `1` and restart. If staging certificates are still served, run `proxy-renew -a`.

### The DNS challenge fails with NXDOMAIN

The record hadn't reached all of Hetzner's nameservers. Increase `BF_PROXY_DNS_PROPAGATION_DELAY` (e.g. `120s`) and / or set `BF_PROXY_DNS_RESOLVERS` (e.g. `1.1.1.1`). If you delegate, check the CNAME records with `dig` (see [DNS challenge](#domains-hosted-with-another-dns-provider)) - a wrong or missing one fails the same way.

### I always see the maintenance page

Caddy can't reach the upstream. It must be on a Docker network shared with the proxy, and the URL must use the container's name and its **internal** port (e.g. `http://app:80`, not the port published on the host). Test from inside: `docker exec <container> wget -qO- http://app:80`.

### My changes don't take effect

Run `proxy-regenerate`, or set `BF_PROXY_AUTO_RELOAD=1`. Domains with `"custom": true` are only regenerated with `proxy-regenerate -d <primary> -f`. Errors are written to the container log.

## FAQs

### How do I proxy to a service running on the host, not in a container?

Add `extra_hosts` so the container can resolve the host, and use that name as the upstream:

```yaml
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

Then use e.g. `"upstream": "http://host.docker.internal:8080"`. The service must listen on an address the Docker bridge can reach (e.g. `0.0.0.0`, not `127.0.0.1`), and the host's firewall must allow it.

### How do I use a certificate in another container?

A PEM file (key and full chain) for each host name is kept in `/ssl/certs/<host>/<host>.pem`, as with nginx-proxy. It is created empty on start (so Docker won't create a directory in its place), then written every 15 minutes or by `proxy-pem`. Files are rewritten in place, so one can be mounted alone, e.g. for [bfren/ftps](https://github.com/bfren/docker-ftps):

```yaml
      - ./proxy/ssl/certs/ftp.example.com/ftp.example.com.pem:/ssl/vsftpd.pem:ro
```

### How do I keep the Hetzner token out of my compose file?

Put it in a `.env` file next to `docker-compose.yml` (and out of version control), e.g. `HETZNER_TOKEN=...`, then add `- BF_PROXY_HETZNER_TOKEN=${HETZNER_TOKEN}` to `environment`. Don't add quotes - they become part of the value.

### Can I use a DNS provider other than Hetzner?

Only Hetzner is built in, but domains hosted anywhere can use it by [delegating the challenge](#domains-hosted-with-another-dns-provider) with CNAME records.

## Licence

> [MIT](https://mit.bfren.dev/2020)

## Copyright

> Copyright (c) 2020-2026 [bfren](https://bfren.dev) (unless otherwise stated)
