{
  description = "Dev shell for nix-devshell-action contributors";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
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
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.actionlint
              pkgs.bats
              pkgs.gh
              pkgs.nixfmt
              pkgs.shellcheck
              pkgs.zizmor
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
