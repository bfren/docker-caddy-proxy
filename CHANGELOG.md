# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.4] - Unreleased

### Changed

- The `$schema` written into a generated or converted `conf.json` is now the pinned
  `https://schemas.bfren.dev/docker/caddy-proxy/domains/2026-11.json` - existing files that use the old GitHub URL
  still work.

## [2.0.3] - 2026-11-10

### Changed

- Base image updated to `bfren/alpine-s6` 7.0.2, which updates Nushell to 0.117.0 (your own Nushell scripts may
  need changes), keeps the container starting when `BF_TZ` cannot be set, and no longer hides `CURRENT_FILE` and
  `FILE_PWD` from services - see the
  [Alpine + S6 changelog](https://github.com/bfren/docker-alpine-s6/blob/main/CHANGELOG.md).

## [2.0.2] - 2026-11-06

### Changed

- Base image updated to `bfren/alpine-s6` 7.0.1, which moves to Alpine 3.24.4 (with security fixes) and rebuilds
  BusyBox, figlet and Nushell - see the
  [Alpine + S6 changelog](https://github.com/bfren/docker-alpine-s6/blob/main/CHANGELOG.md).

### Fixed

- The build information shows the Caddy version again - recording the ai.robots.txt version stopped it being shown.

## [2.0.1] - 2026-11-05

### Changed

- Caddy updated to [2.11.9](https://github.com/caddyserver/caddy/releases/tag/v2.11.9), which fixes a regression in
  2.11.8 that stopped PHP directory indexes (e.g. `/wp-admin/`) being served, and includes FastCGI security fixes.
  FastCGI requests whose script path is ambiguous now get `400`, and FastCGI `env` values take precedence over
  request headers. A conflicting `client_auth` across site blocks is now a Caddyfile error.

## [2.0.0] - 2026-11-05

### Added

- `proxy-dns` checks the public DNS records needed to issue certificates: A / AAAA records for the http challenge,
  `_acme-challenge` CNAMEs for the dns challenge, and CAA records allowing Let's Encrypt.

### Changed

- **Breaking:** base image updated to `bfren/alpine-s6` 7.0.0 - see the
  [Alpine + S6 changelog](https://github.com/bfren/docker-alpine-s6/blob/main/CHANGELOG.md).
  `bf env set` must now run as root.
- Caddy updated to [2.11.8](https://github.com/caddyserver/caddy/releases/tag/v2.11.8), which includes security
  fixes. Requests with an invalid host (e.g. `..`) are now rejected with `400`, and responses are compressed even
  when the request sends `Cache-Control: no-transform`.
- The Caddy build stage now uses `quay.io/bfren-bin/caddy` instead of `caddy` from Docker Hub.
- Images are built and published by the shared `bfren/docker` build workflow (`build.yml`), replacing the separate
  `dev.yml` and `publish.yml` workflows.

### Security

- `auth` in `conf.json` must be `true`, `false` or a list of user names. Anything else (e.g. `"auth": "fred"` instead
  of `["fred"]`) was treated as `true`, letting every user in - it is now a configuration error.

[2.0.4]: https://github.com/bfren/docker-caddy-proxy/compare/v2.0.3...v2.0.4
[2.0.3]: https://github.com/bfren/docker-caddy-proxy/compare/v2.0.2...v2.0.3
[2.0.2]: https://github.com/bfren/docker-caddy-proxy/compare/v2.0.1...v2.0.2
[2.0.1]: https://github.com/bfren/docker-caddy-proxy/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/bfren/docker-caddy-proxy/compare/v1.0.7...v2.0.0
