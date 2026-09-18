# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) and to [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

## v3.6.1 (2026-09-18)

### Bug Fixes
- the v3.6.0 out-link scan never matched for nsh jobs: `nix build --store nsh://` creates no ./result out-links (out-links are local-FS-store only), so nothing was enqueued. Discovery now uses the store itself: pre-command writes a watermark, post-command enqueues every path whose registrationTime is after it — gated on the command containing `nsh://` so ordinary jobs skip the store scan. Still a TEMPORARY WORKAROUND pending first-class FlakeHub cache push access from Determinate Systems.

## v3.6.0 (2026-09-18)

### Bug Fixes
- **TEMPORARY WORKAROUND** (remediation: Determinate Systems to provide a first-class way to push to the FlakeHub cache ourselves — a supported push CLI/API — instead of magic-nix-cache's daemon-event side channel; remove this hook logic when that lands): upload nsh whole-graph build outputs to FlakeHub Cache: `--store nsh://` builds run on the cluster and their outputs come back as a store copy, which emits no determinate-nixd built-path events, so magic-nix-cache's upload set was always empty ("FlakeHub Cache uploads completed, paths: []"). post-command now enqueues the closures of the store symlinks the job left in the checkout via mnc's /api/enqueue-paths before draining. Locally-built paths are unaffected (already event-enqueued; duplicates dedup against the cache). Steps that leave no out-links (`nix run`-only) still upload nothing.

## v3.5.0 (2026-09-16)

### Bug Fixes
- always log in with the job's Buildkite OIDC identity instead of skipping when the host netrc token looks fresh: a boot-time awssts token passes the freshness and cache.flakehub.com probes (it has cache-read entitlement) but has no FlakeHub org session, so Magic Nix Cache's api.flakehub.com cache-name lookup gets 401 and the daemon never starts (60s startup timeouts across bk-runners-slurm fan-out waves, combined-pr-checks-slurm build 99). The mid-job refresher keeps its deadline-driven renewal logic unchanged.

## v3.4.0 (2026-08-25)

### Feature
- pin the Determinate Nix version installed on non-NixOS hosts (default per plugin release, currently `3.22.2`) via version-tagged install URLs, replacing the unpinned `stable` channel; add `determinate-nix-version` option to override or opt back into `stable`
- log the detected Determinate Nix version; on macOS, converge hosts whose version differs from the pin by reinstalling the pinned package

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
