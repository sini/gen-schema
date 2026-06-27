{
  lib ? (import <nixpkgs> { }).lib,
  algebra ?
    let
      lock = builtins.fromJSON (builtins.readFile ./flake.lock);
    in
    import "${builtins.fetchTree lock.nodes.gen-algebra.locked}/lib",
  ...
}:
import ./lib { inherit lib algebra; }
