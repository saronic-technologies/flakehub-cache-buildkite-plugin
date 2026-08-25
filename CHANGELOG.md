# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) and to [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

## v3.3.1 (2026-08-25)

### Bug Fixes
- retry the FlakeHub login with exponential backoff (5 attempts over ~30s) instead of one instant retry, so short FlakeHub/OIDC outages no longer fail jobs (motivated by the 2026-08-25 14:46–15:41 UTC auth outage)

## v3.3.0 (2026-08-04)

### Feature
- add `push` option (default `true`): when `false`, never start Magic Nix Cache (multi-agent-safe, login-only mode)
- keep the FlakeHub login fresh for the whole job via a deadline-driven background refresher (renews off the token's own `iat`/`exp`; fails loudly on undecodable tokens)

## v2.0.0 (2026-03-20)

### Feature
- additional arch support (#3) [`b6682f0`](https://github.com/saronic-technologies/flakehub-cache-buildkite-plugin/commit/b6682f0)

## v1.2.0 (2026-02-18)

### Feature
- add token lifetime feature and option (#2) [`5bffecc`](https://github.com/saronic-technologies/flakehub-cache-buildkite-plugin/commit/5bffecc)

## v1.1.0 (2026-02-18)

### Feature
- add upload logs feature and option (#1) [`5424f8c`](https://github.com/saronic-technologies/flakehub-cache-buildkite-plugin/commit/5424f8c)

## v1.0.0 (2026-02-17)

### Feature
- add license [`331fd2e`](https://github.com/saronic-technologies/flakehub-cache-buildkite-plugin/commit/331fd2e)
- initial commit [`6916192`](https://github.com/saronic-technologies/flakehub-cache-buildkite-plugin/commit/6916192)

### Bug Fixes
- shebangs [`cdf1434`](https://github.com/saronic-technologies/flakehub-cache-buildkite-plugin/commit/cdf1434)
