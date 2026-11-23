{
  description = "Convert selected Wayland text between XKB keyboard layouts";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.rustPlatform.buildRustPackage {
          pname = "z-layout-switcher";
          version = "0.1.0";
          src = self;
          cargoLock.lockFile = ./Cargo.lock;
          nativeBuildInputs = [ pkgs.pkg-config pkgs.makeWrapper ];
          buildInputs = [ pkgs.libxkbcommon ];
          postInstall = ''
            wrapProgram $out/bin/z-layout-switcher \
              --prefix PATH : ${nixpkgs.lib.makeBinPath [ pkgs.wl-clipboard pkgs.wtype ]}
          '';
          meta = {
            description = "Convert selected Wayland text using XKB layouts";
            license = nixpkgs.lib.licenses.mit;
            platforms = systems;
          };
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.cargo pkgs.rustc pkgs.rustfmt pkgs.pkg-config pkgs.libxkbcommon pkgs.wl-clipboard pkgs.wtype ];
        };
      });

      homeManagerModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.programs.z-layout-switcher;
          xkb = config.programs.niri.settings.input.keyboard.xkb;
          layouts = if cfg.layouts == null then xkb.layout else cfg.layouts;
          xkbOptions = if xkb.options == null then "" else xkb.options;
          key = if cfg.key != null then cfg.key
            else if lib.elem "grp:caps_toggle" (lib.splitString "," xkbOptions) then "Super+Caps_Lock"
            else throw "z-layout-switcher: set programs.z-layout-switcher.key for this XKB layout-switch option";
        in
        {
          options.programs.z-layout-switcher = {
            enable = lib.mkEnableOption "selected-text layout conversion";
            layouts = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Comma-separated XKB layouts; defaults to niri input.keyboard.xkb.layout.";
            };
            key = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "niri key binding; derived from grp:caps_toggle when unset.";
            };
          };

          config = lib.mkIf cfg.enable {
            assertions = [{
              assertion = layouts != null && layouts != "";
              message = "Set programs.niri.settings.input.keyboard.xkb.layout or programs.z-layout-switcher.layouts";
            }];
            home.packages = [ self.packages.${pkgs.stdenv.hostPlatform.system}.default ];
            programs.niri.settings.binds.${key} = {
              repeat = false;
              action.spawn = [
                "${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/z-layout-switcher"
                "--layouts" layouts
                "--variants" (if xkb.variant == null then "" else xkb.variant)
                "--options" xkbOptions
              ];
            };
          };
        };
    };
}
