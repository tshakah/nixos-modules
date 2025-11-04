{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    sops-nix,
    flake-utils,
    ...
  } @ inputs:
    with inputs; let
      inherit (nixpkgs) lib;
      functions = import ./functions/strings.nix {inherit lib;};
      elixirPackage = ./modules/elixir_package.nix;
      elixirService = import ./modules/elixir_service.nix {inherit functions lib;};
    in
      {inherit functions elixirService elixirPackage;}
      // flake-utils.lib.eachDefaultSystem (
        system: let
          pkgs = import nixpkgs {inherit system;};
        in {
          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              ssh-to-age
              age
              sops
              alejandra
              statix
              nix-unit
              nix-tree
            ];
          };
        }
      );
}
