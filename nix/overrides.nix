{ pkgs }:

self: super:

with { inherit (pkgs.stdenv) lib; };

with pkgs.haskell.lib;

{
  reflex-mono = (
    with rec {
      reflex-monoSource = pkgs.lib.cleanSource ../.;
      reflex-monoBasic  = self.callCabal2nix "reflex-mono" reflex-monoSource { };
    };
    overrideCabal reflex-monoBasic (old: {
    })
  );
}
