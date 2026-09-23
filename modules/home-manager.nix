# Home Manager module for Interactive Brokers clients.
#
# Installs FHS launchers for the proprietary TWS and IBKR Desktop apps. The
# apps themselves are installed per-user into ~/Jts and ~/ntws by IBKR's
# install4j installers (see the tws-install / ibkr-desktop-install wrappers
# and the README).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.ibkr;
  ibkr = pkgs.callPackage ../packages/ibkr.nix {
    inherit (cfg.desktop) gpuWorkarounds;
  };
in
{
  options.programs.ibkr = {
    enable = lib.mkEnableOption "Interactive Brokers client launchers";

    desktop = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the IBKR Desktop launcher and installer.";
      };

      gpuWorkarounds = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Enable EGL/GLX workarounds for NVIDIA and hybrid NVIDIA+AMD
          systems (EGL vendor dir override + xcb EGL integration).
          Harmless on other setups; disable if they interfere with a
          working single-vendor configuration.
        '';
      };
    };

    tws = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Install the Trader Workstation (Java) launcher and installer.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      lib.optionals cfg.desktop.enable [
        ibkr.ibkr-desktop
        ibkr.ibkr-desktop-install
      ]
      ++ lib.optionals cfg.tws.enable [
        ibkr.tws
        ibkr.tws-install
      ];
  };
}
