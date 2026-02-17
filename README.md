# FlakeHub Cache Buildkite Plugin

A Buildkite plugin for using DeterminateSystems FlakeHub Cache.
See: https://flakehub.com/cache

## Example

Add the following to your `pipeline.yml`:

```yml
steps:
  - command: nix build .#my-package
    plugins:
      - DeterminateSystems/flakehub-cache#v1.0.0:
```

## Configuration

This plugin requires no configuration.
