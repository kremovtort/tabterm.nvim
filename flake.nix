{
  description = "Tabterm Neovim plugin flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ self, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      flake = {
        nixvimModules.default =
          { lib, pkgs, ... }:
          let
            tabterm = pkgs.vimUtils.buildVimPlugin {
              name = "tabterm";
              src = self;
            };
          in
          lib.nixvim.plugins.mkNeovimPlugin {
            name = "tabterm";
            moduleName = "tabterm";
            package = lib.mkOption {
              type = lib.types.package;
              default = tabterm;
              defaultText = lib.literalExpression "tabterm";
              description = "The tabterm plugin package to use.";
            };
            maintainers = [ ];
            url = "https://github.com/kremovtort/dotfiles/tree/main/nvim/plugins/tabterm";
            description = "Tab-scoped floating terminal workspace for Neovim.";
            settingsExample = {
              ui = {
                border = "round";
                sidebar_width = 30;
                float = {
                  width = 0.9;
                  height = 0.9;
                };
              };
            };
          };
      };

      perSystem =
        { pkgs, ... }:
        {
          packages.default = pkgs.vimUtils.buildVimPlugin {
            name = "tabterm";
            src = self;
          };

          devShells.default = pkgs.mkShell {
            packages = [
              pkgs.bash-language-server
              pkgs.just
              pkgs.lua
              pkgs.lua-language-server
              pkgs.nixd
              pkgs.nixfmt
              pkgs.statix
              pkgs.shellcheck
              pkgs.stylua
            ];
          };
        };
    };
}
