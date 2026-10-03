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
  genAlgebra,
  genIdentity,
  genGraph,
  prelude,
  ...
}:
let
  inherit (genSchema)
    mkIdentityModule
    identityKeysForKind
    evalSchema
    mkSchemaOption
    mkSchemaEntryType
    mkFieldValidator
    mkMixin
    mkInstanceRegistry
    ;

  # An `mkType` whose result publishes no collections and whose functor ignores `self`.
  bareMkType =
    { defs, ... }:
    {
      __functor =
        _:
        { ... }:
        {
          imports = map (d: d.value) defs;
        };
    };
  # A plain tree: the schema option declared in the caller's own module pass (den v1's shape).
  plainTreeWith =
    schemaOption: modules:
    (genMerge.evalModuleTree {
      modules = [ { options.schema = schemaOption; } ] ++ modules;
    }).config.schema;
  plainTree = plainTreeWith (mkSchemaOption { });
  # A kind graph, name -> parents, each kind declaring its own option `o_<name>`: the parents
  # declared, or written in the deprecated spelling.
  declaredKinds = g: [
    {
      config.schema = builtins.mapAttrs (n: ps: {
        inherits = ps;
        options."o_${n}" = genMerge.mkOption { type = genMerge.types.str; };
      }) g;
    }
  ];
  spelledKinds = g: [
    (
      { config, ... }:
      {
        config.schema = builtins.mapAttrs (n: ps: {
          imports = map (p: config.schema.${p}) ps;
          options."o_${n}" = genMerge.mkOption { type = genMerge.types.str; };
        }) g;
      }
    )
  ];
  # `a` declares `b`; `b` spells `a`
  mixedCycle = [
    (
      { config, ... }:
      {
        config.schema.a.inherits = [ "b" ];
        config.schema.b.imports = [ config.schema.a ];
      }
    )
  ];

  # The door table door-checks.nix also reads, for the doors' own valid fixtures — the message
  # goldens below apply the same rows' violations, so a row edited there cannot drift from what is
  # pinned here.
  doors = import ./doors.nix { inherit genSchema genMerge; };

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

  # The door takes the KIND DECLARATION: the head of `hostModules` is declared as the kind `host`
  # through `evalSchema`, and the tail is the instance's definitions (ci/tests/identity-hash.nix).
  kindOfModules =
    decl:
    (evalSchema {
      modules = [ { config.schema.host = decl; } ];
    }).host;
  identityEval =
    modules: extra:
    let
      kindValue = kindOfModules (builtins.head modules);
    in
    genMerge.evalModuleTree {
      modules = [ (mkIdentityModule kindValue (identityKeysForKind { } kindValue)) ] ++ modules ++ extra;
    };

  keysNaming = k: (identityEval hostModules [ { config._identity.keys = [ k ]; } ]).config.id_hash;

  # The same door handed a NAME. `stamp` forces `id_hash`; `keys` reads only `_identity.keys`,
  # which never reaches the stamp — the shape on which a door refusing only at the stamp would
  # admit the name silently.
  byName =
    (genMerge.evalModuleTree {
      modules = [ (mkIdentityModule "host" [ "name" ]) ] ++ hostModules;
    }).config;

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

  # den-hoag-zijk1. A refined port option, and one instance's `myPort` under a kind declared as
  # `decl` — the instance plane is where a refinement contract is enforced or silently is not.
  portOpt = genMerge.mkOption {
    type = genSchema.refined genMerge.types.int genSchema.refinements.tcpPort;
  };
  portOf =
    decl: port:
    (genMerge.evalModuleTree {
      modules = [
        { options.hosts = mkInstanceRegistry (kindOf { } decl) { }; }
        { config.hosts.a.myPort = port; }
      ];
    }).config.hosts.a.myPort;
in
{
  # evalSchema's two refusals, one of them reached through the deprecated spelling. They are here rather
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

    # cxlc0, the deprecated spelling: a kind CYCLE written in that spelling refuses by name, never
    # recursing. Reading the spelling as `inherits` FORCES each spelled kind's mark (den-hoag-l0y:
    # telling the tree's own kind from a foreign one decides by mark and `kindEq`), and `evalSchema`
    # reads `inherits` on pass 0, so the cycle partner's own guard refuses first, in the entry
    # type's wording with the path, before `evalSchema`'s name graph is reached. The members are the
    # same `[a b]`.
    test-deprecated-spelling-cycle-refuses-by-name = {
      expr = evalSchema {
        modules = [
          (
            { config, ... }:
            {
              config.schema.a.imports = [ config.schema.b ];
              config.schema.b.imports = [ config.schema.a ];
            }
          )
        ];
      };
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kind 'a' reaches a kind with its own content witness through its parents \\(a -> b -> a\\), among kinds \\[a b\\]: either it inherits itself, an inheritance cycle, and a kind may inherit only kinds resolved in a strictly earlier pass; or two kinds named 'a' were declared from one source with the same parent names and the same directly declared option names, which the witness does not tell apart before composition, and giving each such module value its own `_file` separates them \\(a module imported by path takes its file from the path: import it as a value, or give each application a distinct path\\)$";
      };
    };

    # den-hoag-8c8pr: on a plain tree a declared `inherits` desugars onto the import the deprecated
    # spelling makes, so a parent nothing declares has nothing to import and is refused by
    # `evalSchema`'s own words, where the parent's options would be read and on the edge view.
    test-plain-undeclared-parent-refuses-by-name = {
      expr = (plainTree [ { config.schema.derived.inherits = [ "nosuch" ]; } ]).derived.options;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kind 'derived' inherits 'nosuch' which is not a declared kind$";
      };
    };
    test-plain-undeclared-parent-refuses-the-edge-view = {
      expr = (plainTree [ { config.schema.derived.inherits = [ "nosuch" ]; } ])._edges;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kind 'derived' inherits 'nosuch' which is not a declared kind$";
      };
    };

    # An entry type built OUTSIDE a kind tree has no tree to read a declared parent off, so the
    # parent is refused by name rather than dropped.
    test-treeless-entry-refuses-by-name = {
      expr =
        (genMerge.evalModuleTree {
          modules = [
            {
              options.kinds = genMerge.mkOption {
                type = genMerge.types.lazyAttrsOf (mkSchemaEntryType { });
              };
              config.kinds.base = { };
              config.kinds.derived.inherits = [ "base" ];
            }
          ];
        }).config.kinds.derived.options;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kind 'derived' inherits 'base', but nothing resolved it: this entry type was built outside a kind tree, so there is no parent to read. Declare the kind through `mkSchemaOption` or `evalSchema`$";
      };
    };

    # den-hoag-8c8pr, S1: an `mkType` kind whose result publishes no collections still carries its
    # `parent`, so an undeclared one is refused by the topology instead of reading as no parent.
    test-mktype-undeclared-parent-refuses-by-name = {
      expr =
        (genMerge.evalModuleTree {
          modules = [
            {
              options.schema = mkSchemaOption { mkType = bareMkType; };
              config.schema.user.parent = "nosuch";
            }
          ];
        }).config.schema._topology.user;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kind 'user' declares parent 'nosuch' which is not a declared kind$";
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

  # THE INHERITANCE-CYCLE REFUSAL ON A PLAIN TREE, both spellings under one walk (8c8pr Q-b arm (i),
  # 2026-09-30): a kind that reaches itself through its parents, declared (`inherits`, desugared onto
  # the import) or spelled (`imports = [ config.schema.<p> ]`), is refused by name in `evalSchema`'s
  # wording, where the module system would otherwise recurse uncatchably. The members are named in
  # sorted order (`evalSchema`'s bracket, whichever member is read), with the path from the kind read.
  flake.testsError.plain-inheritance-cycle-refusals =
    let
      msg =
        members: path: kind:
        "^gen-schema: kind '${kind}' reaches a kind with its own content witness through its parents \\(${path}\\), among kinds \\[${members}\\]: either it inherits itself, an inheritance cycle, and a kind may inherit only kinds resolved in a strictly earlier pass; or two kinds named '${kind}' were declared from one source with the same parent names and the same directly declared option names, which the witness does not tell apart before composition, and giving each such module value its own `_file` separates them \\(a module imported by path takes its file from the path: import it as a value, or give each application a distinct path\\)$";
      refuses = members: path: kind: {
        type = "ThrownError";
        msg = msg members path kind;
      };
    in
    {
      test-declared-2-cycle = {
        expr =
          (plainTree (declaredKinds {
            a = [ "b" ];
            b = [ "a" ];
          })).a.options;
        expectedError = refuses "a b" "a -> b -> a" "a";
      };
      test-spelled-2-cycle = {
        expr =
          (plainTree (spelledKinds {
            a = [ "b" ];
            b = [ "a" ];
          })).a.options;
        expectedError = refuses "a b" "a -> b -> a" "a";
      };
      test-declared-self-cycle = {
        expr =
          (plainTree (declaredKinds {
            a = [ "a" ];
          })).a.options;
        expectedError = refuses "a" "a -> a" "a";
      };
      test-spelled-self-cycle = {
        expr =
          (plainTree (spelledKinds {
            a = [ "a" ];
          })).a.options;
        expectedError = refuses "a" "a -> a" "a";
      };
      test-declared-3-cycle = {
        expr =
          (plainTree (declaredKinds {
            a = [ "b" ];
            b = [ "c" ];
            c = [ "a" ];
          })).a.options;
        expectedError = refuses "a b c" "a -> b -> c -> a" "a";
      };
      test-spelled-3-cycle = {
        expr =
          (plainTree (spelledKinds {
            a = [ "b" ];
            b = [ "c" ];
            c = [ "a" ];
          })).a.options;
        expectedError = refuses "a b c" "a -> b -> c -> a" "a";
      };
      # one edge declared, one spelled, read from either end
      test-mixed-cycle-from-the-declaring-end = {
        expr = (plainTree mixedCycle).a.options;
        expectedError = refuses "a b" "a -> b -> a" "a";
      };
      test-mixed-cycle-from-the-spelling-end = {
        expr = (plainTree mixedCycle).b.options;
        expectedError = refuses "a b" "b -> a -> b" "b";
      };
      # the declared 2-cycle read from `b`: the bracket is sorted, so it is `evalSchema`'s `[a b]`
      # from either end, and only the path starts where the read did
      test-declared-2-cycle-from-the-other-end = {
        expr =
          (plainTree (declaredKinds {
            a = [ "b" ];
            b = [ "a" ];
          })).b.options;
        expectedError = refuses "a b" "b -> a -> b" "b";
      };
      # a kind that reaches a cycle without being on it composes the cycle's first member, which
      # refuses: the cycle is named, never the kind that merely reached it
      test-a-kind-reaching-a-cycle-names-the-cycle = {
        expr =
          (plainTree (declaredKinds {
            x = [ "a" ];
            a = [ "b" ];
            b = [ "a" ];
          })).x.options;
        expectedError = refuses "a b" "a -> b -> a" "a";
      };
      # the same refusal on the `mkType` branch, read through the caller's functor
      test-declared-2-cycle-mktype =
        let
          k =
            (plainTreeWith (mkSchemaOption { mkType = bareMkType; }) (declaredKinds {
              a = [ "b" ];
              b = [ "a" ];
            })).a;
        in
        {
          expr = builtins.attrNames (genMerge.evalModuleTree { modules = [ (k.__functor k) ]; }).options;
          expectedError = refuses "a b" "a -> b -> a" "a";
        };
    };

  # A SAME-TREE CYCLE IN THE VALUE SPELLING (den-hoag-l0y G1): `inherits = [ config.schema.b ]` is the
  # name `b` (F4), and telling it from a foreign value forces both marks, so a walk over the
  # CLASSIFIED parents would need the cycle's own composition and recurse uncatchably. The walk reads
  # every kind's parents as written (`__kindCycleParents`), so each shape refuses by name, on a plain
  # tree and under `evalSchema` (whose pass 0 reads `inherits`, so the partner's guard fires first).
  flake.testsError.same-tree-value-cycle-refusals =
    let
      refuses = members: path: kind: {
        type = "ThrownError";
        msg = "^gen-schema: kind '${kind}' reaches a kind with its own content witness through its parents \\(${path}\\), among kinds \\[${members}\\]: either it inherits itself, an inheritance cycle, and a kind may inherit only kinds resolved in a strictly earlier pass; or two kinds named '${kind}' were declared from one source with the same parent names and the same directly declared option names, which the witness does not tell apart before composition, and giving each such module value its own `_file` separates them \\(a module imported by path takes its file from the path: import it as a value, or give each application a distinct path\\)$";
      };
      written = f: [ ({ config, ... }: { config.schema = f config.schema; }) ];
      val2 = s: {
        a.inherits = [ s.b ];
        b.inherits = [ s.a ];
      };
      valself = s: { a.inherits = [ s.a ]; };
      # a value and a name
      valname = s: {
        a.inherits = [ s.b ];
        b.inherits = [ "a" ];
      };
      # a value and the deprecated spelling
      valdep = s: {
        a.inherits = [ s.b ];
        b.imports = [ s.a ];
      };
      plain = f: builtins.attrNames (plainTree (written f)).a.options;
      staged = f: evalSchema { modules = written f; };
    in
    {
      test-plain-value-2-cycle = {
        expr = plain val2;
        expectedError = refuses "a b" "a -> b -> a" "a";
      };
      test-plain-value-self-cycle = {
        expr = plain valself;
        expectedError = refuses "a" "a -> a" "a";
      };
      test-plain-value-and-name-cycle = {
        expr = plain valname;
        expectedError = refuses "a b" "a -> b -> a" "a";
      };
      test-plain-value-and-spelling-cycle = {
        expr = plain valdep;
        expectedError = refuses "a b" "a -> b -> a" "a";
      };
      test-evalSchema-value-2-cycle = {
        expr = staged val2;
        expectedError = refuses "a b" "a -> b -> a" "a";
      };
      test-evalSchema-value-self-cycle = {
        expr = staged valself;
        expectedError = refuses "a" "a -> a" "a";
      };
      test-evalSchema-value-and-name-cycle = {
        expr = staged valname;
        expectedError = refuses "a b" "a -> b -> a" "a";
      };
      test-evalSchema-value-and-spelling-cycle = {
        expr = staged valdep;
        expectedError = refuses "a b" "a -> b -> a" "a";
      };
    };

  # `inherits` VALUE ENTRIES (den-hoag-l0y N2), the refused half. A foreign value sharing the mark of
  # the tree's same-named kind is decided by `kindEq`, and an open-content twin is refused by
  # `kindEq`'s own words, on both spellings; the type-only twin is admitted as the name
  # (ci/tests/inherits-value-entries.nix). A value that is not a kind is refused by name.
  flake.testsError.inherits-value-entry-refusals =
    let
      openInt = genMerge.mkOption {
        type = genMerge.types.int;
        default = 0;
      };
      foreignO = (plainTree [ { config.schema.baseO.options.b = openInt; } ]).baseO;
      openTwin =
        spelled:
        (plainTree [
          { config.schema.baseO.options.b = openInt; }
          {
            config.schema.sub = spelled // {
              options.extra = genMerge.mkOption { type = genMerge.types.int; };
            };
          }
        ]).sub.inherits;
      twinRefused = {
        type = "ThrownError";
        msg = "^gen-schema: kindEq: two declarations of 'baseO' mint one identity and are unequal only at sealed component\\(s\\) 'open\\.options\\.b\\.default': ";
      };
    in
    {
      test-inherits-open-twin-is-refused = {
        expr = openTwin { inherits = [ foreignO ]; };
        expectedError = twinRefused;
      };
      test-alias-open-twin-is-refused = {
        expr = openTwin { imports = [ foreignO ]; };
        expectedError = twinRefused;
      };
      # a SELF-NAMED subkind over a `//` copy of a foreign kind: decided by witness (the tree's entry
      # at that name is the declaring kind), and the copy's stamp is still read
      test-self-named-swap-is-refused = {
        expr =
          builtins.attrNames
            (plainTree [
              {
                config.schema.baseO = {
                  inherits = [ (foreignO // { options = { }; }) ];
                  options.extra = genMerge.mkOption { type = genMerge.types.int; };
                };
              }
            ]).baseO.options;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: kind 'baseO' inherits: the kind value 'baseO' is not the value its schema built: ";
        };
      };
      # ★ ENUMERATED, NOT CLOSED (ADR-0025 item 1): the name held by a DESCENDANT on the `mkType` arm,
      # with a caller `mkType` whose result shape reads the defs. The reach walk passes through `sub`
      # to the declaring kind, whose value is in flight, so it aborts uncatchably, as it did before the
      # reach step. Host evaluator only; the other two are the guarantee's.
      test-name-held-by-a-descendant-on-the-mkType-arm-aborts = {
        expr =
          let
            mkType =
              {
                defs ? [ ],
                kind,
                ...
              }:
              {
                __functor = _: _: {
                  imports = map (d: d.value) (builtins.filter (d: builtins.isAttrs d.value) defs);
                };
                inherit kind;
              }
              // (if builtins.length defs > 0 then { hasDefs = true; } else { });
          in
          builtins.attrNames
            (plainTreeWith (mkSchemaOption { inherit mkType; }) [
              {
                config.schema.baseO = {
                  inherits = [ "sub" ];
                  options.lb = genMerge.mkOption { type = genMerge.types.int; };
                };
                config.schema.sub = {
                  inherits = [ foreignO ];
                  options.extra = genMerge.mkOption { type = genMerge.types.int; };
                };
              }
            ]).sub.options;
        expectedError = {
          type = "EvalError";
          msg = "infinite recursion encountered";
        };
      };
      # A WITNESS COLLISION (den-hoag-4i0o5). Three self-named layers from one generator (one source
      # position, the same parent and option names) carry equal witnesses, so the cycle walk meets the
      # tip's witness on the middle layer. The refusal names both readings and the remedy, since no
      # reading before composition tells this acyclic chain from a cycle (`witness-collision-refusals`
      # below). A layer with another option name composes (`ci/tests/inherits-value-entries.nix`,
      # `test-self-named-chain-of-three-composes`).
      test-witness-collision-refuses-an-acyclic-chain =
        let
          layer = parent: o: {
            config.schema.baseO = {
              inherits = [ parent ];
              options.${o} = genMerge.mkOption { type = genMerge.types.int; };
            };
          };
          t1 = plainTree [ (layer foreignO "x") ];
          t2 = plainTree [ (layer t1.baseO "x") ];
        in
        {
          expr = builtins.attrNames t2.baseO.options;
          expectedError = {
            type = "ThrownError";
            msg = "^gen-schema: kind 'baseO' reaches a kind with its own content witness through its parents \\(baseO -> baseO\\), among kinds \\[baseO\\]: either it inherits itself, an inheritance cycle, .*; or two kinds named 'baseO' were declared from one source ";
          };
        };
      # The control forces each entry only as far as the kind/not-a-kind decision (its WHNF), never
      # the kind value whole: a kind carries published option records, and a deep force reaches the
      # evaluated keys gen-merge refuses by name there, as nixpkgs' own `value` throws for an
      # undefined option.
      test-inherits-entry-that-is-not-a-kind-is-refused = {
        expr =
          assert
            (builtins.tryEval (
              builtins.foldl' (ok: e: builtins.seq e ok) true
                (plainTree [ { config.schema.sub.inherits = [ foreignO ]; } ]).sub.inherits
            )).success;
          (plainTree [ { config.schema.sub.inherits = [ { kind = "baseO"; } ]; } ]).sub.inherits;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: kind 'sub' inherits an attrset with no mark: an `inherits` entry is a kind name or a kind value \\(`kind` and a mint-backed mark `__mint.minted`\\)$";
        };
      };
    };

  # THE COMPLETION STAMP (den-hoag-1a4f6), the refused half: a `//` copy of a kind value is refused
  # by name at every door that decides by mark — `kindEq`, the `inherits` value door, the ancestor
  # fold, and an instance's kind import. Each cell is pinned by message, so a refusal from anywhere
  # else cannot pass for it. The controls are `ci/tests/kind-value-swap.nix`.
  flake.testsError.kind-value-swap-refusals =
    let
      inherit (genSchema) kindEq mkInstanceType;
      T = genMerge.types;
      intOpt = genMerge.mkOption { type = T.int; };
      hostOf =
        port:
        (plainTree [
          {
            config.schema.host.options.port = genMerge.mkOption {
              type = T.int;
              default = port;
            };
          }
        ]).host;
      k80 = hostOf 80;
      typeOnly = (plainTree [ { config.schema.host.options.port = intOpt; } ]).host;
      swapped = k80 // {
        options = { };
      };
      viaAnything =
        v:
        (genMerge.evalModuleTree {
          modules = [
            { options.v = genMerge.mkOption { type = T.anything; }; }
            { config.v = v; }
          ];
        }).config.v;
      kindWith =
        computed:
        (genMerge.evalModuleTree {
          modules = [
            { options.schema = mkSchemaOption { inherit computed; }; }
            { config.schema.host.options.port = intOpt; }
          ];
        }).config.schema.host;
      boomy = kindWith (_: _: { boom = throw "boom"; });
      kMeta = kindWith (
        _: _: {
          meta = {
            boom = throw "meta-boom";
            ok = 1;
          };
        }
      );
      kList = kindWith (
        _: _: {
          l = [
            (x: x)
            (throw "list-boom")
          ];
        }
      );
      # a foreign kind, from a tree of its own
      foreign = (plainTree [ { config.schema.base.options.b = intOpt; } ]).base;
      foreignSwapped = foreign // {
        options = { };
      };
      sub =
        spelling: parents:
        (plainTree [
          {
            config.schema.sub = {
              ${spelling} = parents;
              options.extra = intOpt;
            };
          }
        ]).sub;
      mid =
        (plainTree [
          {
            config.schema.mid = {
              imports = [ foreignSwapped ];
              options.m = intOpt;
            };
          }
        ]).mid;
      opts = k: builtins.attrNames k.options;
      instanceOf =
        kind:
        (genMerge.evalModuleTree {
          modules = [
            { options.h = genMerge.mkOption { type = mkInstanceType kind { }; }; }
            { config.h.name = "a"; }
          ];
        }).config.h;
      notBuilt = site: kind: {
        type = "ThrownError";
        msg = "^${site}: the kind value '${kind}' is not the value its schema built: a `//` over a kind value keeps its mark while changing what the mark stands for; declare the change in the kind entry, or pass the kind value the schema published$";
      };
      kindEqRefuses = notBuilt "gen-schema: kindEq" "host";
    in
    {
      # S1–S6: the swap, either operand order, carried through `anything`, on a type-only kind, a
      # same-shape swap, and an added key
      test-swapped-options-refused = {
        expr = kindEq k80 swapped;
        expectedError = kindEqRefuses;
      };
      test-swapped-options-refused-in-either-order = {
        expr = kindEq swapped k80;
        expectedError = kindEqRefuses;
      };
      test-swapped-options-refused-through-anything = {
        expr = kindEq k80 (viaAnything swapped);
        expectedError = kindEqRefuses;
      };
      test-type-only-swap-refused = {
        expr = kindEq typeOnly (typeOnly // { options = { }; });
        expectedError = kindEqRefuses;
      };
      test-same-shape-swap-refused = {
        expr = kindEq k80 (k80 // { inherit (hostOf 443) options; });
        expectedError = kindEqRefuses;
      };
      test-added-key-refused = {
        expr = kindEq k80 (k80 // { extra = 1; });
        expectedError = kindEqRefuses;
      };
      # S9 and C2: a throwing slot replaced by a value, and an inner slot rebound unequal
      test-throwing-slot-replaced-refused = {
        expr = kindEq boomy (boomy // { boom = 1; });
        expectedError = kindEqRefuses;
      };
      test-inner-throwing-attrset-rebound-unequal-refused = {
        expr = kindEq kMeta (
          kMeta
          // {
            meta = kMeta.meta // {
              ok = 2;
            };
          }
        );
        expectedError = kindEqRefuses;
      };
      test-inner-throwing-list-rebound-unequal-refused = {
        expr = kindEq kList (
          kList
          // {
            l = [
              (builtins.head kList.l)
              2
            ];
          }
        );
        expectedError = kindEqRefuses;
      };
      # P2 and P6: a kind value short of the stamp, or of its sealed subjects, is refused naming what
      # it lacks, never with the `//` message or the no-mark one
      test-stampless-kind-refused-by-its-own-name = {
        expr = kindEq k80 (builtins.removeAttrs k80 [ "__kindSelf" ]);
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: kindEq: the kind value 'host' carries a mark but no completion stamp \\(`__kindSelf`\\), so nothing ties the mark to this value; take the kind from a gen-schema that stamps it$";
        };
      };
      test-unsealed-kind-refused-by-its-own-name = {
        expr = kindEq k80 (builtins.removeAttrs k80 [ "__sealed" ]);
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: kindEq: the kind value 'host' carries a mark but no sealed subjects \\(`__sealed`\\), so it cannot be compared by its mark; take the kind from a gen-schema that publishes both$";
        };
      };
      # S7: a same-tree value is the NAME, decided by `kindEq`
      test-same-tree-swapped-value-refused = {
        expr =
          opts
            (plainTree [
              { config.schema.host.options.port = intOpt; }
              (
                { config, ... }:
                {
                  config.schema.sub = {
                    inherits = [ (config.schema.host // { options = { }; }) ];
                    options.x = intOpt;
                  };
                }
              )
            ]).sub;
        expectedError = kindEqRefuses;
      };
      # S7′ (gate C1): a FOREIGN value decides by no `kindEq`; `formOf` reads its stamp
      test-foreign-swapped-value-refused = {
        expr = opts (sub "inherits" [ foreignSwapped ]);
        expectedError = notBuilt "gen-schema: kind 'sub' inherits" "base";
      };
      test-foreign-added-key-value-refused = {
        expr = opts (sub "inherits" [ (foreign // { extra2 = 1; }) ]);
        expectedError = notBuilt "gen-schema: kind 'sub' inherits" "base";
      };
      test-foreign-swapped-value-refused-where-inherits-is-read = {
        expr = (sub "inherits" [ foreignSwapped ]).inherits;
        expectedError = notBuilt "gen-schema: kind 'sub' inherits" "base";
      };
      # S11 (gate P1): a diamond the fold decides, spelled in `imports`, which meets no `formOf`
      test-foreign-swapped-diamond-refused-by-the-fold = {
        expr = opts (
          sub "imports" [
            foreign
            foreignSwapped
          ]
        );
        expectedError = notBuilt "gen-schema: kind 'sub' inherits" "base";
      };
      # S12: one parent the fold reaches with no diamond, spelled in `imports` or reached through a
      # parent; the fold reads every ancestor's stamp on entry
      test-foreign-swapped-spelled-parent-refused = {
        expr = opts (sub "imports" [ foreignSwapped ]);
        expectedError = notBuilt "gen-schema: kind 'sub' reaches 'base' along sub -> base" "base";
      };
      test-foreign-swapped-grandparent-refused = {
        expr = opts (sub "inherits" [ mid ]);
        expectedError = notBuilt "gen-schema: kind 'mid' reaches 'base' along mid -> base" "base";
      };
      # gate C3: an instance of a swapped kind, refused at the kind's import
      test-instance-of-swapped-kind-refused = {
        expr = (instanceOf swapped).port;
        expectedError = notBuilt "gen-schema: mkInstanceType" "host";
      };
    };

  flake.testsError.identity-refusals = {
    # R1. The door takes the kind DECLARATION and refuses a NAME by name: the stamp's preimage
    # carries the kind's minted identity, which a name does not have. Before this door a name was
    # the tag and the preimage alike, so two different declarations sharing a name minted one
    # identity. The control is the same door handed the kind value, which mints.
    test-kind-name-refused-at-the-stamp = {
      expr =
        assert
          let
            control = forced (keysNaming "name");
          in
          control.success && builtins.match "host:[0-9a-f]{64}" control.value != null;
        byName.id_hash;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: mkIdentityModule: a kind name is a reference, and this door takes the kind declaration \\(a kind value carrying `__mint\\.minted`\\); got the string 'host'$";
      };
    };
    # R1b. The refusal is EAGER: it fires when the module is applied, so a read that never forces
    # the stamp is refused too. A door judging its operand only at `id_hash` admits the name here.
    test-kind-name-refused-without-forcing-the-stamp = {
      expr = byName._identity.keys;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: mkIdentityModule: a kind name is a reference, and this door takes the kind declaration \\(a kind value carrying `__mint\\.minted`\\); got the string 'host'$";
      };
    };
    # An attrset that is not a kind value is refused with the admission wording `kindEq` and
    # `mkInstanceType` use.
    test-unmarked-attrset-refused = {
      expr =
        (genMerge.evalModuleTree {
          modules = [
            (mkIdentityModule {
              kind = "host";
              options = { };
            } [ "name" ])
          ]
          ++ hostModules;
        }).config.id_hash;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: mkIdentityModule: expected a kind value carrying a mint-backed mark \\(`__mint\\.minted`\\); got an attrset with no mark$";
      };
    };
    # The recompute takes the same operand and refuses a name the same way; without the guard it
    # reached `.__mint.minted` on a string and aborted uncatchably.
    test-recompute-refuses-a-kind-name = {
      expr = genSchema.identityHashForKind "host" { name = "igloo"; };
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: identityHashForKind: a kind name is a reference, and this door takes the kind declaration \\(a kind value carrying `__mint\\.minted`\\); got the string 'host'$";
      };
    };

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
        (identityEval noName [ ]).config.id_hash;
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

  # ★★ THE TWIN COST OF THE CARRY, STATED. gen-merge's `anything` carries a `__mint` carrier whole
  # through its leaf fold, which compares definitions with `==`. Two INDEPENDENT constructions of one
  # type-only kind are one identity (the control: `kindEq` answers `true`), but their closures are
  # distinct, so defined twice through `anything` the whole value is refused. A rebuild handed back a
  # value `kindEq` decided `true` against either construction: this cell's red.
  flake.testsError.kind-transport = {
    test-twin-kind-constructions-defined-twice-through-anything-refused =
      let
        kindOf =
          decl:
          (genMerge.evalModuleTree {
            modules = [
              { options.schema = mkSchemaOption { }; }
              { config.schema.host = decl; }
            ];
          }).config.schema.host;
        typeOnly = _: kindOf { options.port = genMerge.mkOption { type = genMerge.types.int; }; };
        k1 = typeOnly 1;
        k2 = typeOnly 2;
        carried =
          (genMerge.evalModuleTree {
            modules = [
              { options.k = genMerge.mkOption { type = genMerge.types.anything; }; }
              {
                _file = "A";
                config.k = k1;
              }
              {
                _file = "B";
                config.k = k2;
              }
            ];
          }).config.k;
      in
      {
        expr =
          assert
            let
              control = builtins.tryEval (genSchema.kindEq k1 k2);
            in
            control.success && control.value;
          genSchema.kindEq k1 carried;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-merge: the option `k' has conflicting definitions:\n- In `B': <a set>\n- In `A': <a set>$";
        };
      };
  };

  # den-hoag-ciu4r (ADR-0025). The computed fields are splatted OVER the record mkSchemaEntryType
  # writes, on both branches, so a computed `options` or `refs` replaced the published plane with no
  # signal. Measured at a90bc54: `(kind with computed options = "COMPUTED").options` ⇒ "COMPUTED" on
  # both arms. The class cell over every `kindResultKeys` name is `ci/tests/computed-field-keys.nix`.
  flake.testsError.computed-field-shadow-refusals = {
    # The default branch, with the live control inside the cell: a computed field with a free name is
    # still accepted, so a door that refused every computed field cannot score this green.
    test-computed-options-is-refused-by-name = {
      expr =
        assert
          let
            control =
              forced
                (kindOf { computed = _: _: { freeName = 1; }; } { options.role = strOpt; }).freeName;
          in
          control.success && control.value == 1;
        (kindOf { computed = _: _: { options = "COMPUTED"; }; } { options.role = strOpt; }).options;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: computed field 'options' is reserved — it is part of the kind-value contract; reserved computed-field names: __functor, kind, mixins, strict, keySemantics, options, refs, refinements, __mint, __sealed, __kindImports, __kindWitness, __kindAncestors, __kindCycleParents, __kindSelf$";
      };
    };

    # The `mkType` branch, where the computed fields are applied over the `mkType` result too.
    test-computed-refs-is-refused-on-the-mkType-arm = {
      expr =
        let
          mkType =
            { ... }:
            {
              options.role = strOpt;
            };
        in
        assert
          let
            control =
              forced
                (kindOf {
                  inherit mkType;
                  computed = _: _: { freeName = 1; };
                } { }).freeName;
          in
          control.success && control.value == 1;
        (kindOf {
          inherit mkType;
          computed = _: _: { refs = "COMPUTED"; };
        } { }).refs;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: computed field 'refs' is reserved — it is part of the kind-value contract; reserved computed-field names: __functor, kind, mixins, strict, keySemantics, options, refs, refinements, __mint, __sealed, __kindImports, __kindWitness, __kindAncestors, __kindCycleParents, __kindSelf$";
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
  # `_module` in a schema (den-hoag-fpxsd Unit 0): the engine's keys there are not a kind, and anything
  # else under `_module` refuses by name, where a filter would have dropped it in silence. The `_x`
  # cell is the control: the `_` reservation still refuses a kind so named.
  flake.testsError.schema-module-namespace =
    let
      kindsOf =
        extra:
        (genMerge.evalModuleTree {
          modules = [
            {
              options.schema = genSchema.mkSchemaOption { };
              config.schema.host.options.addr = genMerge.mkOption { type = genMerge.types.str; };
            }
            extra
          ];
        }).config.schema._kindNames;
      stray = {
        type = "ThrownError";
        msg = "^gen-schema: `_module' is the module engine's namespace and declares no kind; a schema module wrote something under it other than the engine's own `args', `check', `freeformType', `specialArgs' \\(a kind body there is read as a kind named `_module', and the `_' prefix is reserved\\)$";
      };
    in
    {
      test-an-unread-module-key-refuses-by-name = {
        expr = kindsOf { config.schema._module.foo = 1; };
        expectedError = stray;
      };
      test-a-kind-body-under-module-refuses-by-name = {
        expr = kindsOf {
          config.schema._module.options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
        expectedError = stray;
      };
      test-control-an-underscore-kind-still-refuses = {
        expr = kindsOf {
          config.schema._x.options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: kind name '_x' is reserved — names starting with '_' are internal use only \\(_kindNames, _topology, etc\\.\\)$";
        };
      };
    };

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

    # den-hoag-zijk1. A top-level `mkOption` on a structured kind is no option declaration: neither
    # module engine collects one, so it is an unread key and refuses by name. The control is the
    # module-style twin, which must land `myPort` — without it a refuse-everything guard satisfies
    # the pattern.
    test-flat-option-on-structured-kind-refuses-by-name = {
      expr =
        assert
          let
            control = forced (builtins.attrNames (kindOf { } { options.myPort = portOpt; }).options);
          in
          control.success && control.value == [ "myPort" ];
        builtins.attrNames
          (kindOf { } {
            imports = [ { } ];
            myPort = portOpt;
          }).options;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kind 'host': unrecognised declaration key 'myPort'";
      };
    };

    # The same key under `freeformType`, the one flat shape that evaluated end to end before: the
    # option record sat on the freeform plane as a VALUE while the refinement reader read it as a
    # declaration.
    test-flat-option-under-freeform-refuses-by-name = {
      expr =
        assert
          let
            control = forced (builtins.attrNames (kindOf { } { options.myPort = portOpt; }).options);
          in
          control.success && control.value == [ "myPort" ];
        builtins.attrNames
          (kindOf { } {
            freeformType = genMerge.types.lazyAttrsOf genMerge.types.anything;
            myPort = portOpt;
          }).options;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kind 'host': unrecognised declaration key 'myPort'";
      };
    };
  };

  # den-hoag-zijk1 · the REVERSE half-read, by name. An option the engine collects through `imports`
  # keeps its refined type, so an out-of-contract value is refused as the refinement, naming the
  # field. The control is the in-contract value on the same shape.
  flake.testsError.reverse-half-read-refusals = {
    test-imported-refined-option-is-enforced = {
      expr =
        assert
          let
            control = forced (portOf { imports = [ { options.myPort = portOpt; } ]; } 8080);
          in
          control.success && control.value == 8080;
        portOf { imports = [ { options.myPort = portOpt; } ]; } 70000;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-merge: a definition for option `hosts[.]a[.]myPort' is not of the expected type: must be a valid TCP port [(]1-65535[)]";
      };
    };

    # A bare `int` declared FIRST and the refined type SECOND must not merge down to `int` and drop
    # the contract (den-hoag-efepm): the refinement plane is read off the engine's merged type, so a
    # swallow there would accept 70000. The control is the refined-first order, refused the same way.
    test-bare-first-refined-second-does-not-swallow = {
      expr =
        assert
          !(forced (
            portOf {
              imports = [
                { options.myPort = portOpt; }
                { options.myPort = genMerge.mkOption { type = genMerge.types.int; }; }
              ];
            } 70000
          )).success;
        portOf {
          imports = [
            { options.myPort = genMerge.mkOption { type = genMerge.types.int; }; }
            { options.myPort = portOpt; }
          ];
        } 70000;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-merge: option `myPort' is declared with types that do not merge";
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
    # The inheritance-cycle walk's two fields are written onto every kind value on both branches
    # (8c8pr Q-b arm (i), 2026-09-30), so a SHORTHAND declaration of either, which the module engine
    # would otherwise read as no module syntax and discard, is refused by name. The control is the
    # same tree with the parent imported the ordinary way: it composes, so the refusal is the name's.
    test-kind-imports-is-a-reserved-declaration-key = {
      expr =
        assert
          let
            control = builtins.tryEval (
              builtins.attrNames
                (plainTree (spelledKinds {
                  a = [ "b" ];
                  b = [ ];
                })).a.options
            );
          in
          control.success
          &&
            control.value == [
              "o_a"
              "o_b"
            ];
        builtins.attrNames
          (plainTree [
            (
              { config, ... }:
              {
                config.schema.b.options.o_b = strOpt;
                config.schema.a.__kindImports = [ config.schema.b ];
              }
            )
          ]).a.options;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kind 'a': declaration key '__kindImports' is reserved — gen-schema writes it onto every kind value and a declared one is discarded unread$";
      };
    };
    test-kind-witness-is-a-reserved-declaration-key = {
      expr =
        assert
          let
            control = builtins.tryEval (builtins.attrNames (kindOf { } { options.role = strOpt; }).options);
          in
          control.success && control.value == [ "role" ];
        builtins.attrNames (kindOf { } { __kindWitness = "forged"; }).options;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kind 'host': declaration key '__kindWitness' is reserved — gen-schema writes it onto every kind value and a declared one is discarded unread$";
      };
    };
    # `__kindAncestors` is `_`-prefixed, so the construction-formal door's `publishedEntryKeys` (which
    # drops every `_`-prefixed name of `kindResultKeys`) leaves it to this door, as it leaves its two
    # siblings: refused here, with this door's text and not the published-name text.
    test-kind-ancestors-is-a-reserved-declaration-key = {
      expr =
        assert
          let
            control = builtins.tryEval (builtins.attrNames (kindOf { } { options.role = strOpt; }).options);
          in
          control.success && control.value == [ "role" ];
        builtins.attrNames (kindOf { } { __kindAncestors = { }; }).options;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kind 'host': declaration key '__kindAncestors' is reserved — gen-schema writes it onto every kind value and a declared one is discarded unread$";
      };
    };
    # `__kindCycleParents`, the parents as written, is reserved by the same door for the same reason.
    test-kind-cycle-parents-is-a-reserved-declaration-key = {
      expr =
        assert
          let
            control = builtins.tryEval (builtins.attrNames (kindOf { } { options.role = strOpt; }).options);
          in
          control.success && control.value == [ "role" ];
        builtins.attrNames (kindOf { } { __kindCycleParents = [ ]; }).options;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kind 'host': declaration key '__kindCycleParents' is reserved — gen-schema writes it onto every kind value and a declared one is discarded unread$";
      };
    };

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
          && id.value == "host:81561e7dc4346fe8fd08f1be5b8201a91392889f0ca10efc59d2f48f626e9d63"
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
          && id.value == "host:ddce01b9dccdc44b1d4320738872e674510cb9aea614c49f86b6aacfa1cc155d"
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

  # ── `evalSchema`'s two-channel collision ──────────────────────────────────────────────────────
  # A caller-supplied `schemaOption` has ALREADY been built, and its entry type has already closed
  # over whatever base module args it was given. `specialArgs` stated beside it would therefore be
  # threaded nowhere and the kind tree would diverge exactly as if none had been supplied — the
  # failure this channel exists to remove, reappearing at the one call that states both. Refused
  # where the caller states it, and the message names the place to state it instead; a `tryEval`
  # cell could only say that something threw.
  flake.testsError.schema-special-args = {
    test-evalSchema-refuses-schemaOption-and-specialArgs-together = {
      expr = evalSchema {
        modules = [
          { config.schema.fleet.options.hostName = genMerge.mkOption { type = genMerge.types.str; }; }
        ];
        schemaOption = mkSchemaOption { };
        specialArgs = {
          argand = {
            inletTag = "CALLER";
          };
        };
      };
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: `evalSchema' was given both `schemaOption' and `specialArgs'\\. The schema option supplied here is already built, so those args would reach no kind tree; state them where it is constructed instead — `mkSchemaOption \\{ specialArgs = …; \\}'$";
      };
    };
    # LIVE CONTROL, same run: each channel ALONE is admitted, so the cell above is about the
    # collision and not about a surface that refuses either one.
    test-either-channel-alone-is-admitted-control = {
      expr =
        let
          viaArgs =
            (evalSchema {
              modules = [
                {
                  config.schema.fleet.imports = [
                    (
                      { argand, ... }:
                      {
                        options.hostName = genMerge.mkOption {
                          type = genMerge.types.str;
                          default = argand.inletTag;
                        };
                      }
                    )
                  ];
                }
              ];
              specialArgs = {
                argand = {
                  inletTag = "CALLER";
                };
              };
            }).fleet.options.hostName.default;
          viaOption =
            (evalSchema {
              modules = [
                {
                  config.schema.fleet.options.hostName = genMerge.mkOption {
                    type = genMerge.types.str;
                    default = "plain";
                  };
                }
              ];
              schemaOption = mkSchemaOption { };
            }).fleet.options.hostName.default;
        in
        "${viaArgs}/${viaOption}";
      expected = "CALLER/plain";
    };
  };

  # A refined type's identity refusals, and the merge refusal's wording. All three are here for this
  # file's own reason: `tryEval` discards the message, and WHICH refusal fired is the subject.
  flake.testsError.refined-identity-refusals = {
    # Demanding `__id` of a refined type over a NULLARY base reaches gen-types' refusal for a type
    # with a SEALED component — the refinement's `check` is a caller lambda, carried in `__sealed`
    # beside the mark. The identity is gen-types' construction (`mkIdentity`), so this message is
    # that library's and not a paraphrase this one keeps in step by hand.
    test-id-of-a-refined-type-refuses-by-name = {
      expr = (genSchema.refined genMerge.types.int [ genSchema.refinements.tcpPort ]).__id;
      expectedError = {
        type = "ThrownError";
        msg = "^identity: type 'refined<int>' has sealed component\\(s\\) 'refinements[.]0' .*has no identity to demand$";
      };
    };

    # A refined type over a PARAMETRIC base names the check alone: gen-merge's structural types mint
    # per component, so the base is a component of the mark and not a sealed one (before it minted,
    # the base entered sealed as `members.0` beside the check).
    test-id-of-a-refined-parametric-type-names-only-the-check = {
      expr =
        (genSchema.refined (genMerge.types.listOf genMerge.types.str) [ genSchema.refinements.nonEmpty ])
        .__id;
      expectedError = {
        type = "ThrownError";
        msg = "^identity: type 'refined<listOf>' has sealed component\\(s\\) 'refinements[.]0' .*has no identity to demand$";
      };
    };

    # ★ THE WORDING AT THE MERGE DOOR IS NON-DISCRIMINATING FOR REFINEMENTS THAT SHARE A BASE, and
    # this cell pins that rather than pretending otherwise. `foreignRel` names the pair by `t.name`,
    # and a refined type deliberately keeps the BASE's name. It also names the two FUNCTOR names, but
    # only where they differ (gen-merge `interface.functorNamesOf`), and two refinements of one base
    # share the functor name `refined<int>'. So two refinements of one base produce the same string
    # whichever refinements they carry, and an oracle pinning only this message cannot tell them
    # apart; that discrimination is carried by the answer-and-survivors tables in
    # `ci/tests/refined-identity.nix`, never by the wording. A refined type against its BARE base, or
    # against a refinement of a different base, differs in functor name and is named by it.
    test-the-merge-refusal-names-the-unreconciled-pair = {
      expr =
        let
          port = genSchema.refined genMerge.types.int [ genSchema.refinements.tcpPort ];
          positive = genSchema.refined genMerge.types.int [ genSchema.refinements.positive ];
        in
        throw (port.typeMergeRel positive).refused;
      expectedError = {
        type = "ThrownError";
        msg = "^`int' and `int', which the first type's own `functor' does not reconcile$";
      };
    };

    # The control for the cell above, and the reason it is not vacuous: where the two bases differ
    # the message DOES discriminate, by the type names and by the two functor names the refusal now
    # carries. So the byte-identity pinned above is specific to the same-base pair rather than the
    # template being a constant.
    test-control-the-merge-refusal-discriminates-different-bases = {
      expr =
        let
          port = genSchema.refined genMerge.types.int [ genSchema.refinements.tcpPort ];
          other = genSchema.refined genMerge.types.str [ genSchema.refinements.positive ];
        in
        throw (port.typeMergeRel other).refused;
      expectedError = {
        type = "ThrownError";
        msg = "^`int' and `string', which the first type's own `functor' \\(named `refined<int>'\\) does not reconcile with the second's \\(named `refined<string>'\\)$";
      };
    };

    # a refinement chain past the type-identity bound refuses with gen-types' own named refusal,
    # single-sourced, where it used to overflow the stack
    test-refined-chain-past-the-bound-names-it = {
      expr =
        let
          chain =
            n:
            if n == 0 then genSchema.refined genMerge.types.int [ ] else genSchema.refined (chain (n - 1)) [ ];
        in
        (chain 1500).__id;
      expectedError = {
        type = "ThrownError";
        msg = "^identity: a type nests deeper than the type-identity depth bound \\(128 levels\\); a self-referential type has no identity$";
      };
    };
  };

  # den-hoag-0y9nr. `mkStrictModule`'s refusal names the undeclared KEY — never the instance, which
  # is all the freeform site's `path` can name — and its printed remedy is shown to be the one that
  # works: each control declares exactly what the `Fix:` line prints and reads the value back.
  # Self-labelling names: KINDNAME, INSTANCENAME, OFFENDINGKEY, DECLAREDOPTION, GROUPNAME,
  # DECLAREDINNER.
  flake.testsError.strict-mode-refusals =
    let
      opt = genMerge.mkOption { type = genMerge.types.anything; };
      kindWith =
        decls:
        (genMerge.evalModuleTree {
          modules = [
            { options.schema = mkSchemaOption { }; }
          ]
          ++ map (d: { config.schema.KINDNAME = d; }) decls;
        }).config.schema.KINDNAME;
      strictInstance =
        decls: insts:
        (genMerge.evalModuleTree {
          modules = [
            { options.registry = mkInstanceRegistry (kindWith decls) { }; }
          ]
          ++ map (i: { config.registry.INSTANCENAME = i; }) insts;
        }).config.registry.INSTANCENAME;
      instanceOf = decls: inst: strictInstance decls [ inst ];
      flat = [ { options.DECLAREDOPTION = opt; } ];
      grouped = [ { options.GROUPNAME.DECLAREDINNER = opt; } ];
      fixLine = k: "Fix: schema\\.KINDNAME\\.options\\.${k} = mkOption \\{ \\.\\.\\. \\};";
      # The refusal's exact text, anchored, from its literal lines.
      refusal = lines: "^${prelude.escapeRegex (builtins.concatStringsSep "\n" lines)}$";
      # The strict type itself, for the arms no module evaluation reaches: its `merge` handed defs
      # directly, under a level whose options declare DECLAREDOPTION.
      strictMerge =
        (genSchema.mkStrictModule "KINDNAME" {
          options.DECLAREDOPTION = opt;
        }).config._module.freeformType.content.merge
          [
            "registry"
            "INSTANCENAME"
          ];
    in
    {
      # S1. One undeclared key at depth 1: the refusal names the KEY and the instance's location, and
      # its remedy declares the KEY. The control is the same kind with the remedy APPLIED, which must
      # evaluate and carry the value — so the printed fix is shown to be the one that works.
      test-strict-names-the-key-not-the-instance = {
        expr =
          assert
            let
              c = forced (
                instanceOf (flat ++ [ { options.OFFENDINGKEY = opt; } ]) {
                  DECLAREDOPTION = 1;
                  OFFENDINGKEY = 2;
                }
              );
            in
            c.success && c.value.OFFENDINGKEY == 2;
          builtins.deepSeq (instanceOf flat {
            DECLAREDOPTION = 1;
            OFFENDINGKEY = 2;
          }) null;
        expectedError = {
          type = "ThrownError";
          msg = "^STRICT MODE: \"OFFENDINGKEY\" is not declared on KINDNAME \\(instance at registry\\.INSTANCENAME, defined in <gen-merge>\\)\\.\n${fixLine "OFFENDINGKEY"}$";
        };
      };
      # S2. An undeclared key UNDER a declared group: the blamed name is the capture path, not the
      # group, and the remedy extends the group (the control applies it) rather than colliding with it.
      test-strict-names-the-capture-path-under-a-group = {
        expr =
          assert
            let
              c = forced (
                instanceOf (grouped ++ [ { options.GROUPNAME.OFFENDINGKEY = opt; } ]) {
                  GROUPNAME = {
                    DECLAREDINNER = 1;
                    OFFENDINGKEY = 2;
                  };
                }
              );
            in
            c.success && c.value.GROUPNAME.OFFENDINGKEY == 2;
          builtins.deepSeq (instanceOf grouped {
            GROUPNAME = {
              DECLAREDINNER = 1;
              OFFENDINGKEY = 2;
            };
          }) null;
        expectedError = {
          type = "ThrownError";
          msg = "^STRICT MODE: \"GROUPNAME\\.OFFENDINGKEY\" is not declared on KINDNAME \\(instance at registry\\.INSTANCENAME, defined in <gen-merge>\\)\\.\n${fixLine "GROUPNAME\\.OFFENDINGKEY"}$";
        };
      };
      # S3. Two undeclared keys: both named, one remedy each.
      test-strict-names-every-undeclared-key = {
        expr = builtins.deepSeq (instanceOf flat {
          DECLAREDOPTION = 1;
          OFFENDINGKEYA = 2;
          OFFENDINGKEYB = 3;
        }) null;
        expectedError = {
          type = "ThrownError";
          msg = "^STRICT MODE: \"OFFENDINGKEYA\", \"OFFENDINGKEYB\" are not declared on KINDNAME \\(instance at registry\\.INSTANCENAME, defined in <gen-merge>\\)\\.\n${fixLine "OFFENDINGKEYA"}\n${fixLine "OFFENDINGKEYB"}$";
        };
      };
      # S4. mkStrictModule at a ROOT evaluation (prefix = [ ]), `ci/tests/strict-module.nix`'s shape:
      # the refusal is the strict one, not an unrelated failure of the blame read itself.
      test-strict-at-a-root-evaluation = {
        expr =
          builtins.deepSeq
            (genMerge.evalModuleTree {
              modules = [
                (genSchema.mkStrictModule "KINDNAME")
                { options.DECLAREDOPTION = opt; }
                {
                  config.DECLAREDOPTION = 1;
                  config.OFFENDINGKEY = 2;
                }
              ];
            }).config
            null;
        expectedError = {
          type = "ThrownError";
          msg = "^STRICT MODE: \"OFFENDINGKEY\" is not declared on KINDNAME \\(defined in <gen-merge>\\)\\.\n${fixLine "OFFENDINGKEY"}$";
        };
      };
      # S5. The same undeclared key defined by two modules is ONE key: named once, one remedy. Two
      # copies of the remedy would not parse (`attribute already defined`).
      test-strict-names-a-key-defined-twice-once = {
        expr = builtins.deepSeq (strictInstance flat [
          {
            DECLAREDOPTION = 1;
            OFFENDINGKEY = 2;
          }
          { OFFENDINGKEY = 2; }
        ]) null;
        expectedError = {
          type = "ThrownError";
          msg = refusal [
            "STRICT MODE: \"OFFENDINGKEY\" is not declared on KINDNAME (instance at registry.INSTANCENAME, defined in <gen-merge>)."
            "Fix: schema.KINDNAME.options.OFFENDINGKEY = mkOption { ... };"
          ];
        };
      };
      # S6. Keys that are not bare Nix identifiers — a dot, a quote, a leading digit — print QUOTED, so
      # the remedy parses and declares the key rather than a nested path. The control declares
      # exactly the printed attribute paths and reads every value back.
      test-strict-quotes-a-key-that-is-not-an-identifier = {
        expr =
          assert
            let
              c = forced (
                instanceOf
                  (
                    flat
                    ++ [
                      {
                        options."1DIGITKEY" = opt;
                        options."KEY\"QUOTE" = opt;
                        options."KEY.WITH.DOT" = opt;
                      }
                    ]
                  )
                  {
                    DECLAREDOPTION = 1;
                    "1DIGITKEY" = 2;
                    "KEY\"QUOTE" = 3;
                    "KEY.WITH.DOT" = 4;
                  }
              );
            in
            c.success && c.value."1DIGITKEY" == 2 && c.value."KEY\"QUOTE" == 3 && c.value."KEY.WITH.DOT" == 4;
          builtins.deepSeq (instanceOf flat {
            DECLAREDOPTION = 1;
            "1DIGITKEY" = 2;
            "KEY\"QUOTE" = 3;
            "KEY.WITH.DOT" = 4;
          }) null;
        expectedError = {
          type = "ThrownError";
          msg = refusal [
            "STRICT MODE: \"\"1DIGITKEY\"\", \"\"KEY\\\"QUOTE\"\", \"\"KEY.WITH.DOT\"\" are not declared on KINDNAME (instance at registry.INSTANCENAME, defined in <gen-merge>)."
            "Fix: schema.KINDNAME.options.\"1DIGITKEY\" = mkOption { ... };"
            "Fix: schema.KINDNAME.options.\"KEY\\\"QUOTE\" = mkOption { ... };"
            "Fix: schema.KINDNAME.options.\"KEY.WITH.DOT\" = mkOption { ... };"
          ];
        };
      };
      # S7. The fallback no module evaluation reaches: defs whose names the walk finds all declared
      # still refuse by naming their top-level names, never with an empty list.
      test-strict-falls-back-to-top-level-names = {
        expr = strictMerge [
          {
            file = "FILENAME";
            value.DECLAREDOPTION = 1;
          }
        ];
        expectedError = {
          type = "ThrownError";
          msg = refusal [
            "STRICT MODE: \"DECLAREDOPTION\" is not declared on KINDNAME (instance at registry.INSTANCENAME, defined in FILENAME)."
            "Fix: schema.KINDNAME.options.DECLAREDOPTION = mkOption { ... };"
          ];
        };
      };
      # S8. And with no name at all, the refusal still reads as a sentence.
      test-strict-with-no-name-still-refuses-in-words = {
        expr = strictMerge [
          {
            file = "FILENAME";
            value = { };
          }
        ];
        expectedError = {
          type = "ThrownError";
          msg = refusal [
            "STRICT MODE: a definition is not declared on KINDNAME (instance at registry.INSTANCENAME, defined in FILENAME)."
          ];
        };
      };
    };

  # Containment is well-founded and a parent is a kind NAME (den-hoag-4bqim, den-hoag-jvcgq). Each
  # refusal was an interpreter abort or a silent drop; `type = "ThrownError"` is what pins that it is
  # now a `throw`, which `tryEval` catches, and `msg` pins which one.
  flake.testsError.schema-containment-refusals =
    let
      schemaOf =
        modules:
        (genMerge.evalModuleTree {
          modules = [ { options.schema = mkSchemaOption { }; } ] ++ modules;
        }).config.schema;
      cycleMsg = "^gen-schema: containment cycle among kinds \\[a b\\] — a kind may not be its own ancestor$";
      looped = schemaOf [
        {
          config.schema = {
            a.parent = "b";
            b.parent = "a";
            c = { };
          };
        }
      ];
    in
    {
      # a <-> b admitted silently: both kinds were in neither `_roots` nor `_leaves`
      test-parent-cycle-refuses-by-name = {
        expr = looped._roots;
        expectedError = {
          type = "ThrownError";
          msg = cycleMsg;
        };
      };
      test-self-parent-refuses-by-name = {
        expr =
          (schemaOf [
            {
              config.schema = {
                a.parent = "a";
                b = { };
              };
            }
          ])._leaves;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: containment cycle among kinds \\[a\\] — a kind may not be its own ancestor$";
        };
      };
      # Every containment read refuses, not only `_roots`/`_leaves`: an unrelated kind's topology
      # entry, and the unified edge view whose parent edges are read through it.
      test-parent-cycle-refuses-an-unrelated-topology-read = {
        expr = looped._topology.c.parent;
        expectedError = {
          type = "ThrownError";
          msg = cycleMsg;
        };
      };
      test-parent-cycle-refuses-the-edge-view = {
        expr = looped._edges;
        expectedError = {
          type = "ThrownError";
          msg = cycleMsg;
        };
      };
      # the collection is untyped: an integer parent was indexed as a name and aborted uncatchably
      test-non-string-parent-refuses-by-name = {
        expr =
          (schemaOf [
            {
              config.schema = {
                a.parent = 5;
                b = { };
              };
            }
          ])._topology;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: kind 'a' declares a parent of type int, not a kind name$";
        };
      };
      # a string with store context cannot index the kind set; it aborted uncatchably
      test-context-parent-refuses-by-name = {
        expr =
          (schemaOf [
            {
              config.schema = {
                a.parent = "${builtins.toFile "b" "b"}";
                b = { };
              };
            }
          ])._roots;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: kind 'a' declares a parent carrying string context, not a kind name$";
        };
      };
      # The guard's answer is gen-graph's: built with a `cycles` that returns a sentinel on a forest,
      # the refusal names the sentinel. A cycle detector computed here instead answers `[ ]` and reads
      # a value.
      test-cycle-guard-delegates-to-gen-graph =
        let
          stubbed = import ../lib {
            inherit prelude;
            merge = genMerge;
            algebra = genAlgebra;
            identity = genIdentity;
            graph = genGraph // {
              cycles = _: [ "CYCLE-SENTINEL" ];
            };
          };
        in
        {
          expr =
            (genMerge.evalModuleTree {
              modules = [
                { options.schema = stubbed.mkSchemaOption { }; }
                {
                  config.schema = {
                    a = { };
                    b.parent = "a";
                  };
                }
              ];
            }).config.schema._roots;
          expectedError = {
            type = "ThrownError";
            msg = "^gen-schema: containment cycle among kinds \\[CYCLE-SENTINEL\\] — a kind may not be its own ancestor$";
          };
        };
      # the conflict refusal interpolated both sides, so a non-string side aborted in the act of refusing
      test-conflicting-non-string-parent-refuses-by-name = {
        expr =
          (schemaOf [
            { config.schema.a.parent = 5; }
            { config.schema.a.parent = "b"; }
            { config.schema.b = { }; }
          ]).a.parent;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: conflicting parent declarations: <a int> vs 'b'$";
        };
      };
    };

  # The retired name `ref` (lib/ref.nix, THE RETIRED NAME): applying it refuses with the message
  # that names `declarationOf`, and a lambda argument meets the same refusal rather than a coercion
  # abort, because the message interpolates nothing.
  flake.testsError.declaration-of-refusals =
    let
      msg = "^gen-schema: `ref` is renamed `declarationOf`\\. A value denoting a node is a declaration and the name written at a use site is a reference \\(Neron et al\\. 2015\\), so the type of a field holding either is `declarationOf <kind-or-registry>`; the argument and the behaviour are unchanged\\.$";
    in
    {
      test-ref-applied-refuses-by-name = {
        expr = genSchema.ref "host";
        expectedError = {
          type = "ThrownError";
          inherit msg;
        };
      };
      test-ref-lambda-argument-refuses-by-name = {
        expr = genSchema.ref (x: x);
        expectedError = {
          type = "ThrownError";
          inherit msg;
        };
      };
    };

  # ── a declaration value that is not a member (den-hoag-a4158) ────────────────────────────────
  # The refusal names the door, the declaration and the registry's identifiers; ./tests pins only
  # THAT the value is refused. The key-override idiom (`member // { addr = …; }`) is the case: it
  # keeps the member's stamp, so a message naming a cause other than membership would misdiagnose.
  flake.testsError.declaration-membership-refusals =
    let
      at =
        extra:
        (genMerge.evalModuleTree {
          modules = [
            (
              { config, ... }:
              let
                kinds = genSchema.evalSchema {
                  modules = [
                    {
                      config.schema.host.options.addr = genMerge.mkOption { type = genMerge.types.str; };
                      config.schema.link.options.label = genMerge.mkOption { type = genMerge.types.str; };
                      config.schema.service.options.host = genMerge.mkOption {
                        type = genSchema.declarationOf "host";
                      };
                      config.schema.node = {
                        options.addr = genMerge.mkOption { type = genMerge.types.str; };
                        options.parent = genMerge.mkOption {
                          type = genMerge.types.nullOr (genSchema.declarationOf "node");
                          default = null;
                        };
                      };
                    }
                  ];
                };
              in
              {
                options.hosts = genSchema.mkInstanceRegistry kinds.host { };
                options.spares = genSchema.mkInstanceRegistry kinds.host { };
                options.links = genSchema.mkInstanceRegistry kinds.link {
                  extraModules = [
                    { options.target = genMerge.mkOption { type = genSchema.declarationOf config.hosts; }; }
                  ];
                };
                options.handLinks = genSchema.mkInstanceRegistry kinds.link {
                  extraModules = [
                    { options.target = genMerge.mkOption { type = genSchema.declarationOf hand; }; }
                  ];
                };
                options.services = genSchema.mkInstanceRegistry kinds.service { refs.host = config.hosts; };
                # `derive` overwrites an identity key after the stamp is minted, so the post-derive
                # record carries a stamp its own fields no longer produce.
                options.drift = genSchema.mkInstanceRegistry kinds.node {
                  refs.parent = {
                    deferred = true;
                    instances = config.drift;
                  };
                  derive = _: { n0.addr = "derived"; };
                };
                config.hosts.igloo.addr = "10.0.0.1";
                config.spares.igloo.addr = "10.9.9.9";
                config.links.main.label = "l";
                config.handLinks.main.label = "l";
                config.drift.n0.addr = "n0";
              }
            )
            extra
          ];
        }).config;
      fixture = extra: (at extra).links.main.target;
      hand.a = {
        name = "a";
        id_hash = "hand:1";
        addr = "x";
      };
    in
    {
      test-key-override-refused-as-non-member = {
        expr = fixture (
          { config, ... }: {
            config.links.main.target = config.hosts.igloo // {
              addr = "evil";
            };
          }
        );
        expectedError = {
          type = "ThrownError";
          msg = "^links\\.main\\.target: declaration 'igloo' is not a member of the registry \\(available: 'igloo'\\) \\(in prelude\\.resolve\\)$";
        };
      };
      # Gate v1 C1: a hinted STAMPLESS value naming a REAL member — no stamp at all, unlike the
      # override above (which keeps the stamp and moves a key). Without the `or null` guard on the
      # stamp read in `isCanonicalOf`, this aborts uncatchably (`attribute 'id_hash' missing`)
      # instead of refusing by name through this same "not a member" verdict.
      test-stampless-real-member-refused-as-non-member = {
        expr = fixture {
          config.links.main.target = {
            name = "igloo";
          };
        };
        expectedError = {
          type = "ThrownError";
          msg = "^links\\.main\\.target: declaration 'igloo' is not a member of the registry \\(available: 'igloo'\\) \\(in prelude\\.resolve\\)$";
        };
      };
      test-non-instance-refused-by-form = {
        expr = fixture {
          config.links.main.target = {
            name = "ghost";
          };
        };
        expectedError = {
          type = "ThrownError";
          msg = "^links\\.main\\.target: declaration 'ghost' is not a member of the registry \\(available: 'igloo'\\) \\(in prelude\\.resolve\\)$";
        };
      };
      # A ref-field door (immediate): the prefix names the field and the kind, as the identifier arm's.
      test-foreign-refused-at-a-ref-field = {
        expr = (at ({ config, ... }: { config.services.s.host = config.spares.igloo; })).services.s.host;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: ref field 'host' on kind 'service': declaration 'igloo' is not a member of the registry \\(available: 'igloo'\\) \\(in prelude\\.resolve\\)$";
        };
      };
      # Gate v1 (P1) C1, exercised at an IMMEDIATE ref-field door: the same hinted, stampless value
      # naming a real member as the direct-door cell above, routed through `mkCoerceChain` instead of
      # `mkCoercingRefType`. Both call `isCanonicalOf`, so one guard covers both, but only a cell at
      # each door measures that rather than assuming it.
      test-stampless-real-member-refused-at-a-ref-field = {
        expr =
          (at (
            { config, ... }: {
              config.services.s.host = {
                name = "igloo";
              };
            }
          )).services.s.host;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: ref field 'host' on kind 'service': declaration 'igloo' is not a member of the registry \\(available: 'igloo'\\) \\(in prelude\\.resolve\\)$";
        };
      };
      # A registry whose members are not gen-schema instances has no identity-key datum to compare.
      # This is the one refusal in the suite that does NOT name the door: it throws from
      # `isCanonicalOf` (lib/ref.nix), which `prelude.resolve` binds registry-first so the by-hint
      # index is shared across every option location — the calling door is not yet known there, so
      # the message names the library instead.
      test-member-without-identity-keys-refused = {
        expr =
          (at {
            config.handLinks.main.target = hand.a // {
              addr = "evil";
            };
          }).handLinks.main.target;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: registry member 'a' carries no _identityKeys; a declaration value resolves only against gen-schema instances \\(use the identifier 'a'\\)$";
        };
      };
      # The registry's own member, after a `derive` overwrote an identity key: its stamp is stale
      # against its fields, so it is not the entry it claims to be. At HEAD this served "derived"
      # while the identifier "n0" served "n0"; now the value form is loud.
      test-derive-overlaid-member-refused = {
        expr =
          (at (
            { config, ... }:
            {
              config.drift.n1 = {
                addr = "n1";
                parent = config.drift.n0;
              };
            }
          )).drift.n1.parent.addr;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: ref field 'parent' on kind 'node': declaration 'n0' is not a member of the registry \\(available: 'n0', 'n1'\\) \\(in prelude\\.resolve\\)$";
        };
      };
      # Gate v1 (P1) C1, exercised at a DEFERRED ref-field door (`mkInstanceRegistry`'s
      # `refs.<field> = { deferred = true; instances = …; }`): same hinted, stampless real-member
      # value, third door onto the shared `isCanonicalOf` guard.
      test-stampless-real-member-refused-in-deferred-ref = {
        expr =
          (at (
            { config, ... }:
            {
              config.drift.n1 = {
                addr = "n1";
                parent = {
                  name = "n0";
                };
              };
            }
          )).drift.n1.parent;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: ref field 'parent' on kind 'node': declaration 'n0' is not a member of the registry \\(available: 'n0', 'n1'\\) \\(in prelude\\.resolve\\)$";
        };
      };
    };

  # ── the kind-tree channel's reserved keys (den-hoag-v9gjd, G5/G6) ────────────────────────────
  # `evalSchema`, `mkSchemaOption` and `identityKeysForKind` forward `specialArgs` verbatim into
  # `merge.evalModuleTree`'s own `baseArgs` (S2/S3/S4 in the spec's channel census). The gen-merge
  # landing this row depends on (`f5a2420`, den-hoag-v9gjd) refuses a caller's `config`/`options`/
  # `prefix` there by name, closing this channel BY CONSTRUCTION — no lib/ change on this side, only
  # the cells that show it. Each refusal cell reads the TEXT, because `tryEval` alone would pass on
  # any refusal anywhere in the construction.
  flake.testsError.kind-tree-reserved-args =
    let
      # A kind needing no formal of its own — merely applying it during introspection is what
      # forces `baseArgs` on `identityKeysForKind`'s path (the build report's S4 note: a
      # names-only read already throws).
      plainKind = {
        options.tag = genMerge.mkOption {
          type = genMerge.types.str;
          default = "plain";
        };
      };
      # `evalSchema`/`mkSchemaOption`'s own path only forces `baseArgs` for a module whose
      # FORMAL NAMES the reserved key — `builtins.functionArgs` on a bare attrset or a
      # non-pattern lambda returns `{ }`, and `intersectAttrs { } specialArgs` never touches
      # `specialArgs` at all, so the guard's `throw` is never reached. Driven directly
      # (`den-hoag-v9gjd` probe): a bare-attrset kind does NOT throw here even at f5a2420; a
      # `{ config, ... }: …` kind does. One pattern-formal kind per reserved key, naming it but
      # not reading it — the refusal fires on the DECLARATION, not on a use of the value.
      configKind =
        { config, ... }:
        {
          options.tag = genMerge.mkOption {
            type = genMerge.types.str;
            default = "plain";
          };
        };
      optionsKind =
        { options, ... }:
        {
          options.tag = genMerge.mkOption {
            type = genMerge.types.str;
            default = "plain";
          };
        };
      prefixKind =
        { prefix, ... }:
        {
          options.tag = genMerge.mkOption {
            type = genMerge.types.str;
            default = "plain";
          };
        };
      viaEvalSchema =
        mod: sa:
        (evalSchema {
          specialArgs = sa;
          modules = [ { config.schema.fleet.imports = [ mod ]; } ];
        }).fleet.options.tag.default;
      viaMkSchemaOption =
        mod: sa:
        (evalSchema {
          schemaOption = mkSchemaOption { specialArgs = sa; };
          modules = [ { config.schema.fleet.imports = [ mod ]; } ];
        }).fleet.options.tag.default;
      viaIdentityKeysForKind = sa: identityKeysForKind { specialArgs = sa; } (kindOfModules plainKind);
      msg =
        keys:
        "^gen-merge: `specialArgs' cannot supply the base module ${keys}; the engine injects its own value there, so the caller's would be discarded rather than used$";
      refused = keys: {
        type = "ThrownError";
        msg = msg keys;
      };
      one = k: { ${k} = "CALLER"; };

      # ── G6: the value plane, which must NOT flip ────────────────────────────────────────────
      # `argand` (an ordinary caller key) and `name` (admitted here because Q1 = A, defaulted: the
      # kind-tree channel refuses only E = {config, options, prefix}) both still deliver the
      # caller's literal VALUE, on every channel — not merely "did not throw".
      argandTagModule =
        { argand, ... }:
        {
          options.tag = genMerge.mkOption {
            type = genMerge.types.str;
            default = argand;
          };
        };
      nameTagModule =
        { name, ... }:
        {
          options.tag = genMerge.mkOption {
            type = genMerge.types.str;
            default = name;
          };
        };
      # `identityKeysForKind` returns option NAMES, not values (S4 note), so its probe is a
      # conditional option: the key set carries `marker` only when the caller's value is exactly
      # `"CALLER"`, and the returned key list is the observation.
      argandGatedModule =
        { argand, ... }:
        if argand == "CALLER" then
          {
            options.marker = genMerge.mkOption {
              type = genMerge.types.str;
              default = "hit";
            };
          }
        else
          { };
      nameGatedModule =
        { name, ... }:
        if name == "CALLER" then
          {
            options.marker = genMerge.mkOption {
              type = genMerge.types.str;
              default = "hit";
            };
          }
        else
          { };
      viaIdentityKeysForKindGated =
        mod: sa: builtins.elem "marker" (identityKeysForKind { specialArgs = sa; } (kindOfModules mod));
    in
    {
      test-evalSchema-refuses-a-caller-config-by-name = {
        expr = viaEvalSchema configKind (one "config");
        expectedError = refused "argument `config'";
      };
      test-evalSchema-refuses-a-caller-options-by-name = {
        expr = viaEvalSchema optionsKind (one "options");
        expectedError = refused "argument `options'";
      };
      test-evalSchema-refuses-a-caller-prefix-by-name = {
        expr = viaEvalSchema prefixKind (one "prefix");
        expectedError = refused "argument `prefix'";
      };
      test-mkSchemaOption-refuses-a-caller-config-by-name = {
        expr = viaMkSchemaOption configKind (one "config");
        expectedError = refused "argument `config'";
      };
      test-mkSchemaOption-refuses-a-caller-options-by-name = {
        expr = viaMkSchemaOption optionsKind (one "options");
        expectedError = refused "argument `options'";
      };
      test-mkSchemaOption-refuses-a-caller-prefix-by-name = {
        expr = viaMkSchemaOption prefixKind (one "prefix");
        expectedError = refused "argument `prefix'";
      };
      test-identityKeysForKind-refuses-a-caller-prefix-by-name = {
        expr = viaIdentityKeysForKind (one "prefix");
        expectedError = refused "argument `prefix'";
      };
      test-kind-tree-channels-agree-argand-and-name-survive-control = {
        expr = {
          evalSchema = {
            argand = viaEvalSchema argandTagModule (one "argand");
            name = viaEvalSchema nameTagModule (one "name");
          };
          mkSchemaOption = {
            argand = viaMkSchemaOption argandTagModule (one "argand");
            name = viaMkSchemaOption nameTagModule (one "name");
          };
          identityKeysForKind = {
            argand = viaIdentityKeysForKindGated argandGatedModule (one "argand");
            name = viaIdentityKeysForKindGated nameGatedModule (one "name");
          };
        };
        expected = {
          evalSchema = {
            argand = "CALLER";
            name = "CALLER";
          };
          mkSchemaOption = {
            argand = "CALLER";
            name = "CALLER";
          };
          identityKeysForKind = {
            argand = true;
            name = true;
          };
        };
      };
    };

  # den-hoag-xzchx arm 4. `_identity` is a closed `lazyAttrsOf (listOf str)` leaf; the refusals it
  # owns, by message. ci/tests/identity-leaf.nix pins that each one fires, and this group pins WHICH
  # one: a foreign key names the closed record, on a strict kind, on a lax one and under `mkIf false`,
  # and a module-shaped definition refuses at the leaf's domain.
  flake.testsError.identity-leaf-refusals =
    let
      leafHost =
        (evalSchema {
          modules = [

            {
              config.schema.host.options.addr = genMerge.mkOption { type = genMerge.types.str; };
              config.schema.host.options.role = genMerge.mkOption { type = genMerge.types.str; };
            }

          ];
        }).host;
      identityOf =
        regOpts: v:
        (genMerge.evalModuleTree {
          modules = [

            {
              options.hosts = mkInstanceRegistry leafHost regOpts;
              config.hosts.h = {
                addr = "10.0.0.1";
                role = "web";
              }
              // v;
            }

          ];
        }).config.hosts.h.id_hash;
    in

    {
      test-foreign-key-names-the-closed-record = {
        expr = identityOf { } { _identity.bogus = [ "x" ]; };
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: `_identity' declares only `keys'; it does not declare `bogus'$";
        };
      };
      test-foreign-key-on-a-lax-kind-names-the-closed-record = {
        expr = identityOf { strict = false; } { _identity.bogus = [ "x" ]; };
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: `_identity' declares only `keys'; it does not declare `bogus'$";
        };
      };
      test-conditioned-away-foreign-key-names-the-closed-record = {
        expr = identityOf { } {
          _identity = {
            keys = [ "addr" ];
            bogus = genMerge.mkIf false [ "x" ];
          };
        };
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: `_identity' declares only `keys'; it does not declare `bogus'$";
        };
      };
      test-function-definition-refuses-at-the-domain = {
        expr = identityOf { } { _identity = { config, ... }: { keys = [ "addr" ]; }; };
        expectedError = {
          type = "ThrownError";
          msg = "^gen-merge: option `hosts\\.h\\._identity' has definitions `lazyAttrsOf' cannot consume";
        };
      };
      test-path-definition-refuses-at-the-domain = {
        expr = identityOf { } { _identity = ./test-fixtures/identity-path-definition.nix; };
        expectedError = {
          type = "ThrownError";
          msg = "^gen-merge: option `hosts\\.h\\._identity' has definitions `lazyAttrsOf' cannot consume";
        };
      };
    };

  # THE CLOSED-DOOR REFUSALS (den-hoag-7gp66 P1) — `ci/tests/door-checks.nix` pins that every door
  # refuses catchably; these pin WHICH refusal fired and that it names the door (R6). One cell per
  # violation gen-prelude's `checkOptions`/`checkRequired` can raise for a row in `../doors.nix`, in
  # the row's own order; a RECORD door (`options == [ ]`) has no unknown-option cell because R5 admits
  # an extra field rather than refusing it (that admission is `door-checks.nix`'s own cell).
  flake.testsError.door-checks = {
    test-mkfieldvalidator-missing-required-names-the-door = {
      expr = doors.mkFieldValidator.call (builtins.removeAttrs doors.mkFieldValidator.valid [ "fields" ]);
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema\\.mkFieldValidator: required field 'fields' is missing \\(required: 'fields', 'name', 'check', 'message'\\) \\(in prelude\\.checkRequired\\)$";
      };
    };
    test-mkfieldvalidator-non-attrset-argument-names-the-door = {
      expr = doors.mkFieldValidator.call 1;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema\\.mkFieldValidator: the argument must be an attrset, not a int \\(required: 'fields', 'name', 'check', 'message'\\) \\(in prelude\\.checkRequired\\)$";
      };
    };

    test-mkmixin-missing-required-names-the-door = {
      expr = doors.mkMixin.call (builtins.removeAttrs doors.mkMixin.valid [ "define" ]);
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema\\.mkMixin: required field 'define' is missing \\(required: 'define'\\) \\(in prelude\\.checkRequired\\)$";
      };
    };
    test-mkmixin-non-attrset-argument-names-the-door = {
      expr = doors.mkMixin.call 1;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema\\.mkMixin: the argument must be an attrset, not a int \\(required: 'define'\\) \\(in prelude\\.checkRequired\\)$";
      };
    };
    test-mkmixin-unknown-option-names-the-door = {
      expr = doors.mkMixin.call (doors.mkMixin.valid // { bogus = 1; });
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema\\.mkMixin: 'bogus' is not an option of this door; the options are closed \\(accepted: 'define', 'requires', 'provides', 'kinds', 'name'\\) \\(in prelude\\.checkOptions\\)$";
      };
    };

    test-evalschema-missing-required-names-the-door = {
      expr = doors.evalSchema.call (builtins.removeAttrs doors.evalSchema.valid [ "modules" ]);
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema\\.evalSchema: required field 'modules' is missing \\(required: 'modules'\\) \\(in prelude\\.checkRequired\\)$";
      };
    };
    test-evalschema-non-attrset-argument-names-the-door = {
      expr = doors.evalSchema.call 1;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema\\.evalSchema: the argument must be an attrset, not a int \\(required: 'modules'\\) \\(in prelude\\.checkRequired\\)$";
      };
    };
    test-evalschema-unknown-option-names-the-door = {
      expr = doors.evalSchema.call (doors.evalSchema.valid // { bogus = 1; });
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema\\.evalSchema: 'bogus' is not an option of this door; the options are closed \\(accepted: 'modules', 'schemaOption', 'specialArgs'\\) \\(in prelude\\.checkOptions\\)$";
      };
    };

    test-identitykeysforkind-non-attrset-argument-names-the-door = {
      expr = doors.identityKeysForKind.call 1;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema\\.identityKeysForKind: the options must be an attrset, not a int \\(accepted: 'specialArgs'\\) \\(in prelude\\.checkOptions\\)$";
      };
    };
    test-identitykeysforkind-unknown-option-names-the-door = {
      expr = doors.identityKeysForKind.call { bogus = 1; };
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema\\.identityKeysForKind: 'bogus' is not an option of this door; the options are closed \\(accepted: 'specialArgs'\\) \\(in prelude\\.checkOptions\\)$";
      };
    };

    test-mkschemaentrytype-non-attrset-argument-names-the-door = {
      expr = doors.mkSchemaEntryType.call 1;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema\\.mkSchemaEntryType: the options must be an attrset, not a int \\(accepted: 'baseModule', 'collections', 'computed', 'mixins', 'mkType', 'strict', 'keySemantics', 'specialArgs'\\) \\(in prelude\\.checkOptions\\)$";
      };
    };
    test-mkschemaentrytype-unknown-option-names-the-door = {
      expr = doors.mkSchemaEntryType.call { bogus = 1; };
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema\\.mkSchemaEntryType: 'bogus' is not an option of this door; the options are closed \\(accepted: 'baseModule', 'collections', 'computed', 'mixins', 'mkType', 'strict', 'keySemantics', 'specialArgs'\\) \\(in prelude\\.checkOptions\\)$";
      };
    };

    test-mkschemaoption-non-attrset-argument-names-the-door = {
      expr = doors.mkSchemaOption.call 1;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema\\.mkSchemaOption: the options must be an attrset, not a int \\(accepted: 'baseModule', 'collections', 'computed', 'mixins', 'mkType', 'strict', 'keySemantics', 'specialArgs'\\) \\(in prelude\\.checkOptions\\)$";
      };
    };
    test-mkschemaoption-unknown-option-names-the-door = {
      expr = doors.mkSchemaOption.call { bogus = 1; };
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema\\.mkSchemaOption: 'bogus' is not an option of this door; the options are closed \\(accepted: 'baseModule', 'collections', 'computed', 'mixins', 'mkType', 'strict', 'keySemantics', 'specialArgs'\\) \\(in prelude\\.checkOptions\\)$";
      };
    };
  };

  # den-hoag-n6dh7 Unit 2.4 (item 1; OQ2 α): a nested tree is a child of the one evaluation that
  # holds it, so a submodule's CALLED `whenEmpty.value` refuses by name rather than evaluating the
  # tree standalone. A deep force of a submodule-based TYPE record (here `mkInstanceType`'s) reaches
  # that field, so it meets the refusal, catchably; the value side and a shallow read are untouched
  # (`ci/tests/mktype-kind-value.nix`).
  flake.testsError.type-record-deep-force = {
    test-a-deep-force-of-a-submodule-based-type-meets-the-called-empty-value-refusal = {
      expr =
        let
          # every option defaulted, so the deep force reaches the type's own fields first
          kind =
            (genMerge.evalModuleTree {
              modules = [
                { options.schema = mkSchemaOption { }; }
                {
                  config.schema.host.options.role = genMerge.mkOption {
                    type = genMerge.types.str;
                    default = "x";
                  };
                }
              ];
            }).config.schema.host;
        in
        # `__id` is left out: a submodule type now mints with its modules sealed, so a deep force meets
        # the identity demand's refusal (`modules.0` has no identity to demand) before `whenEmpty`.
        builtins.deepSeq (removeAttrs (genSchema.mkInstanceType kind { }) [ "__id" ]) null;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-merge: `submodule': its called `whenEmpty' does not evaluate the nested tree: a nested tree is a child of the one evaluation that holds it [(]`evalModuleTree'[)], read through its fold's threaded sibling, and no second evaluation is made for it$";
      };
    };
  };

  # ★ A NAME WITH A KIND-LEVEL READING WRITTEN AT A KIND ENTRY'S TOP LEVEL (den-hoag-q17cc). Before the
  # door each of these evaluated at exit 0: the shorthand write became config for every instance and
  # the kind value went on reading its own value at the path just written. Every cell forces the mark,
  # which a kind with no instances still mints, and carries the clean kind as its control. The
  # structured cell is the one the nn4 surplus clause used to answer with "declare an option" — the
  # wrong surface — so it pins that the formal clause runs first.
  flake.testsError.construction-formal-refusals =
    let
      cleanMarks =
        (forced (kindOf { } { options.role = strOpt; }).__mint.minted).success
        && (forced (kindOf { } { role = "web"; }).__mint.minted).success;
      formalMsg =
        f:
        "^gen-schema: kind 'host': declaration key '${f}' is a construction formal of this schema — it is fixed by the call that builds the schema option [(]`mkSchemaOption`, `mkSchemaEntryType`[)], and written on a kind entry it is not read as one; pass '${f}' to that constructor, or write `config[.]${f}` for an instance field of that name, which a strict instance must declare as an option$";
      publishedMsg =
        n:
        "^gen-schema: kind 'host': declaration key '${n}' is a name gen-schema writes onto the kind value — written on a kind entry it lands on every instance, while reading `config[.]schema[.]host[.]${n}` returns the published one; write `config[.]${n}` for an instance field of that name, which a strict instance must declare as an option$";
      publishedCell = n: v: {
        expr =
          assert cleanMarks;
          (kindOf { } { ${n} = v; }).__mint.minted;
        expectedError = {
          type = "ThrownError";
          msg = publishedMsg n;
        };
      };
    in
    {
      # G5 · default branch, shorthand.
      test-formal-as-shorthand-refuses-by-name = {
        expr =
          assert cleanMarks;
          (kindOf { } { keySemantics = [ "darwin" ]; }).__mint.minted;
        expectedError = {
          type = "ThrownError";
          msg = formalMsg "keySemantics";
        };
      };

      # G6 · default branch, structured: the formal clause answers, not the surplus clause.
      test-formal-in-structured-decl-gets-the-formal-text = {
        expr =
          assert cleanMarks;
          (kindOf { } {
            options.role = strOpt;
            keySemantics = [ "darwin" ];
          }).__mint.minted;
        expectedError = {
          type = "ThrownError";
          msg = formalMsg "keySemantics";
        };
      };

      # The `mkType` branch, where clause A stands the surplus guard down: the formal door is live
      # there too. Control: the same schema's caller-owned key still comes through.
      test-formal-refuses-on-the-mkType-branch = {
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
              control = builtins.tryEval (kindOf args { unreadByGenSchema = "kept"; }).custom;
            in
            control.success && control.value;
          (kindOf args { strict = false; }).custom;
        expectedError = {
          type = "ThrownError";
          msg = formalMsg "strict";
        };
      };

      # C2 · the names gen-schema writes onto the kind value that are not formals, each with its own
      # text: reading the path back returns the published plane, never the write.
      test-kind-is-a-published-name = publishedCell "kind" "forged";
      test-refs-is-a-published-name = publishedCell "refs" { forged = 1; };
      test-refinements-is-a-published-name = publishedCell "refinements" { forged = 1; };

      # G7 · a collection named for a formal would make the formal's key read as a collection.
      test-collection-named-for-a-formal-is-reserved = {
        expr =
          assert cleanMarks;
          (kindOf { collections.computed.default = [ ]; } { options.role = strOpt; }).__mint.minted;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: collection 'computed' is reserved — cannot be used as a collection key$";
        };
      };
    };

  # THE LINEAGE REFUSALS (den-hoag-l0y U1): the ancestor map's diamond refusal, which names the child
  # and both paths, the class check, and the composition the mark-keyed module key no longer drops.
  # Each is read at the child's COMPOSED read (an option), where `resolvedOnly` sites it, and each
  # carries its admitted twin as a live control (`ci/tests/kind-ancestors.nix` holds them as cells).
  flake.testsError.kind-lineage-refusals =
    let
      T = genMerge.types;
      intOpt = genMerge.mkOption { type = T.int; };
      openInt =
        d:
        genMerge.mkOption {
          type = T.int;
          default = d;
        };
      tree = plainTree;
      pOf = d: (tree [ { config.schema.p.options.base = openInt d; } ]).p;
      mid =
        p: o:
        (tree [
          {
            config.schema.${o} = {
              imports = [ p ];
              options.${o} = intOpt;
            };
          }
        ]).${o};
      diamondOf =
        a: b:
        (tree [
          {
            config.schema.d.imports = [
              a
              b
            ];
          }
        ]).d;
      p80 = pOf 80;
      dOk = diamondOf (mid p80 "x") (mid p80 "y");
      dBad = diamondOf (mid p80 "x") (mid (pOf 443) "y");

      ksBase = {
        alpha.category = "class";
      };
      baseA =
        (plainTreeWith (mkSchemaOption { keySemantics = ksBase; }) [
          { config.schema.base.options.b = intOpt; }
        ]).base;
      subUnder =
        ks:
        (plainTreeWith (mkSchemaOption { keySemantics = ks; }) [
          {
            config.schema.sub = {
              imports = [ baseA ];
              options.extra = intOpt;
            };
          }
        ]).sub;
      subOk = subUnder (ksBase // { beta.category = "class"; });

      # one generator in two trees: `bOpt` is the only difference (a type for K2, a default for K2eq)
      gen = bOpt: {
        config.schema.root.options.r = intOpt;
        config.schema.base = {
          inherits = [ "root" ];
          options.b = bOpt;
        };
      };
      consumer =
        foreignOpt: localOpt:
        tree [
          (gen localOpt)
          {
            config.schema.sub = {
              imports = [ (tree [ (gen foreignOpt) ]).base ];
              options.s = intOpt;
            };
          }
          {
            config.schema.x = {
              inherits = [ "base" ];
              options.xx = intOpt;
            };
          }
          {
            config.schema.d.inherits = [
              "sub"
              "x"
            ];
          }
        ];
      k2 = consumer intOpt (genMerge.mkOption { type = T.str; });
      k2eq = consumer (openInt 80) (openInt 443);

      # an ancestor sharing the declaring kind's name is a foreign kind value (in one tree a name is
      # one entry): a SELF-NAMED `base` over `baseA`, and a `base` reaching two foreign `base`s
      selfUnder =
        ks:
        (plainTreeWith (mkSchemaOption { keySemantics = ks; }) [
          {
            config.schema.base = {
              inherits = [ baseA ];
              options.extra = intOpt;
            };
          }
        ]).base;
      viaBoth =
        d:
        tree [
          (gen (openInt d))
          {
            config.schema.sub = {
              inherits = [ "base" ];
              options.s = intOpt;
            };
            config.schema.x = {
              inherits = [ "base" ];
              options.xx = intOpt;
            };
          }
        ];
      a80 = viaBoth 80;
      selfDiamond =
        x:
        (tree [
          {
            config.schema.base.inherits = [
              a80.sub
              x
            ];
          }
        ]).base;
    in
    {
      # C3 + P6 · `p` reached along two paths as two declarations of one mark: refused at the child's
      # composed read, naming the child and both paths, with `kindEq`'s sealed component.
      test-depth-2-diamond-is-refused-over-transitive-ancestors = {
        expr =
          assert (forced dOk.options.base.default).value == 80;
          dBad.options.base.default;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: kind 'd' reaches 'p' along d -> x -> p and along d -> y -> p: two declarations of 'p' mint one identity and are unequal only at sealed component\\(s\\) 'open.options.base.default': ";
        };
      };
      # The same refusal at the published map.
      test-depth-2-diamond-is-refused-at-the-ancestor-map = {
        expr =
          assert (forced (builtins.attrNames dOk.__kindAncestors)).success;
          builtins.attrNames dBad.__kindAncestors;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: kind 'd' reaches 'p' along d -> x -> p and along d -> y -> p: two declarations of 'p' ";
        };
      };
      # C2 · a subkind whose keySemantics omits a base class is refused by name, naming the kind, the
      # key and the ancestor.
      test-subkind-omitting-a-base-class-is-refused = {
        expr =
          assert (forced (builtins.attrNames subOk.options)).success;
          builtins.attrNames
            (subUnder {
              beta.category = "class";
            }).options;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: kind 'sub' inherits 'base', whose keySemantics declares the key 'alpha', and this kind's keySemantics does not: a subkind's keySemantics must hold every key of each ancestor's, with the same category; build this kind's schema with 'alpha' in its keySemantics as the ancestor declares it$";
        };
      };
      # C2 · the same key under another category is refused too.
      test-subkind-recategorising-a-base-class-is-refused = {
        expr =
          assert (forced (builtins.attrNames subOk.options)).success;
          builtins.attrNames
            (subUnder {
              alpha.category = "channel";
              beta.category = "class";
            }).options;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: kind 'sub' inherits 'base', whose keySemantics gives the key 'alpha' the category 'class', and this kind's keySemantics gives it 'channel': ";
        };
      };
      # K2 · one generator in two trees differing only in an option TYPE: equal witnesses, different
      # marks. Keyed by mark, both `base`s compose into `d`, and gen-merge refuses the conflicting
      # declaration; keyed by witness, the second was dropped and `b` read `int`, silently. The message
      # is gen-merge's and names neither `d` nor the trees (residue: the option-type merge has no kind
      # in scope). Control: `x`, which reaches only the local `base`, composes.
      test-differing-mark-parents-are-not-dropped-by-the-module-key = {
        expr =
          assert (forced k2.x.options.b.type.name).value == "string";
          k2.d.options.b.type.name;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-merge: option `b' is declared with types that do not merge \\(`int' and `string'\\); declared in <gen-merge>, via option schema.base, <gen-merge>, via option schema.base$";
        };
      };
      # K2eq · the same topology, the two `base`s differing only in an option DEFAULT: marks and
      # witnesses both collide, so they share a module key and `d` composed one of them silently.
      # The ancestor map's fold refuses the pair at `d`'s composed read.
      test-equal-mark-parents-are-refused-by-the-fold = {
        expr =
          assert (forced k2eq.x.options.b.default).value == 443;
          k2eq.d.options.b.default;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: kind 'd' reaches 'base' along d -> sub -> base and along d -> x -> base: two declarations of 'base' mint one identity and are unequal only at sealed component\\(s\\) 'modules', 'open.options.b.default': ";
        };
      };
      # An ancestor named as the kind is named as the foreign kind value, at the class check and at
      # the fold's diamond, so the text never reads as a kind inheriting itself.
      test-self-named-subkind-omitting-a-base-class-names-the-foreign-value = {
        expr =
          assert
            (forced (builtins.attrNames (selfUnder (ksBase // { beta.category = "class"; })).options)).success;
          builtins.attrNames (selfUnder { beta.category = "class"; }).options;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: kind 'base' inherits the foreign kind value 'base', whose keySemantics declares the key 'alpha', and this kind's keySemantics does not: ";
        };
      };
      test-diamond-over-a-same-named-ancestor-names-the-foreign-value = {
        expr =
          assert (forced (selfDiamond a80.x).options.b.default).value == 80;
          (selfDiamond (viaBoth 443).x).options.b.default;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: kind 'base' reaches the foreign kind value 'base' along base -> sub -> base and along base -> x -> base: two declarations of 'base' mint one identity and are unequal only at sealed component\\(s\\) 'modules', 'open.options.b.default': ";
        };
      };
    };

  # ★ THE SAME NAMES IN A MODULE THE KIND ENTRY IMPORTS (den-hoag-8x97u). The entry's defs carry
  # `entryReservation`, so gen-merge's collector refuses the name with this library's text and the
  # module's attribution. Before the door each cell read the mark at exit 0: the write landed on
  # every instance. Each carries the clean kind and an ordinary imported option as its control.
  flake.testsError.imports-route-refusals =
    let
      int7 = genMerge.mkOption {
        type = genMerge.types.int;
        default = 7;
      };
      controls =
        (forced (kindOf { } { options.role = strOpt; }).__mint.minted).success
        && (forced (kindOf { } { imports = [ { options.priority = int7; } ]; }).__mint.minted).success
        && (forced (kindOf { } ({ ... }: { imports = [ { options.priority = int7; } ]; })).__mint.minted)
          .success;
      formalMsg =
        f: file:
        "^gen-schema: kind 'host': declaration key '${f}' is a construction formal of this schema, written in a module this kind entry imports — it is fixed by the call that builds the schema option [(]`mkSchemaOption`, `mkSchemaEntryType`[)], and written there it is not read as one; pass '${f}' to that constructor, or write `config[.]${f}` for an instance field of that name, which a strict instance must declare as an option [(]module `${file}'[)]$";
      publishedMsg =
        n: file:
        "^gen-schema: kind 'host': declaration key '${n}' is a name gen-schema writes onto the kind value, written in a module this kind entry imports — there it lands on every instance, while reading `config[.]schema[.]host[.]${n}` returns the published one; write `config[.]${n}` for an instance field of that name, which a strict instance must declare as an option [(]module `${file}'[)]$";
    in
    {
      # A formal two `imports` away, on the default branch.
      test-nested-imports-formal-refuses-by-name = {
        expr =
          assert controls;
          (kindOf { } { imports = [ { imports = [ { keySemantics = [ "darwin" ]; } ]; } ]; }).__mint.minted;
        expectedError = {
          type = "ThrownError";
          msg = formalMsg "keySemantics" "[^']*";
        };
      };
      # A published name through a PATH module, whose attribution is the file.
      test-path-module-published-name-names-the-file = {
        expr =
          assert controls;
          (kindOf { } { imports = [ ./test-fixtures/imports-route-refs.nix ]; }).__mint.minted;
        expectedError = {
          type = "ThrownError";
          msg = publishedMsg "refs" "/[^']*/test-fixtures/imports-route-refs[.]nix";
        };
      };
      # A FUNCTION entry def importing a formal: the def is wrapped (an applied function's result
      # would drop an in-place marker). This is the default branch's twin of gen-aspects' functor-def
      # cell: a functor def is refused at the entry on this branch (`__functor` is reserved there).
      test-function-def-imports-route-formal-refuses-by-name = {
        expr =
          assert controls;
          (kindOf { } ({ ... }: { imports = [ { keySemantics = [ "darwin" ]; } ]; })).__mint.minted;
        expectedError = {
          type = "ThrownError";
          msg = formalMsg "keySemantics" "[^']*";
        };
      };
    };

  # THE KIND INSTANCE COLLISION (den-hoag-kind-generator-collision-d4gnx): two instances of one kind
  # declaration that share a key, imported side by side outside any kind, are compared by gen-merge's
  # key dedup with the comparison the kind publishes (`__keyEq`, the ancestor map's
  # `sealedCollisionEq`). Each cell first forces its LIVE CONTROL, one instance alone. The catchable
  # half, with the one construction imported twice, is `schema-inheritance.nix`.
  flake.testsError.kind-instance-collision =
    let
      str =
        default:
        genMerge.mkOption {
          type = genMerge.types.str;
          inherit default;
        };
      generatorOver =
        schemaOption: decl: x:
        (plainTreeWith schemaOption [
          {
            config.schema.p.options.o_p = str "p";
            config.schema.a = {
              inherits = [ "p" ];
              options.o_a = str x;
            }
            // decl;
          }
        ]).a;
      oneGenerator = generatorOver (mkSchemaOption { }) { };
      o_a = modules: (genMerge.evalModuleTree { inherit modules; }).config.o_a;
      controls = (forced (o_a [ (oneGenerator "two") ])).value == "two";
      collision = {
        type = "ThrownError";
        msg = "^gen-schema: kind 'a' is imported twice under one key: two declarations of 'a' mint one identity and are unequal only at sealed component\\(s\\) 'modules', 'open\\.options\\.o_a\\.default': a sealed component is compared by its seal, the whole value under Nix `==`, where two separately built functions are never equal, so two separate constructions are refused even where the values they compute are equal; a sealed component has no identity, because identity is minted from inert structure alone: migrate it to a first-order term, a registered constructor over inert arguments, so that it mints$";
      };
      reserved = {
        type = "ThrownError";
        msg = "^gen-schema: kind 'a': declaration key '__keyEq' is reserved — gen-schema publishes the key comparison of every kind that composes a parent, beside the key it derives from the kind's mark, and a declaration does not choose it$";
      };
      smuggled = {
        __keyEq = {
          subject = null;
          decide = _: _: true;
        };
      };
      # gen-schema over a gen-merge whose published key list does not carry `__keyEq`: the pairing
      # an older gen-merge makes.
      withoutProtocol = genMerge // {
        moduleSyntax = genMerge.moduleSyntax // {
          structured = builtins.filter (k: k != "__keyEq") genMerge.moduleSyntax.structured;
        };
      };
      oldSchema = import ../lib {
        inherit prelude;
        graph = genGraph;
        merge = withoutProtocol;
        algebra = genAlgebra;
        identity = genIdentity;
      };
    in
    {
      test-two-constructions-side-by-side-refused-by-name = {
        expr =
          assert controls;
          o_a [
            (oneGenerator "one")
            (oneGenerator "two")
          ];
        expectedError = collision;
      };
      test-two-constructions-other-order-refused-by-name = {
        expr =
          assert controls;
          o_a [
            (oneGenerator "two")
            (oneGenerator "one")
          ];
        expectedError = collision;
      };
      # Two constructions whose values are EQUAL are refused by the same text: it names them separate
      # constructions compared by seal, and never says that their values differ (O1, gate P3).
      test-two-constructions-with-equal-values-refused-by-name = {
        expr =
          assert controls;
          o_a [
            (oneGenerator "one")
            (oneGenerator "one")
          ];
        expectedError = collision;
      };
      # A kind declaration may not choose its own comparison: refused at the declaration, keyed or not.
      test-declaration-carrying-key-eq-refused-by-name = {
        expr =
          assert controls;
          o_a [ (generatorOver (mkSchemaOption { }) smuggled "one") ];
        expectedError = reserved;
      };
      test-declaration-carrying-key-and-key-eq-refused-by-name = {
        expr =
          assert controls;
          o_a [ (generatorOver (mkSchemaOption { }) (smuggled // { key = "mine"; }) "one") ];
        expectedError = reserved;
      };
      # Over a gen-merge that does not read `__keyEq`, a kind composing a parent is refused by name,
      # naming the protocol it requires, where the field would otherwise be read as undeclared config.
      test-gen-merge-without-the-protocol-refused-by-name = {
        expr =
          assert controls;
          o_a [ (generatorOver (oldSchema.mkSchemaOption { }) { } "one") ];
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: kind 'a' composes a parent, so its module is keyed by its mark and publishes the key comparison `__keyEq', and the gen-merge it is evaluated with does not read that key \\(its `moduleSyntax\\.structured' does not list `__keyEq'\\)\\. gen-schema requires a gen-merge carrying the `__keyEq' key-comparison protocol; .*$";
        };
      };
    };

  # THE WALK'S REFUSAL ON A WITNESS COLLISION (den-hoag-4i0o5). One declaration applied in two trees
  # gives two kinds one content witness, so an acyclic chain through them and a genuine cycle through
  # them meet the walk identically. Both cells read the same refusal, which names both readings and
  # the remedy; `ci/tests/kind-witness-collision.nix` holds the remedy's admitted twin.
  flake.testsError.witness-collision-refusals =
    let
      intOpt = genMerge.mkOption { type = genMerge.types.int; };
      layer = name: parent: o: {
        config.schema.${name} = {
          inherits = [ parent ];
          options.${o} = intOpt;
        };
      };
      m0 = plainTree [ { config.schema.mid.options.m = intOpt; } ];
      u1 = plainTree [ (layer "base" m0.mid "x") ];
      m1 = plainTree [ (layer "mid" u1.base "m2") ];
      u2 = plainTree [ (layer "base" m1.mid "x") ];
      gA = plainTree [ (layer "base" gB.base "x") ];
      gB = plainTree [ (layer "base" gA.base "x") ];
      tagged =
        tag: name: parent: o:
        layer name parent o // { _file = "layer:${tag}"; };
      tA = plainTree [ (tagged "g" "base" tB.base "x") ];
      tB = plainTree [ (tagged "g" "base" tA.base "x") ];
      b0 = plainTree [ { config.schema.base.options.b = intOpt; } ];
      # options through the kind entry's own `imports` are not directly declared, so the witness does
      # not read them: `y1` and `y2` differ, and the two applications still collide
      ilayer = parent: extra: {
        config.schema.base = {
          inherits = [ parent ];
          imports = [ extra ];
        };
      };
      i1 = plainTree [ (ilayer b0.base { options.y1 = intOpt; }) ];
      i2 = plainTree [ (ilayer i1.base { options.y2 = intOpt; }) ];
      # one module FILE applied in two trees: a module imported by path takes its file from the path,
      # so neither a `_file` it sets itself nor one on a module importing it separates the two
      byPath =
        file: args:
        (genMerge.evalModuleTree {
          specialArgs = args // {
            inherit intOpt;
          };
          modules = [ { options.schema = mkSchemaOption { }; } ] ++ [ file ];
        }).config.schema;
      st1 = byPath ./test-fixtures/shared-layer-tagged.nix {
        parent = b0.base;
        tag = "1";
      };
      st2 = byPath ./test-fixtures/shared-layer-tagged.nix {
        parent = st1.base;
        tag = "2";
      };
      sw1 = byPath {
        _file = "w1";
        imports = [ ./test-fixtures/shared-layer.nix ];
      } { parent = b0.base; };
      sw2 = byPath {
        _file = "w2";
        imports = [ ./test-fixtures/shared-layer.nix ];
      } { parent = sw1.base; };
      # THE ENUMERATED MISS (ADR-0025 item 1): `k` reaches itself only through `x2`, whose witness twin
      # `x1` (no cycle behind it) the walk visits first and so skips `x2`; the twin given its own
      # `_file` is visited, and the cycle is refused by name
      xl = parent: {
        config.schema.x = {
          inherits = [ parent ];
          options.o = intOpt;
        };
      };
      vK =
        x1Tag:
        let
          p1 = plainTree [ { config.schema.p.options.p1 = intOpt; } ];
          x1 = plainTree [ (xl p1.p // x1Tag) ];
          a = plainTree [
            {
              config.schema.a = {
                inherits = [ x1.x ];
                options.oa = intOpt;
              };
            }
          ];
          p2 = plainTree [
            {
              config.schema.p = {
                inherits = [ k.k ];
                options.p2 = intOpt;
              };
            }
          ];
          x2 = plainTree [ (xl p2.p) ];
          b = plainTree [
            {
              config.schema.b = {
                inherits = [ x2.x ];
                options.ob = intOpt;
              };
            }
          ];
          k = plainTree [
            {
              config.schema.k = {
                inherits = [
                  a.a
                  b.b
                ];
                options.ok = intOpt;
              };
            }
          ];
        in
        k.k;
      refuses = members: path: kind: {
        type = "ThrownError";
        msg = "^gen-schema: kind '${kind}' reaches a kind with its own content witness through its parents \\(${path}\\), among kinds \\[${members}\\]: either it inherits itself, an inheritance cycle, and a kind may inherit only kinds resolved in a strictly earlier pass; or two kinds named '${kind}' were declared from one source with the same parent names and the same directly declared option names, which the witness does not tell apart before composition, and giving each such module value its own `_file` separates them \\(a module imported by path takes its file from the path: import it as a value, or give each application a distinct path\\)$";
      };
    in
    {
      test-an-acyclic-chain-through-one-declaration-names-both-readings = {
        expr = builtins.attrNames u2.base.options;
        expectedError = refuses "base mid" "base -> mid -> base" "base";
      };
      test-a-cycle-through-one-declaration-reads-the-same = {
        expr = builtins.attrNames gA.base.options;
        expectedError = refuses "base" "base -> base" "base";
      };
      test-a-cycle-through-equal-tags-reads-the-same = {
        expr = builtins.attrNames tA.base.options;
        expectedError = refuses "base" "base -> base" "base";
      };
      test-options-through-imports-are-not-read-by-the-witness = {
        expr = builtins.attrNames i2.base.options;
        expectedError = refuses "base" "base -> base" "base";
      };
      test-a-path-module-setting-its-own-file-still-collides = {
        expr = builtins.attrNames st2.base.options;
        expectedError = refuses "base" "base -> base" "base";
      };
      test-a-path-module-under-a-tagged-importer-still-collides = {
        expr = builtins.attrNames sw2.base.options;
        expectedError = refuses "base" "base -> base" "base";
      };
      test-a-tagged-twin-reveals-the-cycle-behind-it = {
        expr = builtins.attrNames (vK { _file = "x:1"; }).options;
        expectedError = refuses "b k p x" "k -> b -> x -> p -> k" "k";
      };
      # ★ ENUMERATED, NOT CLOSED: the walk's visited set is keyed by witness, so `k`'s walk, reaching
      # the cycle only through the second of two twins, misses it. What follows is the evaluator's:
      # nix and Determinate recurse uncatchably composing `k`, while Lix forces `b` first, whose own
      # walk meets `b`'s witness, and refuses by name. Each outcome is pinned on its own family, read
      # off `builtins.nixVersion` as gen-harness's `error-plane-engines.nix` reads it (`-lix` suffix).
      test-a-cycle-behind-an-untagged-twin-aborts = {
        expr = builtins.attrNames (vK { }).options;
        expectedError =
          if builtins.match ".*-lix" builtins.nixVersion != null then
            refuses "b k p x" "b -> x -> p -> k -> b" "b"
          else
            {
              type = "EvalError";
              msg = "infinite recursion encountered";
            };
      };
    };

  # den-hoag-registry-types-outside-kind-d24lq: a deferred declaration merged where no registry binds
  # it refuses by name, naming the binding and the direct form, and a bound one keeps its own wording.
  flake.testsError.unbound-declaration-refusals =
    let
      inherit (genSchema) declarationOf setOf evalSchema;
      outside =
        type: v:
        (genMerge.evalModuleTree {
          modules = [
            { options.o = genMerge.mkOption { inherit type; }; }
            { o = v; }
          ];
        }).config.o;
      unbound = {
        type = "ThrownError";
        msg = "^gen-schema: o.*: `declarationOf \"host\"' is unbound here\\. A deferred declaration resolves only through a registry binding .*$";
      };
      schema = evalSchema {
        modules = [
          {
            config.schema.host = { };
            config.schema.svc.options.host = genMerge.mkOption { type = declarationOf "host"; };
          }
        ];
      };
    in
    {
      test-unbound-scalar-refused-by-name = {
        expr = outside (declarationOf "host") "nope";
        expectedError = unbound;
      };
      test-unbound-set-element-refused-by-name = {
        expr = builtins.deepSeq (outside (setOf (declarationOf "host")) [
          "a"
          "a"
        ]) null;
        expectedError = unbound;
      };
      test-unbound-refined-refused-by-name = {
        expr = outside (genSchema.refined (declarationOf "host") {
          check = _: true;
          message = "any";
        }) "a";
        expectedError = unbound;
      };
      test-bound-dangling-keeps-its-wording = {
        expr =
          (genMerge.evalModuleTree {
            modules = [
              (
                { config, ... }:
                {
                  options.hosts = mkInstanceRegistry schema.host { };
                  options.svcs = mkInstanceRegistry schema.svc { refs.host = config.hosts; };
                  config.hosts.a = { };
                  config.svcs.s.host = "nope";
                }
              )
            ];
          }).config.svcs.s.host.name;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-schema: ref field 'host' on kind 'svc': reference 'nope' not found in instance registry \\(available: a\\)$";
        };
      };
    };
}
