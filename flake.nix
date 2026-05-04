{
  description = "FlakeHub Cache Buildkite Plugin";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
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
          shellcheck
        ];
      };
    });
}
