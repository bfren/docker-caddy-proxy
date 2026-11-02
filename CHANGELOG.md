# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - Unreleased

### Added

- `proxy-dns` checks the public DNS records needed to issue certificates: A / AAAA records for the http challenge,
  `_acme-challenge` CNAMEs for the dns challenge, and CAA records allowing Let's Encrypt.

### Changed

- **Breaking:** base image updated to `bfren/alpine-s6` 7.0.0 - see the
  [Alpine + S6 changelog](https://github.com/bfren/docker-alpine-s6/blob/main/CHANGELOG.md).
  `bf env set` must now run as root.
- Images are built and published by the shared `bfren/docker` build workflow (`build.yml`), replacing the separate
  `dev.yml` and `publish.yml` workflows.

### Security

- `auth` in `conf.json` must be `true`, `false` or a list of user names. Anything else (e.g. `"auth": "fred"` instead
  of `["fred"]`) was treated as `true`, letting every user in - it is now a configuration error.

[2.0.0]: https://github.com/bfren/docker-caddy-proxy/compare/v1.0.7...v2.0.0
