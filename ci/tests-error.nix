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

  # A kind reached through `mkSchemaOption`'s own construction, for the declaration-key cells below.
  # Going through the published option is what makes those cells measure the guard's PLACEMENT
  # inside `mkSchemaEntryType`'s merge rather than a predicate a test wrapped from outside.
  kindOf =
    args: decl:
    (genMerge.evalModuleTree {
      modules = [
        { options.schema = mkSchemaOption args; }
        { config.schema.host = decl; }
      ];
    }).config.schema.host;

  strOpt = genMerge.mkOption {
    type = genMerge.types.str;
    default = "none";
  };

  # den-hoag-6vgwm. The collection-key collision needs an INSTANCE plane as well as a kind plane:
  # its severe half is that the shadow MOVES `id_hash` — a different node under ADR-0016 ruling 5 —
  # and only a minted instance shows that.
  instanceOf =
    args: decl:
    (genMerge.evalModuleTree {
      modules = [
        {
          options.hosts = mkInstanceRegistry (kindOf args decl) { };
          config.hosts.h1 = {
            name = "h1";
          };
        }
      ];
    }).config.hosts.h1;

  # A control forced WHOLE inside its own `tryEval`. `tryEval` alone stops at WHNF, so a list whose
  # ELEMENT throws escapes the wrapper and the throw then lands outside the `assert` — where the
  # cell's `expectedError` pattern can match it and a refuse-everything implementation scores green.
  forced = v: builtins.tryEval (builtins.deepSeq v v);
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
        # ★ LIVE CONTROL, in the same cell and the same run, and the `tryEval` is load-bearing
        # rather than defensive. Written bare — `assert (mkInstanceRegistry markedHostKind
        # { }).description == "host instances";` — it does NOT discriminate: when the control
        # refuses, its throw IS `_guardMsg`, which is exactly what `expectedError` pins, so a guard
        # that refused everything passes. Measured on the sibling cell in gen-select with the
        # predicate seeded `&& false`: 4/4 green. `tryEval` turns the control's refusal into an
        # `assertion failed`, which matches neither the type nor the message below.
        assert
          let
            control = builtins.tryEval (mkInstanceRegistry markedHostKind { }).description;
          in
          control.success && control.value == "host instances";
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

  # THE KIND-DECLARATION KEY SPACE (den-hoag-nn4). A key on a structured kind declaration that no
  # reader consumes was discarded unread, and the discard was invisible to every instrument this
  # library owns — a typo'd key produced an instance byte-identical to one declared without it,
  # `id_hash` included. Owner-ruled 2026-08-19: `mkSchemaOption` aborts on an unknown kind key, by
  # name. These cells are here rather than under ./tests because `tryEval` discards the message and
  # WHICH key was named is the whole subject: a refusal that misdiagnoses passes a `.success` cell
  # perfectly. The keys the guard must NOT refuse are in `ci/tests/declaration-keys.nix`.
  flake.testsError.declaration-key-refusals = {
    # O1. The key no reader consumes, named — and the live control in the same cell is what makes
    # the green mean something: a guard that refused EVERY declaration would satisfy the
    # `expectedError` below on its own. `tryEval` is load-bearing rather than defensive, because a
    # bare control's own refusal would throw a message this cell's pattern could match.
    test-structured-surplus-key-refuses-by-name = {
      expr =
        assert
          let
            control = builtins.tryEval (builtins.attrNames (kindOf { } { options.role = strOpt; }).options);
          in
          control.success && control.value == [ "role" ];
        builtins.attrNames
          (kindOf { } {
            options.role = strOpt;
            roel = "web";
          }).options;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kind 'host': unrecognised declaration key 'roel'";
      };
    };

    # O1d · PLACEMENT. The guard sits on the merge RESULT, so forcing ANY field of the kind meets
    # it — here `parent`, a read that never touches `.options`. A guard sited on the options
    # introspection instead would leave this cell green on the wrong grounds while O1 still passed.
    test-refusal-fires-without-touching-options = {
      expr =
        (kindOf { } {
          options.role = strOpt;
          parent = "env";
          roel = "web";
        }).parent;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kind 'host': unrecognised declaration key 'roel'";
      };
    };

    # Every offending key is named, not just the first: a three-typo migration is otherwise three
    # round trips. The plural form is a different code path from O1's singular one.
    test-every-offending-key-is-named = {
      expr =
        builtins.attrNames
          (kindOf { } {
            options.role = strOpt;
            roel = "web";
            hsot = "a";
          }).options;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kind 'host': unrecognised declaration keys 'hsot', 'roel'";
      };
    };
  };

  # ★ THE RESERVED DECLARATION KEYS. These two are the exception to the `_` prefix rule, and they
  # are an exception because they are the names gen-schema writes onto the kind value ITSELF — the
  # opposite of the consumer-private metadata the prefix admits. The population is read off the
  # merge result's own key set: `__functor` and `__mint` on the default branch, `__mint` alone on
  # the `mkType` branch, which declares no functor. Measured before the guard existed: a declared
  # `__mint` did not survive and the kind's own mark was byte-identical with and without it, while
  # a declared `__functor` was applied by gen-merge's module classifier and DELETED the rest of the
  # declaration. Same class, same strength and same shape as the three reserved COLLECTION keys
  # `mkAllCollections` already refuses.
  flake.testsError.reserved-declaration-key-refusals = {
    test-mint-is-a-reserved-declaration-key = {
      expr =
        assert
          let
            control = builtins.tryEval (builtins.attrNames (kindOf { } { options.role = strOpt; }).options);
          in
          control.success && control.value == [ "role" ];
        builtins.attrNames
          (kindOf { } {
            options.role = strOpt;
            __mint = "forged";
          }).options;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kind 'host': declaration key '__mint' is reserved — gen-schema writes it onto every kind value and a declared one is discarded unread$";
      };
    };

    # The `mkType` branch mints too, so the reserved door is live there even though clause A stands
    # the unknown-key predicate down for a caller-supplied function. The control is the same schema
    # WITHOUT the reserved key: its caller-owned surplus key must still come through untouched,
    # which is what proves the door is reserved-name-specific rather than a second unknown-key guard.
    test-mint-is-reserved-on-the-mkType-branch-too = {
      expr =
        let
          args = {
            mkType =
              { kind, ... }:
              {
                inherit kind;
                custom = true;
              };
          };
        in
        assert
          let
            control =
              builtins.tryEval
                (kindOf args {
                  options.role = strOpt;
                  unreadByGenSchema = "kept";
                }).custom;
          in
          control.success && control.value;
        (kindOf args {
          options.role = strOpt;
          __mint = "forged";
        }).custom;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kind 'host': declaration key '__mint' is reserved — gen-schema writes it onto every kind value and a declared one is discarded unread$";
      };
    };

    # `__functor` is the second member of the population, and its failure mode is worse than a
    # silent overwrite: gen-merge's module classifier APPLIES a declared one, so the rest of the
    # declaration is deleted. The control below is the same declaration without it, whose option
    # does land — the two arms of that deletion, in one cell.
    test-functor-is-a-reserved-declaration-key = {
      expr =
        assert
          let
            control = builtins.tryEval (builtins.attrNames (kindOf { } { options.role = strOpt; }).options);
          in
          control.success && control.value == [ "role" ];
        builtins.attrNames
          (kindOf { } {
            options.role = strOpt;
            __functor = _: _: { };
          }).options;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kind 'host': declaration key '__functor' is reserved — gen-schema writes it onto every kind value and a declared one is discarded unread$";
      };
    };
  };

  # ★ THE COLLECTION KEY SPACE COLLIDING WITH gen-schema's OWN VOCABULARY (den-hoag-6vgwm). The
  # mirror image of the group above: that door guards a DECLARATION against the vocabulary, this one
  # guards the VOCABULARY against the constructor argument. They cannot cover for each other —
  # `surplusDeclarationKeys`' predicate has `collectionKeys` as a term of its own ALLOW-list, so no
  # collection key can ever be surplus, and the declaration door is blind to every input here.
  #
  # ★ WHY EVERY CELL BELOW SITS ON THE MINT OR THE INSTANCE AND NOT ON `kind.options`. Measured
  # before the door existed: with `collections.options` declared, `attrNames kind.options` reads
  # `[ "role" ]` and `attrNames kind.options.role` reads `[ "_type" "default" "type" ]` — on BOTH
  # arms. The collection value has replaced the introspection and carries the same names and the
  # same shape, so the kind ADVERTISES an option its instances do not have and a cell written on
  # that read passes UNCHANGED through the defect. The two reads that separate the arms are the
  # kind's `__mint` and the instance.
  #
  # ★ AND WHY THE FIXTURES DIFFER BETWEEN CELLS, which is not tidiness. A collision arm is live only
  # if the FIXTURE CARRIES THE COLLIDING KEY — `strippedDefs` can only remove a key a def HAS — so
  # O3's fixture must declare `config`. But that same fat fixture converts O1/O2's subject from a
  # SILENT failure into a LOUD one: with `options` stripped, a declared `config.role` is undeclared
  # and strict mode refuses it on its own. The headline silent arms REQUIRE the lean fixture.
  flake.testsError.collection-key-collision-refusals = {
    # O1 · the shadow at its cheapest plane. LEAN fixture. Before the door this returned
    # `"schemakind:608c5bba…"` against the clean twin's `"schemakind:9b67e15b…"`, with no throw and
    # no warning: `markOf`'s preimage takes `attrNames introspect.options`, and `introspect` is an
    # `evalModuleTree` over defs the collection key has already been stripped from.
    test-marker-collection-refuses-by-name = {
      expr =
        assert
          let
            control = forced (builtins.attrNames (kindOf { } { options.role = strOpt; }).options);
          in
          control.success && control.value == [ "role" ];
        (kindOf {
          collections.options = {
            default = { };
          };
        } { options.role = strOpt; }).__mint.minted;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: collection 'options' is reserved — cannot be used as a collection key$";
      };
    };

    # O2 · THE SEVERE HALF — the shadow moved an INSTANCE IDENTITY. LEAN fixture. Before the door
    # this returned `"host:0da58b39…"` where the clean twin mints `"host:6405e005…"`, and under
    # ADR-0016 ruling 5 that is a different node, propagating into every binding that references it.
    #
    # ★ BOTH CONTROL CONJUNCTS ARE LOAD-BEARING. The digest alone stays satisfied if the mint stops
    # reflecting options at all; `_identityKeys` is the reflected set and is the thing that moved,
    # measured `[ "name" "role" ]` ⇒ `[ "name" ]`.
    test-marker-collection-cannot-move-an-instance-identity = {
      expr =
        assert
          let
            clean = instanceOf { } { options.role = strOpt; };
            id = forced clean.id_hash;
            keys = forced clean._identityKeys;
          in
          id.success
          && id.value == "host:6405e005e418788c6ed366500451c25899c6b853ce1046952d3d6244622a792b"
          && keys.success
          &&
            keys.value == [
              "name"
              "role"
            ];
        (instanceOf {
          collections.options = {
            default = { };
          };
        } { options.role = strOpt; }).id_hash;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: collection 'options' is reserved — cannot be used as a collection key$";
      };
    };

    # O3 · THE CUT IS BY CLASS, NOT BY NAME. `config` is a different member of the same collision and
    # its failure is worse than a moved identity: the strip removes the declaration's `config` block,
    # so a declared value silently reverts to its default. Measured before the door — this returned
    # `"host:6405e005…"`, BYTE-IDENTICAL to an instance of a declaration that never carried `config`
    # at all, while the clean twin mints `"host:5c5feebf…"` and reads `role = "web"`. A door cut at
    # `options` alone passes O1 and O2 and leaves this live.
    test-marker-collection-class-config-refuses-by-name = {
      expr =
        assert
          let
            clean = instanceOf { } {
              options.role = strOpt;
              config.role = "web";
            };
            id = forced clean.id_hash;
            role = forced clean.role;
          in
          id.success
          && id.value == "host:5c5feebf2beb3af5429ab36de21bb24c78491ba8eece8534eb69627111464850"
          && role.success
          && role.value == "web";
        (instanceOf
          {
            collections.config = {
              default = { };
            };
          }
          {
            options.role = strOpt;
            config.role = "web";
          }
        ).id_hash;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: collection 'config' is reserved — cannot be used as a collection key$";
      };
    };
  };
}
