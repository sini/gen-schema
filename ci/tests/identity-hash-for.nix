# identityHashForKind — the exported kind-value → id_hash recompute, for external kind-DISCOVERY (a
# consumer holding an instance value and a candidate KIND VALUE recomputes the hash and matches the carried
# id_hash). It routes through the SAME `hashIdentity` formula as `mkIdentityModule`, so the two can never
# drift; these tests pin that equivalence + the kind-discrimination the discovery relies on.
#
# It is the SOLE recompute path. A value-reflecting twin cannot honour the preimage commitment — an
# instance value carries no option metadata, so it can see neither `internal` nor `identity = false` — and
# one minting authority means two derivations that can disagree is one derivation too many.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) hashIdentity;

  # A kind with a mixed str/int identity key set, plus a SAME-SHAPED kind under a different name —
  # the discovery discriminator's fixture: identical options and values, so only the kind separates
  # the two recomputes.
  hostTree = genMerge.evalModuleTree {
    modules = [
      (
        { config, ... }:
        {
          options.schema = genSchema.mkSchemaOption { };
          options.hosts = genSchema.mkInstanceRegistry config.schema.host { };
          config.schema.host.options.rack = genMerge.mkOption {
            type = genMerge.types.int;
            default = 0;
          };
          config.schema.hostAlt.options.rack = genMerge.mkOption {
            type = genMerge.types.int;
            default = 0;
          };
          config.hosts.igloo.rack = 3;
        }
      )
    ];
  };
  hostKv = hostTree.config.schema.host;
  hostAltKv = hostTree.config.schema.hostAlt;
  hostInst = hostTree.config.hosts.igloo;

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
      overNameAndSystem =
        "home:" + builtins.hashString "sha256" ''{"name":s"ben","system":s"x86_64-linux",}'';
    };
    expected = {
      recomputeMatchesStamp = true;
      stamped = "home:" + builtins.hashString "sha256" ''{"name":s"ben","system":s"x86_64-linux",}'';
      overNameAndSystem =
        "home:" + builtins.hashString "sha256" ''{"name":s"ben","system":s"x86_64-linux",}'';
    };
  };
  # identityHashForKind (option-level) equals the id_hash the module stamped — the EXACT twin.
  flake.tests.identity-hash-for.test-forKind-matches-module = {
    expr = (genSchema.identityHashForKind rackKv rackInst) == rackInst.id_hash;
    expected = true;
  };
  # the EXPORTED recompute equals the id_hash the MODULE stamped, over a MIXED str/int key set —
  # same formula, no drift.
  flake.tests.identity-hash-for.test-matches-module = {
    expr = (genSchema.identityHashForKind hostKv hostInst) == hostInst.id_hash;
    expected = true;
  };
  # a wrong kind does NOT match — the discovery discriminator (a non-match = "not this kind"). The
  # candidate kind here has an IDENTICAL option set over identical values, so the kind is the only
  # thing separating the two recomputes; a discriminator that needed a differing field would not
  # witness the property discovery relies on.
  flake.tests.identity-hash-for.test-discriminates-kind = {
    expr = (genSchema.identityHashForKind hostAltKv hostInst) == hostInst.id_hash;
    expected = false;
  };
  # hashIdentity is the primitive every derivation hashes through, and this is its FORMAT: the kind
  # joined to a digest of the pairs, the pairs rendered as a JSON attrset.
  flake.tests.identity-hash-for.test-hashIdentity-shape = {
    expr =
      hashIdentity "host" [ "name" ] (_: "igloo")
      == "host:" + builtins.hashString "sha256" ''{"name":s"igloo",}'';
    expected = true;
  };
}
