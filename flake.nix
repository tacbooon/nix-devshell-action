{
  description = "Dev shell for nix-devshell-action contributors";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-extras = {
      url = "github:tacbooon/nixpkgs-extras";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-extras,
    }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ nixpkgs-extras.overlays.default ];
          };
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.bats
              pkgs.gh
              pkgs.jactionlint
              pkgs.nixfmt
              pkgs.shellcheck
            ];
          };
          fixture = pkgs.mkShell {
            packages = [ pkgs.hello ];

            shellHook = ''
              export FIXTURE_APP_NAME="fixture-app"
              export FIXTURE_DB_HOST="localhost"
            '';
          };
        }
      );
    };
}
