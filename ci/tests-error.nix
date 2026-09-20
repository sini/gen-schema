# THE SECOND TEST OUTPUT — cells whose subject is WHICH refusal fired, not that one did.
#
# `builtins.tryEval` answers `{ success = false; value = false; }` and discards the message, so every
# `.success == false` cell under ./tests pins that a refusal happened and nothing about what it said.
# Both cells below exist because a message that misdiagnoses passes such a cell perfectly: the
# `_identity.keys` refusal spent this build's first round telling a caller that a declared option was
# undeclared, and the Q4 cell that covers that input stayed green throughout.
#
# ★ WHY A SECOND OUTPUT RATHER THAN A SECOND SUITE. `gen-harness.lib.mkCi` builds `checks.default`
# from an asserter that evaluates `t.expr == t.expected` UNCONDITIONALLY and quantifies over
# `config.flake.tests` and nothing else. A cell with no `expected` and a throwing `expr` therefore
# CRASHES that batch gate rather than failing it. Hosting these on `flake.testsError` puts them
# outside the asserter's quantifier while keeping them live on the nix-unit path — the wiring
# gen-merge and gen-memo already carry, reached through `mkCi`'s `extraModules`.
#
#   nix-unit --flake ./ci#tests        # the suites
#   nix-unit --flake ./ci#testsError   # these cells
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema)
    mkIdentityModule
    identityKeysForKind
    evalSchema
    mkSchemaOption
    mkInstanceRegistry
    ;

  # A kind value the way a caller actually gets one, for the kind-mark cells below.
  markedHostKind =
    (genMerge.evalModuleTree {
      modules = [
        { options.schema = mkSchemaOption { }; }
        { config.schema.host.options.role = genMerge.mkOption { type = genMerge.types.str; }; }
      ];
    }).config.schema.host;

  # A kind declaring one primitive identity key and one option that is DECLARED but not an identity
  # key. `tags` is the input P3 was measured on: it is declared, so "is not declared" was a lie.
  hostModules = [
    {
      options.name = genMerge.mkOption { type = genMerge.types.str; };
      options.role = genMerge.mkOption { type = genMerge.types.str; };
      options.tags = genMerge.mkOption {
        type = genMerge.types.listOf genMerge.types.str;
        default = [ ];
      };
    }
    {
      config.name = "igloo";
      config.role = "web";
    }
  ];

  keysNaming =
    k:
    (genMerge.evalModuleTree {
      modules = [
        (mkIdentityModule "host" (identityKeysForKind {
          imports = hostModules;
        }))
      ]
      ++ hostModules
      ++ [ { config._identity.keys = [ k ]; } ];
    }).config.id_hash;
in
{
  # evalSchema's two refusals, and the capability the relocation removes. All three are here rather
  # than under ./tests for the same reason the identity cells are: `tryEval` discards the message,
  # and WHICH refusal fired is the subject.
  flake.testsError.schema-inheritance-refusals = {
    # An inheritance cycle refuses by NAME, where HEAD's `imports` idiom diverges into an
    # uncatchable `stack overflow; max-call-depth exceeded`. ADR-0016 ruling 7: a kind may inherit
    # only kinds resolved in a strictly earlier pass, and the substrate refuses by name.
    test-cycle-refuses-by-name = {
      expr = evalSchema {
        modules = [
          {
            config.schema.a.inherits = [ "b" ];
            config.schema.b.inherits = [ "a" ];
          }
        ];
      };
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: inheritance cycle among kinds \\[a b\\] — a kind may inherit only kinds resolved in a strictly earlier pass$";
      };
    };

    # A parent name nothing declares refuses by name too, and names both ends of the edge.
    test-unknown-parent-refuses-by-name = {
      expr = evalSchema {
        modules = [ { config.schema.derived.inherits = [ "nosuch" ]; } ];
      };
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kind 'derived' inherits 'nosuch' which is not a declared kind$";
      };
    };

    # C10's GREEN arm. At HEAD a consumer's own config knob selects which options a kind declares
    # (both arms driven in ci/tests/schema-inheritance.nix, so the capability is shown to have
    # existed). In the pass the consumer's option set is not in the tree at all, so the read has
    # nothing to resolve — the knob is not refused, it is INEXPRESSIBLE.
    test-consumer-config-cannot-decide-a-kind = {
      expr =
        (evalSchema {
          modules = [
            (
              { config, ... }:
              {
                config.schema.base =
                  if config.knob then
                    { options.hem = genMerge.mkOption { type = genMerge.types.str; }; }
                  else
                    { options.selvage = genMerge.mkOption { type = genMerge.types.str; }; };
              }
            )
          ];
        }).base;
      expectedError = {
        type = "EvalError";
        msg = "attribute 'knob' missing";
      };
    };
  };

  flake.testsError.identity-refusals = {
    # P3, on the input that made the predecessor false. `tags` IS declared on this kind, so the
    # message may not say it is not; it names membership and prints the set instead.
    test-explicit-key-declared-but-not-an-identity-key-names-membership = {
      expr = keysNaming "tags";
      expectedError = {
        type = "ThrownError";
        msg = "^_identity\\.keys: 'tags' is not an identity key of kind 'host' \\(identity keys: name, role\\)$";
      };
    };

    # The same wording on a name nothing declares. One message, both arms — which is the whole point
    # of naming membership rather than a cause.
    test-explicit-key-undeclared-names-the-same-membership = {
      expr = keysNaming "nosuchoption";
      expectedError = {
        type = "ThrownError";
        msg = "^_identity\\.keys: 'nosuchoption' is not an identity key of kind 'host' \\(identity keys: name, role\\)$";
      };
    };

    # P1. `name` is RESERVED, not declared: the key set prepends it unconditionally, and
    # `mkInstanceType` is what declares it. A caller reaching `mkIdentityModule` directly is the one
    # party that can hand over an instance without it, and it used to die on a raw
    # `attribute 'name' missing` naming a line in `lib/id-hash.nix`.
    test-reserved-name-undeclared-refuses-by-name = {
      expr =
        let
          noName = [
            {
              options.load = genMerge.mkOption {
                type = genMerge.types.str;
                default = "x";
              };
            }
          ];
        in
        (genMerge.evalModuleTree {
          modules = [
            (mkIdentityModule "host" (identityKeysForKind {
              imports = noName;
            }))
          ]
          ++ noName;
        }).config.id_hash;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: mkIdentityModule: kind 'host' identifies instances by 'name', which this instance does not declare \\(identity keys: load, name\\); 'name' is reserved and is declared by mkInstanceType$";
      };
    };
  };

  # THE PROVENANCE MARK's refusals (ADR-0034). All three are message cells: what changed at this
  # seam is precisely WHICH property the message names, so a cell reading only `.success == false`
  # would have passed at HEAD, where the same input was ADMITTED and the same message was a claim
  # about a predicate that did not check it.
  flake.testsError.kind-mark-refusals = {
    # O5. The stand-in the retired `? kind && ? options` guard admitted — a hand-written attrset
    # with a kind name and an empty option set. At HEAD this built a registry; the message names the
    # mark, and the mark is now what is read.
    test-mkInstanceRegistry-refuses-an-unmarked-kind = {
      expr =
        # LIVE CONTROL, in the same cell and the same run, and it DISCRIMINATES: a guard that
        # refused everything would fail this assert, and an `assertion failed` is neither the type
        # nor the message `expectedError` pins, so the cell reds instead of passing for the wrong
        # reason. A bare `seq` would not do — it would propagate this very message.
        assert (mkInstanceRegistry markedHostKind { }).description == "host instances";
        (mkInstanceRegistry {
          kind = "host";
          options = { };
        } { }).description;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: mkInstanceRegistry: expected a kind value carrying a mint-backed mark \\(`__mint.minted`\\); got an attrset with no mark$";
      };
    };

    # The mark is applied LAST, so a collection named `__mint` would be overwritten silently — the
    # class this substrate refuses by name everywhere else. Sibling of the `__functor` and `kind`
    # refusals in the same derivation.
    test-mint-is-a-reserved-collection-key = {
      expr =
        (genMerge.evalModuleTree {
          modules = [
            {
              options.schema = mkSchemaOption {
                collections.__mint = {
                  default = [ ];
                };
              };
            }
            { config.schema.host = { }; }
          ];
        }).config.schema.host.kind;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: collection '__mint' is reserved — cannot be used as a collection key$";
      };
    };

    # The same door on the OTHER key source that is merged before the stamp. Computed fields win
    # over collections, so a guard on collections alone leaves this half open.
    test-mint-is-a-reserved-computed-field = {
      expr =
        (genMerge.evalModuleTree {
          modules = [
            {
              options.schema = mkSchemaOption {
                computed = _: _: {
                  __mint = "forged";
                };
              };
            }
            { config.schema.host = { }; }
          ];
        }).config.schema.host.__mint;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: computed field '__mint' is reserved — the provenance mark is minted by mkSchemaEntryType$";
      };
    };
  };
}
