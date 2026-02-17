{
  description = "FlakeHub Cache Buildkite Plugin";

  inputs = {
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
    flake-utils.url = "github:numtide/flake-utils";
    magic-nix-cache.url = "https://flakehub.com/f/DeterminateSystems/magic-nix-cache/0.1.547";
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2511";
  };

  outputs = { flake-utils, nixpkgs, ... }:
    flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs { inherit system; };
    in
    {
      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          bats
          docker
        ];
      };
    });
}
