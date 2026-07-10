# identityHashFor — the exported instance-value → id_hash recompute, for external kind-DISCOVERY (a
# consumer holding an instance value but not its kind recomputes the hash per candidate kind and matches
# the carried id_hash). It routes through the SAME `hashIdentity` formula as `mkIdentityModule`, so the two
# can never drift; these tests pin that equivalence + the kind-discrimination the discovery relies on.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkIdentityModule identityHashFor hashIdentity;
  host = genMerge.evalModuleTree {
    modules = [
      (mkIdentityModule "host")
      { options.name = genMerge.mkOption { type = genMerge.types.str; }; }
      {
        options.rack = genMerge.mkOption {
          type = genMerge.types.int;
          default = 0;
        };
      }
      {
        config.name = "igloo";
        config.rack = 3;
      }
    ];
  };
  inst = host.config;
in
{
  # the EXPORTED recompute equals the id_hash the MODULE stamped — same formula, no drift.
  flake.tests.identity-hash-for.test-matches-module = {
    expr = identityHashFor "host" inst == inst.id_hash;
    expected = true;
  };
  # a wrong kind name does NOT match — the discovery discriminator (a non-match = "not this kind").
  flake.tests.identity-hash-for.test-discriminates-kind = {
    expr = identityHashFor "user" inst == inst.id_hash;
    expected = false;
  };
  # hashIdentity is the shared primitive both derivations hash through.
  flake.tests.identity-hash-for.test-hashIdentity-shape = {
    expr =
      hashIdentity "host" [ "name" ] (_: "igloo") == builtins.hashString "sha256" "host|name=igloo";
    expected = true;
  };
}
