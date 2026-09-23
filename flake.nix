{
  description = "Nix wrappers for Interactive Brokers TWS and IBKR Desktop";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      forSystem = system: rec {
        legacyPackages = nixpkgs.legacyPackages.${system};
        ibkr = legacyPackages.callPackage ./packages/ibkr.nix { };
        packages = {
          inherit (ibkr)
            tws
            tws-install
            ibkr-desktop
            ibkr-desktop-install
            ;
          default = ibkr.ibkr-desktop;
        };
      };
    in
    {
      packages.x86_64-linux = (forSystem "x86_64-linux").packages;

      homeManagerModules.default = import ./modules/home-manager.nix;

      homeManagerModules.ibkr = self.homeManagerModules.default;
    };
}
