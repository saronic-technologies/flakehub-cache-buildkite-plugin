# FlakeHub Cache Buildkite Plugin

A Buildkite plugin for using DeterminateSystems FlakeHub Cache.
See: https://flakehub.com/cache

## Example

Add the following to your `pipeline.yml`:

```yml
steps:
  - command: nix build .#my-package
    plugins:
      - saronic-technologies/flakehub-cache#v2.0.0
```

## Configuration

### `determinate-nix-version` (Optional, string)

The Determinate Nix version installed on hosts that don't already have one —
hosted macs and other non-NixOS agents. NixOS agents bake `determinate-nixd`
into their image via the `determinate` flake input and never hit the install
path.

Defaults to the version pinned by this plugin release, so the version an agent
gets rides the plugin tag your pipeline already pins: bumping Determinate Nix
for these hosts is a one-line change to the default here, a new plugin release,
and a tag bump in the pipeline — and rolling back is reverting the tag. Set to
a specific version like `3.22.2` to override, or `stable` to track
Determinate's rolling channel (the pre-v3.4.0 behavior).

On macOS a host with a different version than the pin is converged by
reinstalling the pinned package. On Linux and NixOS the installed version is
host-managed; a mismatch is logged but not changed.

```yml
steps:
  - command: nix build .#my-package
    plugins:
      - saronic-technologies/flakehub-cache#v3.4.0:
          determinate-nix-version: stable
```

### `upload-logs` (Optional, boolean)

Whether or not to upload plugin logs to the Buildkite job (default `true`).

### `push` (Optional, boolean)

Whether to push store paths built by the job to FlakeHub Cache (default `true`).

Set to `false` on hosts running multiple concurrent agents: Magic Nix Cache
needs an exclusive view of the Nix store, so it is never started in this mode.
The plugin still logs in to FlakeHub with the job's Buildkite OIDC identity for
cache reads and private flakes.

```yml
steps:
  - command: nix build .#my-package
    plugins:
      - saronic-technologies/flakehub-cache#v3.3.0:
          push: false
```

## nsh output force-upload (`--store nsh://` jobs)

For jobs whose command builds via `--store nsh://`, `post-command` enqueues
every store path registered since the command started into Magic Nix Cache
(the TEMPORARY WORKAROUND in `hooks/post-command`). Magic Nix Cache then keeps
only what FlakeHub's `get-missing-paths` calls missing, and that answer is
org-wide while the job's narinfo reads are scoped to its own cache: any output
another pipeline's cache already holds is reported "present" and silently
dropped, so a pipeline's cache never receives outputs its twin built first.
`lib/force-upload.sh` closes that gap right after the enqueue: it probes
`<hash>.narinfo` with the job's token and `PUT`s every 404 straight to
`/_api/v1/upload-path`. It prints one `force-upload:` line per path and one
summary line, and never fails the job (errors are `force-upload: WARNING:`
lines, exit status 0). `.drv` paths are left to Magic Nix Cache.

Environment toggles (pipeline, step or agent environment; no plugin option):

| Variable | Effect |
| --- | --- |
| `FLAKEHUB_CACHE_FORCE_UPLOAD=0` | skip the force-upload entirely |
| `FLAKEHUB_CACHE_FORCE_UPLOAD_DRY_RUN=1` | probe and log what would be uploaded, upload nothing |
| `FORCE_UPLOAD_PARALLEL` | concurrent uploads (default 4) |
| `FORCE_UPLOAD_MAX_TIME` | seconds allowed per upload (default 1800) |

## Login keepalive

FlakeHub sessions minted from Buildkite OIDC are short-lived, so in both modes
the plugin runs a background refresher for the duration of the job. It decodes
the netrc token's own `iat`/`exp` and renews just before expiry (or when the
cache rejects the token), so jobs of any length keep working. On multi-agent
hosts the netrc is shared and the refreshers coordinate implicitly: whoever
renews first moves everyone's deadline out. The refresher log is uploaded as a
job artifact unless `upload-logs` is `false`.
