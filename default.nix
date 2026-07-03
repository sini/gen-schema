# Standalone (non-flake) entry. Flake consumers should use the `.lib` output.
#
# gen-schema is a function of three named values — gen-prelude (the pure utility base),
# gen-merge (the byte-mode module MERGE engine that REPLACES lib.evalModules + lib.types),
# and gen-algebra (the pure record algebra). Defaults fetch the flake-locked revs
# (content-addressed via narHash, so the plain-import path stays pure and in lockstep with
# the flake output). Pass any explicitly to override (e.g. a local checkout).
{
  lock ? builtins.fromJSON (builtins.readFile ./flake.lock),
  fetch ? name: builtins.fetchTree lock.nodes.${lock.nodes.root.inputs.${name}}.locked,
  prelude ? import "${fetch "gen-prelude"}/lib",
  merge ? import "${fetch "gen-merge"}/lib" {
    inherit prelude;
    types = import "${fetch "gen-types"}/lib" { inherit prelude; };
  },
  algebra ? import "${fetch "gen-algebra"}/lib",
}:
import ./lib { inherit prelude merge algebra; }
