# The identity-key set closes at the KIND boundary — an instance-side contribution has nowhere to
# attach, and the recompute reads the same source as the stamp on BOTH kind-value shapes.
#
# The property is not "a contribution is refused". It is that the contribution is INEXPRESSIBLE in an
# identity: the key set was a value before the instance submodule saw a single caller module, so
# `extraModules` can declare whatever it likes and the mint cannot see it. That is why the cells below
# assert EQUALITY across the two arms rather than a throw, and why the arming arm asserts the extra
# option really did land — an `extraModules` that was silently dropped would satisfy the equality just
# as well, and would be the one reading that makes this file worthless.
{
  genSchema,
  genMerge,
  ...
}:
let
  # Eval 1 — the kind, sealed. `role` is contributed to the KIND, which is the inlet that legitimately
  # moves an identity and is not what this file is about.
  kindTree = genMerge.evalModuleTree {
    modules = [
      { options.schema = genSchema.mkSchemaOption { }; }
      { config.schema.host.options.role = genMerge.mkOption { type = genMerge.types.str; }; }
    ];
  };
  hostKind = kindTree.config.schema.host;

  # Eval 2 — the instance, through the registry type. `extraModules` is `mkInstanceType`'s own
  # supported second inlet (`mkInstanceRegistry` forwards its `extraModules` and every `refs` binding
  # module through it), so this is the shape a caller reaches, not a synthetic one.
  instanceWith =
    extraModules: role:
    (genMerge.evalModuleTree {
      modules = [
        {
          options.hosts = genMerge.mkOption {
            type = genMerge.types.attrsOf (
              genSchema.mkInstanceType hostKind {
                inherit extraModules;
                strict = false;
              }
            );
            default = { };
          };
        }
        { config.hosts.igloo.role = role; }
      ];
    }).config.hosts.igloo;

  tagModule = {
    options.tag = genMerge.mkOption {
      type = genMerge.types.str;
      default = "t";
    };
  };

  base = instanceWith [ ] "web";
  withExtra = instanceWith [ tagModule ] "web";
  otherRole = instanceWith [ ] "db";

  # The kind-value shape gen-aspects' `schemaOption` produces: the declarations live in the module the
  # `__functor` imports, and `options` publishes the plane that module declares. gen-aspects is not
  # an input here — it depends on this library — so the shape is reproduced through THE DOOR
  # GEN-ASPECTS ITSELF GOES THROUGH, `mkSchemaOption { mkType = …; }` (`gen-aspects/lib/schema.nix`,
  # binding `schemaOpt`), which is the entry type's mkType ARM. What the cell measures is the SHAPE,
  # which is what the derivation has to be total over; the library that emits it is incidental.
  #
  # ★ IT USED TO BE A HAND-WRITTEN LITERAL, and ADR-0034's mark is why it can no longer be one: a
  # kind value's provenance is now CHECKED, so a literal of that shape is refused by
  # `mkInstanceType` rather than minted — which is the mechanism, not a fixture problem. Driving
  # the real door is strictly more faithful than simulating its output, and it pins the same
  # figures: measured byte-for-byte against the literal it replaces (same identity keys, same empty
  # `options`, same stamped `id_hash`), with the literal's refusal as the live control.
  aspectShapedTree = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = genSchema.mkSchemaOption {
          mkType =
            {
              defs,
              kind,
              ...
            }:
            {
              __functor = _: _: {
                imports = map (d: d.value) defs;
              };
              inherit kind;
            };
        };
      }
      {
        config.schema.thimble.options.spool = genMerge.mkOption {
          type = genMerge.types.str;
          default = "";
        };
      }
    ];
  };
  aspectShapedKind = aspectShapedTree.config.schema.thimble;

  # The control arm: the SAME option set declared the way gen-schema declares one, where `options` is
  # populated. It agreed with the stamp before this change and must still — a cell that only watched
  # the aspect shape could not tell a repair from a uniform break.
  schemaShapedTree = genMerge.evalModuleTree {
    modules = [
      { options.schema = genSchema.mkSchemaOption { }; }
      {
        config.schema.thimble.options.spool = genMerge.mkOption {
          type = genMerge.types.str;
          default = "";
        };
      }
    ];
  };
  schemaShapedKind = schemaShapedTree.config.schema.thimble;

  mintOne =
    kindValue:
    (genMerge.evalModuleTree {
      modules = [
        {
          options.things = genMerge.mkOption {
            type = genMerge.types.attrsOf (
              genSchema.mkInstanceType kindValue {
                strict = false;
              }
            );
            default = { };
          };
        }
        { config.things.pewter.spool = "silk"; }
      ];
    }).config.things.pewter;

  aspectInstance = mintOne aspectShapedKind;
  schemaInstance = mintOne schemaShapedKind;
in
{
  # O1 — the PAIR. One arm with an `extraModules` option and one without, minted from the same kind
  # over the same values. The identity is the same identity, and the closed key set names why.
  flake.tests.identity-key-closure.test-instance-side-option-cannot-enter-the-key-set = {
    expr = {
      base = base.id_hash;
      withExtra = withExtra.id_hash;
      agree = base.id_hash == withExtra.id_hash;
      closedKeys = base._identityKeys;
    };
    expected = {
      base = "host:568a01c7719445b4fc776270ae9baae39c11bd50d7ccf718a3028d7c0a78c869";
      withExtra = "host:568a01c7719445b4fc776270ae9baae39c11bd50d7ccf718a3028d7c0a78c869";
      agree = true;
      closedKeys = [
        "name"
        "role"
      ];
    };
  };

  # THE ARMING ARM. The `extraModules` module above is live — its option is declared and carries its
  # value on the instance. Without this the cell above passes for a construction that dropped the
  # caller's modules on the floor, which is a different library and a worse one.
  flake.tests.identity-key-closure.test-control-extramodules-option-really-lands = {
    expr = {
      value = withExtra.tag;
      absentOnBase = base ? tag;
    };
    expected = {
      value = "t";
      absentOnBase = false;
    };
  };

  # THE SECOND ARMING ARM. The mint is not merely constant: a KIND-declared key still moves the
  # identity, which is the inlet ADR-0016 ruling 5 says an identity is a function of.
  flake.tests.identity-key-closure.test-control-kind-key-still-moves-the-identity = {
    expr = {
      moved = base.id_hash != otherRole.id_hash;
      otherRole = otherRole.id_hash;
    };
    expected = {
      moved = true;
      otherRole = "host:189f15d989c34bcb8eb98bc0209c57574c4f3dff4e66ddcc5808c6577fdfed0e";
    };
  };

  # Q4 — an explicit key set is validated against the CLOSED set, so a name contributed on the
  # instance side is refused. Before the key set closed, this succeeded silently and minted an
  # identity over an option the kind does not have.
  flake.tests.identity-key-closure.test-explicit-key-naming-an-extramodules-option-is-refused = {
    expr =
      (builtins.tryEval
        (genMerge.evalModuleTree {
          modules = [
            {
              options.hosts = genMerge.mkOption {
                type = genMerge.types.attrsOf (
                  genSchema.mkInstanceType hostKind {
                    extraModules = [ tagModule ];
                    strict = false;
                  }
                );
                default = { };
              };
            }
            {
              config.hosts.igloo.role = "web";
              config.hosts.igloo._identity.keys = [ "tag" ];
            }
          ];
        }).config.hosts.igloo.id_hash
      ).success;
    expected = false;
  };

  # §1.6 — the recompute agrees with the stamp on a kind whose declarations live in its `__functor`'s
  # imports and whose `options` is empty. Reading `kindValue.options` answered over `["name"]` alone
  # here, so the sole recompute path disagreed with the carried stamp on every such kind — a reliable
  # "not this kind" for every instance of it, silently.
  flake.tests.identity-key-closure.test-forKind-agrees-with-stamp-on-an-imports-declared-kind = {
    expr = {
      keys = genSchema.identityKeysForKind { } aspectShapedKind;
      kindValueOptions = builtins.attrNames aspectShapedKind.options;
      recomputeMatchesStamp =
        (genSchema.identityHashForKind aspectShapedKind aspectInstance) == aspectInstance.id_hash;
      # Pinned by CONTENTS, not by equality alone: two derivations that both select nothing agree
      # perfectly while every instance collapses to a name-only identity.
      stamped = aspectInstance.id_hash;
    };
    expected = {
      keys = [
        "name"
        "spool"
      ];
      kindValueOptions = [ "spool" ];
      recomputeMatchesStamp = true;
      stamped = "thimble:15c832bc881510c21e80a9635924fc768b837a7ce5544f7a91d82d03d10bf3a8";
    };
  };

  # The control arm of the same object: the gen-schema-declared kind, which agreed before this change
  # and still does. Both shapes now answer the same key set over the same values, so both mint the
  # same identity — the disagreement §1.6 measured was the derivation's, never the kinds'.
  flake.tests.identity-key-closure.test-control-both-kind-value-shapes-mint-alike = {
    expr = {
      keys = genSchema.identityKeysForKind { } schemaShapedKind;
      kindValueOptionsIsPopulated = builtins.attrNames schemaShapedKind.options;
      recomputeMatchesStamp =
        (genSchema.identityHashForKind schemaShapedKind schemaInstance) == schemaInstance.id_hash;
      # The two shapes are two DECLARATIONS, and the stamp carries the declaration's minted identity,
      # so what the shapes agree on is the identity CONTENT: the aspect-shaped instance, recomputed
      # under the schema-shaped kind, is the schema-shaped instance, over one closed key set.
      shapesAgreeOnContent =
        genSchema.identityHashForKind schemaShapedKind aspectInstance == schemaInstance.id_hash;
      shapesAgreeOnKeys = aspectInstance._identityKeys == schemaInstance._identityKeys;
      # …and the stamps decide exactly as `kindEq` does on the pair.
      stampFollowsKindEq =
        (aspectInstance.id_hash == schemaInstance.id_hash)
        == genSchema.kindEq aspectShapedKind schemaShapedKind;
    };
    expected = {
      keys = [
        "name"
        "spool"
      ];
      kindValueOptionsIsPopulated = [ "spool" ];
      recomputeMatchesStamp = true;
      shapesAgreeOnContent = true;
      shapesAgreeOnKeys = true;
      stampFollowsKindEq = true;
    };
  };
}
