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

## Login keepalive

FlakeHub sessions minted from Buildkite OIDC are short-lived, so in both modes
the plugin runs a background refresher for the duration of the job. It decodes
the netrc token's own `iat`/`exp` and renews just before expiry (or when the
cache rejects the token), so jobs of any length keep working. On multi-agent
hosts the netrc is shared and the refreshers coordinate implicitly: whoever
renews first moves everyone's deadline out. The refresher log is uploaded as a
job artifact unless `upload-logs` is `false`.
