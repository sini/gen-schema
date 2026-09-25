# identityHashForKind — the exported kind-value → id_hash recompute, for external kind-DISCOVERY (a
# consumer holding an instance value and a candidate KIND VALUE recomputes the hash and matches the carried
# id_hash). It routes through the SAME `hashIdentity` formula as `mkIdentityModule`, so the two can never
# drift; these tests pin that equivalence + the kind-discrimination the discovery relies on.
#
# It is the SOLE recompute path. A value-reflecting twin cannot honour the preimage commitment — an
# instance value carries no option metadata, so it can see neither the declared type nor `identity = false` — and
# one minting authority means two derivations that can disagree is one derivation too many.
{
  lib,
  genSchema,
  genMerge,
  genIdentity,
  ...
}:
let
  # The mint is gen-identity's; the reflection path this file tests is gen-schema's, and it
  # builds values WITH the injected mint rather than owning one.
  inherit (genIdentity) hashIdentity;

  # A kind with a mixed str/int identity key set, plus a SAME-SHAPED kind under a different name —
  # the discovery discriminator's fixture: identical options and values, so only the kind separates
  # the two recomputes.
  hostSchema = genSchema.evalSchema {
    modules = [
      {
        config.schema.host.options.rack = genMerge.mkOption {
          type = genMerge.types.int;
          default = 0;
        };
        config.schema.hostAlt.options.rack = genMerge.mkOption {
          type = genMerge.types.int;
          default = 0;
        };
        # `hook` is declared FUNCTION-typed on host, so reflection does not select it and the host
        # stamp is unmoved — while the instance still carries a value at that name. The candidate
        # kind `sleeve` below declares the same name `str`, so `hook` IS one of its identity keys:
        # the pair is a candidate whose key the instance carries at a value the MINT refuses.
        config.schema.host.options.hook = lib.mkOption {
          type = lib.types.functionTo lib.types.str;
          default = _: "";
        };
        # A candidate kind identifying by an option `host` does not declare at all — the wrong-kind
        # discovery case the recompute must ANSWER rather than abort on.
        config.schema.spindle.options.gauge = genMerge.mkOption {
          type = genMerge.types.int;
          default = 0;
        };
        config.schema.sleeve.options.hook = genMerge.mkOption {
          type = genMerge.types.str;
          default = "";
        };
      }
    ];
  };
  hostTree = genMerge.evalModuleTree {
    modules = [
      {
        options.hosts = genSchema.mkInstanceRegistry hostSchema.host { };
        config.hosts.igloo.rack = 3;
      }
    ];
  };
  hostKv = hostSchema.host;
  hostAltKv = hostSchema.hostAlt;
  spindleKv = hostSchema.spindle;
  sleeveKv = hostSchema.sleeve;
  hostInst = hostTree.config.hosts.igloo;

  # A kind whose identity key is DECLARED primitive and whose value is not: `apply` is not
  # type-constrained, so `tag : str` reflects as an identity key while the instance carries a list.
  # The mint admits inert composites (lambdas, paths and derivations are what it refuses), so this is
  # a RIGHT-kind instance with a computable identity — and any guard reading the VALUE rather than
  # its presence answers `null` for it and misses its own kind.
  widgetSchema = genSchema.evalSchema {
    modules = [
      {
        config.schema.widget.options.tag = genMerge.mkOption {
          type = genMerge.types.str;
          default = "t";
          apply = x: [ x ];
        };
        # the live control: a plain `str` key on the same kind, which every candidate guard admits.
        config.schema.widget.options.zone = genMerge.mkOption {
          type = genMerge.types.str;
          default = "z";
        };
      }
    ];
  };
  widgetTree = genMerge.evalModuleTree {
    modules = [
      {
        options.widgets = genSchema.mkInstanceRegistry widgetSchema.widget { };
        config.widgets.cog = { };
      }
    ];
  };
  widgetKv = widgetSchema.widget;
  widgetInst = widgetTree.config.widgets.cog;

  # A processed KIND-VALUE + instance (via mkSchemaOption + a registry), for identityHashForKind.
  rackSchema = genSchema.evalSchema {
    modules = [
      {
        config.schema.rack.options.slots = genMerge.mkOption {
          type = genMerge.types.int;
          default = 0;
        };
      }
    ];
  };
  schemaTree = genMerge.evalModuleTree {
    modules = [
      { options.rackFarm = genSchema.mkInstanceRegistry rackSchema.rack { }; }
      { config.rackFarm.r1.slots = 12; }
    ];
  };
  rackKv = rackSchema.rack;
  rackInst = schemaTree.config.rackFarm.r1;

  # The same pairing over a kind whose identity field is declared with NIXPKGS `lib.types.str`.
  # Both reflections select identity keys by the option's type NAME, and nixpkgs spells a string
  # `str` where gen-types spells it `string` — so a kind authored the way a consumer authors one (den
  # declares every entity option with nixpkgs `lib.types`) is the ONLY shape on which the two can
  # disagree. The gen-typed fixture above uses an `int`, a name both type systems share, so it is
  # structurally incapable of witnessing that disagreement: it stayed green while they diverged.
  homeSchema = genSchema.evalSchema {
    modules = [
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
    ];
  };
  homeTree = genMerge.evalModuleTree {
    modules = [
      { options.homes = genSchema.mkInstanceRegistry homeSchema.home { }; }
      { config.homes.ben.system = "x86_64-linux"; }
    ];
  };
  homeKv = homeSchema.home;
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
      # shared blindness. The preimage carries the KIND as a labelled component whose value is its
      # minted identity, beside the keys; the tag stays the display name.
      stamped = homeInst.id_hash;
      # The live arm: the preimage WITHOUT the kind component is not what was hashed, so the cell
      # separates a stamp keyed by the declaration from one keyed by the name alone.
      nameOnlyPreimageIsNotTheStamp =
        homeInst.id_hash
        == "home:" + builtins.hashString "sha256" ''{"name":s"ben","system":s"x86_64-linux",}'';
    };
    expected = {
      recomputeMatchesStamp = true;
      stamped =
        "home:"
        + builtins.hashString "sha256" ''{"_identity":s"${homeKv.__mint.minted}","name":s"ben","system":s"x86_64-linux",}'';
      nameOnlyPreimageIsNotTheStamp = false;
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
  # THE DISCOVERY PROPERTY over candidates with DIFFERENT key sets — the shape `test-discriminates-kind`
  # above is structurally incapable of witnessing, because its two kinds declare identical option sets
  # and so have no key the instance can be missing. Runs the README's own `findFirst` loop and pins the
  # cardinality, so a loop that stopped early rather than passing over the wrong candidate fails loudly.
  flake.tests.identity-hash-for.test-discovers-kind-over-different-key-sets =
    let
      candidates = [
        spindleKv
        hostAltKv
        hostKv
      ];
    in
    {
      expr = {
        hostKeys = genSchema.identityKeysForKind { } hostKv;
        spindleKeys = genSchema.identityKeysForKind { } spindleKv;
        wrongKind = genSchema.identityHashForKind spindleKv hostInst;
        checked = builtins.length candidates;
        discovered =
          (lib.findFirst (kv: genSchema.identityHashForKind kv hostInst == hostInst.id_hash) null candidates)
          .kind;
        # the literal the recompute already produced before the guard existed. Agreement alone is
        # satisfied by two sides degenerating together, and a guard that moved an existing identity
        # would pass a cell that only compared them.
        rightKind = genSchema.identityHashForKind hostKv hostInst;
      };
      expected = {
        hostKeys = [
          "name"
          "rack"
        ];
        spindleKeys = [
          "gauge"
          "name"
        ];
        wrongKind = null;
        checked = 3;
        discovered = "host";
        rightKind = "host:68f4e0d5b8f248b114d7b39eb48568fae20d6c7a0edd471b0acfc876c4ec24ac";
      };
    };
  # THE GUARD TESTS PRESENCE AND NOTHING ELSE. A value predicate re-derived here would be a second copy
  # of the mint's domain, and the mint's domain is wider than any list gen-schema can see: `tag` is
  # declared `str` (so it is an identity key) and carries a list (which the mint admits).
  flake.tests.identity-hash-for.test-guard-does-not-narrow-the-mint-domain = {
    expr = {
      widgetKeys = genSchema.identityKeysForKind { } widgetKv;
      tagType = builtins.typeOf widgetInst.tag;
      zoneType = builtins.typeOf widgetInst.zone;
      ownKindRecompute = genSchema.identityHashForKind widgetKv widgetInst;
      stamped = widgetInst.id_hash;
    };
    expected = {
      widgetKeys = [
        "name"
        "tag"
        "zone"
      ];
      tagType = "list";
      zoneType = "string";
      ownKindRecompute = "widget:2ac90deb8d5301173437184da67ad8b380acb2dfb1222fe30d39d80120b38a08";
      stamped = "widget:2ac90deb8d5301173437184da67ad8b380acb2dfb1222fe30d39d80120b38a08";
    };
  };
  # THE BOUNDARY. Where the instance CARRIES the candidate's identity key at a value the mint refuses,
  # the answer is the mint's own named refusal, propagated — not `null`. That is a stated terminal
  # state: the domain belongs to the one minting authority, and a consumer iterating over candidates of
  # unknown shape catches it with `tryEval`, which is what separates it from the abort this guard
  # removed.
  flake.tests.identity-hash-for.test-out-of-domain-value-is-the-mints-refusal = {
    expr = {
      sleeveKeys = genSchema.identityKeysForKind { } sleeveKv;
      hostCarriesHook = hostInst ? hook;
      hookType = builtins.typeOf hostInst.hook;
      refusalIsCaught = (builtins.tryEval (genSchema.identityHashForKind sleeveKv hostInst)).success;
      # the live control: without it `refusalIsCaught = false` is satisfied by a `tryEval` that fails
      # on everything.
      controlWellFormed = (builtins.tryEval (genSchema.identityHashForKind hostKv hostInst)).success;
    };
    expected = {
      sleeveKeys = [
        "hook"
        "name"
      ];
      hostCarriesHook = true;
      hookType = "set";
      refusalIsCaught = false;
      controlWellFormed = true;
    };
  };
}
