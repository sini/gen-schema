# `evalSchema` — the staged pass, the `inherits` relation, and the `type = "inherits"` edges.
#
# The cells here are the acceptance battery for the relocation: kind composition moves off the
# `imports = [ config.schema.<p> ]` idiom, which reads the tree being declared, onto a pass that
# resolves parents by NAME against the frozen output of strictly earlier passes (ADR-0016 ruling 7).
#
# Every composition cell carries its own discriminator — the same tree with `inherits` dropped —
# because an equality between two arms that agree measures nothing.
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkSchemaOption mkInstanceRegistry;

  str =
    default:
    genMerge.mkOption {
      type = genMerge.types.str;
      inherit default;
    };

  # ── the fixture, in both shapes ──────────────────────────────────────────────────────────────
  # base carries `description`; derived carries `spool` and composes base.

  # HEAD's idiom: the child reads the parent out of the very tree it is being declared in.
  headSpelling =
    (genMerge.evalModuleTree {
      modules = [
        (
          { config, ... }:
          {
            options.schema = mkSchemaOption { };
            config.schema.base.options.description = str "";
            config.schema.derived = {
              imports = [ config.schema.base ];
              options.spool = str "s";
            };
          }
        )
      ];
    }).config.schema;

  # The relocated form: the parent travels as a name, resolved by the pass.
  relModules = withInherit: [
    {
      config.schema.base.options.description = str "";
      config.schema.derived = {
        inherits = if withInherit then [ "base" ] else [ ];
        options.spool = str "s";
      };
    }
  ];

  rel = evalSchema { modules = relModules true; };
  relNoInherit = evalSchema { modules = relModules false; };

  # A registry over a kind value, evaluated far enough to read one instance.
  instanceOf =
    kindValue: opts:
    (genMerge.evalModuleTree {
      modules = [
        {
          options.spools = mkInstanceRegistry kindValue opts;
          config.spools.one = { };
        }
      ];
    }).config.spools.one;

  optionSet = kindValue: builtins.attrNames (instanceOf kindValue { });

  # ── C8: a depth-2 chain — ruling 7's "two levels deep takes two passes" ──────────────────────
  depth2 = evalSchema {
    modules = [
      {
        config.schema.base.options.description = str "";
        config.schema.mid = {
          inherits = [ "base" ];
          options.selvage = str "v";
        };
        config.schema.leaf = {
          inherits = [ "mid" ];
          options.hem = str "h";
        };
      }
    ];
  };

  # ── C10: the consumer's config can no longer decide a kind ───────────────────────────────────
  # At HEAD a knob on the consumer's own tree selects which options a kind declares. In the pass
  # the consumer's option set is not in the tree at all, so the read has nothing to resolve.
  headKnob =
    knob:
    (genMerge.evalModuleTree {
      modules = [
        (
          { config, ... }:
          {
            options.schema = mkSchemaOption { };
            options.knob = genMerge.mkOption {
              type = genMerge.types.bool;
              default = knob;
            };
            config.schema.base =
              if config.knob then { options.hem = str "h"; } else { options.selvage = str "v"; };
          }
        )
      ];
    }).config.schema;

  # ── C14: the relation is queryable ───────────────────────────────────────────────────────────
  fmt = es: map (e: "${e.from}->${toString e.to}:${e.type}") es;

  containment = evalSchema {
    modules = [
      {
        config.schema.base.options.description = str "";
        config.schema.derived = {
          parent = "base";
          options.spool = str "s";
        };
      }
    ];
  };

  # ── C6: `extraModules` is untouched by the relocation ────────────────────────────────────────
  shirring = {
    options.shirring = str "sh";
  };
in
{
  flake.tests.schema-inheritance = {
    # C1 — a child kind's instance option set carries its parent's options.
    test-c1-relocated-composes = {
      expr = optionSet rel.derived;
      expected = optionSet headSpelling.derived;
    };
    test-c1-relocated-option-names = {
      expr = optionSet rel.derived;
      expected = [
        "_identity"
        "_identityKeys"
        "description"
        "id_hash"
        "name"
        "spool"
      ];
    };

    # C2 — THE DISCRIMINATOR for C1. Drop `inherits` and the inherited option goes with it, so
    # C1's equality is a statement about the composition rather than about two default trees.
    test-c2-no-inherit-drops-the-inherited-option = {
      expr = optionSet relNoInherit.derived;
      expected = [
        "_identity"
        "_identityKeys"
        "id_hash"
        "name"
        "spool"
      ];
    };

    # C3 — the parent's option VALUE flows through the child, not merely its name.
    test-c3-parent-value-flows = {
      expr =
        (instanceOf
          (evalSchema {
            modules = [
              {
                config.schema.base.options.description = str "cambric";
                config.schema.derived.inherits = [ "base" ];
              }
            ];
          }).derived
          { }
        ).description;
      expected = "cambric";
    };

    # C5 — the cycle refusal is `tryEval`-CATCHABLE, where HEAD's divergence is not. The MESSAGE
    # is pinned in ci/tests-error.nix, which is the output that can see it.
    test-c5-cycle-refusal-is-catchable = {
      expr =
        (builtins.tryEval (evalSchema {
          modules = [
            {
              config.schema.a.inherits = [ "b" ];
              config.schema.b.inherits = [ "a" ];
            }
          ];
        })).success;
      expected = false;
    };

    # C6 — `extraModules` survives the relocation identically. Its modules are instance-side and
    # are not part of the identity key set; this landing does not move it.
    test-c6-extramodules-survives = {
      expr = builtins.attrNames (instanceOf rel.derived { extraModules = [ shirring ]; });
      expected = [
        "_identity"
        "_identityKeys"
        "description"
        "id_hash"
        "name"
        "shirring"
        "spool"
      ];
    };
    test-c6-extramodules-does-not-move-identity = {
      expr = (instanceOf rel.derived { extraModules = [ shirring ]; }).id_hash;
      expected = (instanceOf rel.derived { }).id_hash;
    };

    # C7 — `mkInstanceRegistry`'s EXISTING demand-time guard is unchanged by this landing. No
    # guard was added to it and none can be (§2.4); the cell exists to show it still refuses.
    test-c7-existing-guard-still-refuses = {
      expr =
        (builtins.tryEval ((mkInstanceRegistry { no = "kind"; } { description = "d"; }).apply { a = { }; }))
        .success;
      expected = false;
    };

    # C8 — a depth-2 chain composes: ruling 7's "a structure two levels deep takes two passes".
    test-c8-depth-2-chain = {
      expr = optionSet depth2.leaf;
      expected = [
        "_identity"
        "_identityKeys"
        "description"
        "hem"
        "id_hash"
        "name"
        "selvage"
      ];
    };

    # C9 — an unknown parent refuses, and it refuses by NAME. Message pinned in tests-error.nix.
    test-c9-unknown-parent-refuses-catchably = {
      expr =
        (builtins.tryEval (evalSchema {
          modules = [ { config.schema.derived.inherits = [ "nosuch" ]; } ];
        })).success;
      expected = false;
    };

    # C10 — a kind can no longer be decided by the consumer's config. Both HEAD arms are driven
    # so the cell shows the capability EXISTED before it shows it is gone.
    test-c10-head-knob-on = {
      expr = builtins.attrNames (headKnob true).base.options;
      expected = [ "hem" ];
    };
    test-c10-head-knob-off = {
      expr = builtins.attrNames (headKnob false).base.options;
      expected = [ "selvage" ];
    };
    # The relocated arm is in ci/tests-error.nix: the read does not merely fail, it fails with
    # `attribute 'knob' missing`, and that message IS the cell — the knob is not refused, it is
    # inexpressible. It does not survive `tryEval`, so it cannot be asserted from here.

    # C11 — the identity stamp does not move, and the oracle can see it move. Asserted
    # RELATIONALLY rather than against a literal digest: the literals in the spec were measured
    # at a different lock, and a hash pinned across a rev boundary is a relayed figure.
    test-c11-stamp-is-unmoved-by-the-relocation = {
      expr = (instanceOf rel.derived { }).id_hash;
      expected = (instanceOf headSpelling.derived { }).id_hash;
    };
    test-c11-discriminator-the-stamp-can-move = {
      expr =
        (instanceOf relNoInherit.derived { }).id_hash == (instanceOf headSpelling.derived { }).id_hash;
      expected = false;
    };

    # C14 — the inheritance relation is QUERYABLE, which is the arc's own requirement that every
    # relation be an edge. At HEAD the composition happened and the graph showed nothing for it.
    test-c14-inherits-edge-is-in-the-unified-view = {
      expr = fmt rel._edges;
      expected = [ "derived->base:inherits" ];
    };
    test-c14-control-containment-is-a-parent-edge = {
      expr = fmt containment._edges;
      expected = [ "derived->base:parent" ];
    };
    test-c14-discriminator-no-inherit-no-edge = {
      expr = fmt relNoInherit._edges;
      expected = [ ];
    };
    # …and the composition is real in the arm that shows the edge, so the edge is not decoration.
    test-c14-composition-is-real = {
      expr = builtins.attrNames rel.derived.options;
      expected = [
        "description"
        "spool"
      ];
    };

    # The pass is invariant under presentation order — ruling 7's first staging obligation,
    # discharged by construction (depth is a function of the name graph alone).
    test-order-invariance = {
      expr =
        builtins.attrNames
          (evalSchema {
            modules = [
              {
                config.schema.derived = {
                  inherits = [ "base" ];
                  options.spool = str "s";
                };
                config.schema.base.options.description = str "";
              }
            ];
          }).derived.options;
      expected = [
        "description"
        "spool"
      ];
    };
  };
}
