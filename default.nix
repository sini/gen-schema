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
  # Through gen-merge's OWN standalone entry rather than its `./lib`, so gen-merge's gen-types
  # dependency is satisfied from gen-merge's lock. Reaching for `./lib` obliged this file to supply
  # `types` itself, and supplying it is the only reason gen-types was ever declared in this
  # repository's flake — a dependency named on another library's behalf. It also read the pin from
  # THIS lock while the flake path reads it from gen-merge's, so the two could drift; they agree
  # today (both 887ad87), and now they cannot disagree.
  merge ? import "${fetch "gen-merge"}" { inherit prelude; },
  algebra ? import "${fetch "gen-algebra"}/lib",
}:
import ./lib { inherit prelude merge algebra; }
