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
  inherit (genSchema)
    evalSchema
    mkSchemaOption
    mkInstanceRegistry
    kindEq
    ;

  str =
    default:
    genMerge.mkOption {
      type = genMerge.types.str;
      inherit default;
    };

  # ── the fixture ──────────────────────────────────────────────────────────────────────────────
  # base carries `description`; derived carries `spool` and composes base. The deprecated idiom, the
  # child reading the parent out of the tree it is declared in, is read as `inherits`; its cells
  # are at the end of this file.

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

  rel = evalSchema { } (relModules true);
  relNoInherit = evalSchema { } (relModules false);

  # A registry over a kind value, evaluated far enough to read one instance.
  instanceOf =
    kindValue: opts:
    (genMerge.evalModuleTree { } [
      {
        options.spools = mkInstanceRegistry opts kindValue;
        config.spools.one = { };
      }
    ]).config.spools.one;

  optionSet = kindValue: builtins.attrNames (instanceOf kindValue { });

  # ── C8: a depth-2 chain — ruling 7's "two levels deep takes two passes" ──────────────────────
  depth2 = evalSchema { } [
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

  # ── C10: the consumer's config can no longer decide a kind ───────────────────────────────────
  # At HEAD a knob on the consumer's own tree selects which options a kind declares. In the pass
  # the consumer's option set is not in the tree at all, so the read has nothing to resolve.
  headKnob =
    knob:
    (genMerge.evalModuleTree { } [
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
    ]).config.schema;

  # ── C14: the relation is queryable ───────────────────────────────────────────────────────────
  fmt = es: map (e: "${e.from}->${toString e.to}:${e.type}") es;

  containment = evalSchema { } [
    {
      config.schema.base.options.description = str "";
      config.schema.derived = {
        parent = "base";
        options.spool = str "s";
      };
    }
  ];

  # ── the deprecated spelling: `base` beside the given modules, on a tree built without `evalSchema` ──
  spelledTree =
    modules:
    (genMerge.evalModuleTree { } (
      [
        {
          options.schema = mkSchemaOption { };
          config.schema.base.options.description = str "";
        }
      ]
      ++ modules
    )).config.schema;
  # An `mkType` result that publishes no collections (den-hoag-fwoa8's shape).
  bareMkTypeOpt = mkSchemaOption {
    mkType =
      { defs, ... }:
      {
        __functor =
          _:
          { ... }:
          {
            imports = map (d: d.value) defs;
          };
      };
  };
  # The same result publishing its collections.
  publishedMkTypeOpt = mkSchemaOption {
    mkType =
      { defs, collections, ... }:
      {
        __functor =
          _:
          { ... }:
          {
            imports = map (d: d.value) defs;
          };
      }
      // collections;
  };

  # ── den-hoag-8c8pr: the plain tree's desugar ─────────────────────────────────────────────────
  plainTree =
    modules:
    (genMerge.evalModuleTree { } ([ { options.schema = mkSchemaOption { }; } ] ++ modules))
    .config.schema;
  # `derived` beside `spelledTree`'s `base`: declaring its parents, or spelling `base`
  declaredDerived = inh: {
    config.schema.derived = {
      inherits = inh;
      options.spool = str "s";
    };
  };
  spelledDerived = [
    (
      { config, ... }:
      {
        config.schema.derived = {
          imports = [ config.schema.base ];
          options.spool = str "s";
        };
      }
    )
  ];
  # every observable of the pair: instance keys, option names, `inherits`, both marks, the
  # instance's `id_hash`, and the edges
  observe = s: {
    inst = optionSet s.derived;
    opts = builtins.attrNames s.derived.options;
    inherits = s.derived.inherits;
    mark = s.derived.__mint.minted;
    idHash = (instanceOf s.derived { }).id_hash;
    baseMark = s.base.__mint.minted;
    edges = s._edges;
  };
  # a 3-chain c -> b -> a, declared
  chainDecl = {
    config.schema.a.options.w = str "";
    config.schema.b = {
      inherits = [ "a" ];
      options.x = str "";
    };
    config.schema.c = {
      inherits = [ "b" ];
      options.y = str "";
    };
  };
  chainObs = s: {
    inst = optionSet s.c;
    mark = s.c.__mint.minted;
    idHash = (instanceOf s.c { }).id_hash;
  };
  # a diamond d -> {b, c} -> a, declared or spelled
  diamondDecl =
    spell:
    { config, ... }:
    let
      up = ps: if spell then { imports = map (p: config.schema.${p}) ps; } else { inherits = ps; };
    in
    {
      config.schema.a.options.w = str "";
      config.schema.b = up [ "a" ] // {
        options.x = str "";
      };
      config.schema.c = up [ "a" ] // {
        options.y = str "";
      };
      config.schema.d =
        up [
          "b"
          "c"
        ]
        // {
          options.z = str "";
        };
    };
  # gen-aspects' `mkType` shape: the functor ignores `self`, and `__defsModule` is built from the defs
  aspectsShaped =
    (genMerge.evalModuleTree { } [
      {
        options.schema = mkSchemaOption {
          mkType =
            { defs, collections, ... }:
            let
              defsModules = map (d: d.value) (builtins.filter (d: builtins.isAttrs d.value) defs);
            in
            {
              __functor =
                _:
                { ... }:
                {
                  imports = defsModules;
                };
              __defsModule.imports = defsModules;
            }
            // collections;
        };
        config.schema.base.options.description = str "";
      }
      (declaredDerived [ "base" ])
    ]).config.schema.derived;
  # two trees, each with a kind `a` that composes a parent of its own
  twoTreesA = {
    one =
      (plainTree [
        (
          { config, ... }:
          {
            config.schema.p.options.o_p = str "p";
            config.schema.a = {
              imports = [ config.schema.p ];
              options.o_a = str "a";
            };
          }
        )
      ]).a;
    two =
      (plainTree [
        (
          { config, ... }:
          {
            config.schema.q.options.o_q = str "q";
            config.schema.a = {
              imports = [ config.schema.q ];
              options.other = str "s2";
            };
          }
        )
      ]).a;
  };

  # one generator, applied twice: the same source positions, parent names and option names
  oneGenerator =
    x:
    (plainTree [
      (
        { config, ... }:
        {
          config.schema.p.options.o_p = str "p";
          config.schema.a = {
            imports = [ config.schema.p ];
            options.o_a = str x;
          };
        }
      )
    ]).a;

  # The kind-shaped stand-in the path fixtures spell (ci/test-fixtures/cxlc0/kind-shaped.nix).
  standIn = import ../test-fixtures/cxlc0/kind-shaped.nix;

  spelledRecord =
    modules:
    let
      s = spelledTree modules;
    in
    {
      inherit (s.derived) inherits;
      options = builtins.attrNames s.derived.options;
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
      expr = builtins.elem "description" (optionSet rel.derived);
      expected = true;
    };
    # The path member the spelling's walk imports: a path to an ordinary module still composes.
    test-path-module-member-composes = {
      expr =
        builtins.attrNames
          (evalSchema { } [
            {
              config.schema.derived.imports = [
                (builtins.toFile "cxlc0-module-path.nix" "{ options.bolt = { }; }")
              ];
              config.schema.derived.options.spool = str "s";
            }
          ]).derived.options;
      expected = [
        "bolt"
        "spool"
      ];
    };
    # The walk the spelling makes through imported files: a two-file cycle terminates (each file is
    # walked once, keyed by its path) and composes; an ordinary nested file tree composes.
    test-path-cycle-composes = {
      expr =
        builtins.attrNames
          (evalSchema { } [ { config.schema.derived.imports = [ ../test-fixtures/cxlc0/cycle-a.nix ]; } ])
          .derived.options;
      expected = [
        "warp"
        "weft"
      ];
    };
    test-path-tree-composes = {
      expr =
        builtins.attrNames
          (evalSchema { } [ { config.schema.derived.imports = [ ../test-fixtures/cxlc0/tree-mid.nix ]; } ])
          .derived.options;
      expected = [
        "hem"
        "selvedge"
      ];
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
          (evalSchema { } [
            {
              config.schema.base.options.description = str "cambric";
              config.schema.derived.inherits = [ "base" ];
            }
          ]).derived
          { }
        ).description;
      expected = "cambric";
    };

    # C5 — the cycle refusal is `tryEval`-CATCHABLE, where HEAD's divergence is not. The MESSAGE
    # is pinned in ci/tests-error.nix, which is the output that can see it.
    test-c5-cycle-refusal-is-catchable = {
      expr =
        (builtins.tryEval (
          evalSchema { } [
            {
              config.schema.a.inherits = [ "b" ];
              config.schema.b.inherits = [ "a" ];
            }
          ]
        )).success;
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
        (builtins.tryEval ((mkInstanceRegistry { description = "d"; } { no = "kind"; }).apply { a = { }; }))
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
        (builtins.tryEval (evalSchema { } [ { config.schema.derived.inherits = [ "nosuch" ]; } ])).success;
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

    # C11 — the oracle can see the identity move. Asserted RELATIONALLY rather than against a
    # literal digest: a hash pinned across a rev boundary is a relayed figure. Dropping the
    # inheritance drops `description` from the key set, and the stamp moves with it.
    test-c11-discriminator-the-stamp-can-move = {
      expr = {
        keySetMoves =
          (instanceOf relNoInherit.derived { })._identityKeys != (instanceOf rel.derived { })._identityKeys;
        stampMoves = (instanceOf relNoInherit.derived { }).id_hash != (instanceOf rel.derived { }).id_hash;
      };
      expected = {
        keySetMoves = true;
        stampMoves = true;
      };
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
          (evalSchema { } [
            {
              config.schema.derived = {
                inherits = [ "base" ];
                options.spool = str "s";
              };
              config.schema.base.options.description = str "";
            }
          ]).derived.options;
      expected = [
        "description"
        "spool"
      ];
    };

    # ── THE DEPRECATED SPELLING, READ AS `inherits` (den-hoag-cxlc0) ───────────────────────────
    # A kind VALUE in a kind entry's `imports` records in `inherits` the entry `inherits = [ <value> ]`
    # would (den-hoag-l0y K1): its name when it is the tree's own kind, the value itself when it is
    # foreign. It still composes where it is written. Each cell reads a tree built WITHOUT
    # `evalSchema`, the shape den v1 declares. The warning it prints is not readable here.
    test-deprecated-spelling-reads-as-inherits = {
      expr = spelledRecord [
        (
          { config, ... }:
          {
            config.schema.derived = {
              imports = [ config.schema.base ];
              options.spool = str "s";
            };
          }
        )
      ];
      expected = {
        inherits = [ "base" ];
        options = [
          "description"
          "spool"
        ];
      };
    };
    # An imported file is walked in turn: a kind two files down is read (fixtures in
    # ci/test-fixtures/cxlc0). The fixture's kind is kind-SHAPED, not a module, so nothing composes;
    # its mark is not the mark of any kind the tree holds, so it is foreign and recorded as the value.
    test-deprecated-nested-path-spelling-reads-as-inherits = {
      expr = spelledRecord [
        { config.schema.derived.imports = [ ../test-fixtures/cxlc0/nested-kind-top.nix ]; }
      ];
      expected = {
        inherits = [ standIn ];
        options = [ ];
      };
    };
    # Two files importing one kind file: the file is walked once, and the name is recorded once.
    test-deprecated-diamond-path-spelling-reads-as-inherits = {
      expr = spelledRecord [
        {
          config.schema.derived.imports = [
            ../test-fixtures/cxlc0/diamond-left.nix
            ../test-fixtures/cxlc0/diamond-right.nix
          ];
        }
      ];
      expected = {
        inherits = [ standIn ];
        options = [
          "left"
          "right"
        ];
      };
    };
    test-deprecated-path-spelling-reads-as-inherits = {
      expr = spelledRecord [
        {
          config.schema.derived.imports = [
            (builtins.toFile "cxlc0-kind-path.nix" ''{ kind = "base"; __mint.minted = "m"; }'')
          ];
        }
      ];
      expected = {
        inherits = [ standIn ];
        options = [ ];
      };
    };
    # THE EQUIVALENCE: the spelling on a plain tree is the same kind as a hand-written `inherits`
    # resolved by `evalSchema` — same mark, same instance identity.
    test-deprecated-spelling-is-the-inherits-kind = {
      expr =
        let
          spelled = spelledTree [
            (
              { config, ... }:
              {
                config.schema.derived = {
                  imports = [ config.schema.base ];
                  options.spool = str "s";
                };
              }
            )
          ];
        in
        {
          mark = spelled.derived.__mint.minted == rel.derived.__mint.minted;
          idHash = (instanceOf spelled.derived { }).id_hash == (instanceOf rel.derived { }).id_hash;
        };
      expected = {
        mark = true;
        idHash = true;
      };
    };

    # den-hoag-fwoa8: an `mkType` kind whose result publishes no collections still carries its
    # declared parents, so `evalSchema` resolves them and the parent's option reaches an instance.
    # The discriminator is the same tree with `inherits` dropped.
    test-mktype-without-collections-composes =
      let
        s = withInherit: evalSchema { schemaOption = bareMkTypeOpt; } (relModules withInherit);
      in
      {
        expr = {
          inherits = (s true).derived.inherits;
          composed = builtins.elem "description" (optionSet (s true).derived);
          discriminator = builtins.elem "description" (optionSet (s false).derived);
        };
        expected = {
          inherits = [ "base" ];
          composed = true;
          discriminator = false;
        };
      };

    # den-hoag-8c8pr, S1: the same kind shape carries its `parent`, so `_topology` reads the declared
    # container rather than `null`. The discriminator is a published-collections `mkType`, which
    # read it before.
    test-mktype-without-collections-publishes-parent = {
      expr =
        (genMerge.evalModuleTree { } [
          {
            options.schema = bareMkTypeOpt;
            config.schema.host = { };
            config.schema.user.parent = "host";
          }
        ]).config.schema._topology.user.parent;
      expected = "host";
    };

    # The resolved kind reads the parent through every route the unresolved one refuses on
    # (tests-error): its functor applied by hand and evaluated as a module.
    test-mktype-without-collections-composes-through-the-functor =
      let
        k = (evalSchema { schemaOption = bareMkTypeOpt; } (relModules true)).derived;
      in
      {
        expr = builtins.elem "description" (
          builtins.attrNames (genMerge.evalModuleTree { } [ (k.__functor k) ]).options
        );
        expected = true;
      };

    # ── den-hoag-8c8pr: a declared `inherits` on a plain tree (one `evalSchema` did not build) ─────
    # It means what `imports = [ config.schema.<p> ]` means there: it is desugared onto the same
    # import, so the parent composes. Its declaration reads as before.
    test-plain-inherits-reads-its-declaration-and-composes =
      let
        t = spelledTree [ (declaredDerived [ "base" ]) ];
      in
      {
        expr = {
          inherits = t.derived.inherits;
          kind = t.derived.kind;
          kinds = t._kindNames;
          options = builtins.attrNames t.derived.options;
        };
        expected = {
          inherits = [ "base" ];
          kind = "derived";
          kinds = [
            "base"
            "derived"
          ];
          options = [
            "description"
            "spool"
          ];
        };
      };

    # Cell (2): the declaration IS the spelling on a plain tree — every observable byte-identical.
    # The discriminator is the same tree declaring no parent.
    test-plain-inherits-is-the-import = {
      expr = {
        same =
          observe (spelledTree [ (declaredDerived [ "base" ]) ]) == observe (spelledTree spelledDerived);
        discriminator =
          observe (spelledTree [ (declaredDerived [ ]) ]) == observe (spelledTree spelledDerived);
      };
      expected = {
        same = true;
        discriminator = false;
      };
    };

    # Cell (3): the plain desugar composes the kind `evalSchema` stages — the pair, and a 3-chain's
    # mark and instance identity.
    test-plain-inherits-is-the-staged-kind = {
      expr = {
        pair = observe (spelledTree [ (declaredDerived [ "base" ]) ]) == observe rel;
        chain = chainObs (plainTree [ chainDecl ]) == chainObs (evalSchema { } [ chainDecl ]);
      };
      expected = {
        pair = true;
        chain = true;
      };
    };

    # The `mkType` branch composes the desugared parent too: a result publishing no collections and
    # one publishing them.
    test-plain-inherits-composes-mktype = {
      expr =
        map
          (
            so:
            builtins.attrNames
              (genMerge.evalModuleTree { } [
                { options.schema = so; }
                { config.schema.base.options.description = str ""; }
                (declaredDerived [ "base" ])
              ]).config.schema.derived.options
          )
          [
            bareMkTypeOpt
            publishedMkTypeOpt
          ];
      expected = [
        [
          "description"
          "spool"
        ]
        [
          "description"
          "spool"
        ]
      ];
    };

    # The reads that bypass `options` (gen-aspects' `mkType` shape: a functor that ignores `self`,
    # and a `__defsModule` built from the defs) compose the parent too: the desugared def is one of
    # the defs the caller's `mkType` receives.
    test-plain-inherits-composes-through-the-functor = {
      expr = builtins.elem "description" (
        builtins.attrNames (genMerge.evalModuleTree { } [ (aspectsShaped.__functor aspectsShaped) ]).options
      );
      expected = true;
    };
    test-plain-inherits-composes-imported-as-a-module = {
      expr = builtins.elem "description" (
        builtins.attrNames (genMerge.evalModuleTree { } [ aspectsShaped ]).options
      );
      expected = true;
    };
    test-plain-inherits-composes-through-a-caller-field = {
      expr = builtins.elem "description" (
        builtins.attrNames (genMerge.evalModuleTree { } [ aspectsShaped.__defsModule ]).options
      );
      expected = true;
    };

    # A diamond (`d` inherits `b` and `c`, both inherit `a`) composes each parent once, and the
    # plain tree, `evalSchema` and the spelling agree.
    test-plain-diamond-composes = {
      expr =
        let
          plain = optionSet (plainTree [ (diamondDecl false) ]).d;
        in
        {
          inherit plain;
          staged = plain == optionSet (evalSchema { } [ (diamondDecl false) ]).d;
          spelled = plain == optionSet (plainTree [ (diamondDecl true) ]).d;
        };
      expected = {
        plain = [
          "_identity"
          "_identityKeys"
          "id_hash"
          "name"
          "w"
          "x"
          "y"
          "z"
        ];
        staged = true;
        spelled = true;
      };
    };

    # ── the kind value publishes its parents and its witness (8c8pr Q-b arm (i), 2026-09-30) ─────
    # `__kindImports` holds the parent kind VALUES in either spelling; the cycle walk reads them.
    test-kind-value-publishes-its-parents = {
      expr = {
        declared = map (k: k.kind) (spelledTree [ (declaredDerived [ "base" ]) ]).derived.__kindImports;
        spelled = map (k: k.kind) (spelledTree spelledDerived).derived.__kindImports;
        root = (spelledTree spelledDerived).base.__kindImports;
      };
      expected = {
        declared = [ "base" ];
        spelled = [ "base" ];
        root = [ ];
      };
    };
    # Two trees' same-named kinds that each compose a parent carry two marks, so two module keys, and
    # both compose where one instance imports both; and a kind importing another tree's same-named
    # kind is not a cycle (the cycle walk compares witnesses, which differ too).
    test-same-named-kinds-of-two-trees-both-compose = {
      expr =
        builtins.attrNames
          (genMerge.evalModuleTree { } [
            twoTreesA.one
            twoTreesA.two
          ]).options;
      expected = [
        "o_a"
        "o_p"
        "o_q"
        "other"
      ];
    };
    # ONE generator applied twice, its two `a`s differing only in an option default (open content,
    # entered into the mark by path): they share a mark, so a module key. Imported side by side
    # outside any kind, gen-merge's key dedup applies the kind's published comparison (`__keyEq`), the
    # one a kind reaching both makes (`kind-lineage-refusals`): two constructions are refused in both
    # orders, and with equal values too, since a sealed component compares by its seal. The one
    # construction imported twice is one module; one instance alone is the control. The by-name text
    # is `kind-instance-collision` in `ci/tests-error.nix`.
    test-one-generator-applied-twice-is-compared-at-the-key = {
      expr =
        let
          o_a =
            modules:
            let
              r = builtins.tryEval (genMerge.evalModuleTree { } modules).config.o_a;
            in
            if r.success then r.value else "REFUSED";
          one = oneGenerator "one";
        in
        {
          sameWitness = (oneGenerator "one").__kindWitness == (oneGenerator "two").__kindWitness;
          oneThenTwo = o_a [
            (oneGenerator "one")
            (oneGenerator "two")
          ];
          twoThenOne = o_a [
            (oneGenerator "two")
            (oneGenerator "one")
          ];
          equalValues = o_a [
            (oneGenerator "one")
            (oneGenerator "one")
          ];
          oneConstructionTwice = o_a [
            one
            one
          ];
          alone = o_a [ (oneGenerator "two") ];
        };
      expected = {
        sameWitness = true;
        oneThenTwo = "REFUSED";
        twoThenOne = "REFUSED";
        equalValues = "REFUSED";
        oneConstructionTwice = "one";
        alone = "two";
      };
    };
    # The module a parent-composing kind publishes carries `__keyEq` as module SYNTAX: it is
    # structured, and every top-level key is one gen-merge reads structurally. A shorthand module
    # hands a key its engine does not know to config, so under a gen-merge predating the protocol
    # `__keyEq` became an instance value (silent on a freeform kind, a STRICT MODE refusal on a
    # strict one) where a structured module is refused by name.
    test-the-keyed-kind-module-is-structured = {
      expr =
        let
          m = rel.derived { };
        in
        {
          publishesKeyEq = m ? __keyEq;
          structured = builtins.any (k: m ? ${k}) genMerge.moduleSyntax.structuring;
          surplus = builtins.attrNames (builtins.removeAttrs m genMerge.moduleSyntax.structured);
        };
      expected = {
        publishesKeyEq = true;
        structured = true;
        surplus = [ ];
      };
    };
    test-another-trees-same-named-kind-is-not-a-cycle = {
      expr =
        builtins.attrNames
          (spelledTree [ { config.schema.a.imports = [ twoTreesA.two ]; } ]).a.options;
      expected = [
        "o_q"
        "other"
      ];
    };
  };
}
