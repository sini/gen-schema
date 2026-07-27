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

  # A processed KIND-VALUE + instance (via mkSchemaOption + a registry), for identityHashForKind.
  schemaTree = genMerge.evalModuleTree {
    modules = [
      { options.schema = genSchema.mkSchemaOption { }; }
      {
        config.schema.rack.options.slots = genMerge.mkOption {
          type = genMerge.types.int;
          default = 0;
        };
      }
      (
        { config, ... }:
        {
          options.rackFarm = genSchema.mkInstanceRegistry config.schema.rack { };
        }
      )
      { config.rackFarm.r1.slots = 12; }
    ];
  };
  rackKv = schemaTree.config.schema.rack;
  rackInst = schemaTree.config.rackFarm.r1;

  # The same pairing over a kind whose identity field is declared with NIXPKGS `lib.types.str`.
  # Both reflections select identity keys by the option's type NAME, and nixpkgs spells a string
  # `str` where gen-types spells it `string` — so a kind authored the way a consumer authors one (den
  # declares every entity option with nixpkgs `lib.types`) is the ONLY shape on which the two can
  # disagree. The gen-typed fixture above uses an `int`, a name both type systems share, so it is
  # structurally incapable of witnessing that disagreement: it stayed green while they diverged.
  homeTree = genMerge.evalModuleTree {
    modules = [
      { options.schema = genSchema.mkSchemaOption { }; }
      {
        config.schema.home.imports = [
          (_: {
            options.system = lib.mkOption {
              type = lib.types.str;
              default = "";
            };
          })
        ];
      }
      (
        { config, ... }:
        {
          options.homes = genSchema.mkInstanceRegistry config.schema.home { };
        }
      )
      { config.homes.ben.system = "x86_64-linux"; }
    ];
  };
  homeKv = homeTree.config.schema.home;
  homeInst = homeTree.config.homes.ben;
in
{
  # THE DRIFT GUARD. `mkIdentityModule` stamps `id_hash` by reflecting the instance's options;
  # `identityHashForKind` recomputes it by reflecting the kind value's. Both must select the same
  # keys, and a consumer-authored (nixpkgs-typed) kind is where they can part company.
  flake.tests.identity-hash-for.test-forKind-matches-module-nixpkgs-str = {
    expr = {
      recomputeMatchesStamp = (genSchema.identityHashForKind homeKv homeInst) == homeInst.id_hash;
      # The KEY SET, pinned by contents. Equality alone is satisfied if BOTH sides degenerate
      # together — two reflections that select nothing agree perfectly while every instance collapses
      # to a name-only hash. Pinning what was actually hashed is what separates agreement from
      # shared blindness.
      stamped = homeInst.id_hash;
      overNameAndSystem = builtins.hashString "sha256" "home|name=ben|system=x86_64-linux";
    };
    expected = {
      recomputeMatchesStamp = true;
      stamped = builtins.hashString "sha256" "home|name=ben|system=x86_64-linux";
      overNameAndSystem = builtins.hashString "sha256" "home|name=ben|system=x86_64-linux";
    };
  };
  # identityHashForKind (option-level) equals the id_hash the module stamped — the EXACT twin.
  flake.tests.identity-hash-for.test-forKind-matches-module = {
    expr = (genSchema.identityHashForKind rackKv rackInst) == rackInst.id_hash;
    expected = true;
  };
  # for a kind without `identity = false`, option-level agrees with the instance-level approximation.
  flake.tests.identity-hash-for.test-forKind-agrees-instance = {
    expr = (genSchema.identityHashForKind rackKv rackInst) == (identityHashFor "rack" rackInst);
    expected = true;
  };
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
