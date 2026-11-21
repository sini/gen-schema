# A collection may declare its WHOLE type (`type`, opt-in): its definitions, a mixin's included, are
# merged by that type through gen-merge, so its element checks, its property resolution at every depth
# and its discharged-element count are the type's, as an option of that type gives them. A list or
# attrset `default` is still the fold's seed (resolved and checked through the type, then folded on by
# its shape, outside the definitions' priority pool), so a declared and an undeclared collection agree
# on every seed case; any other `default` is one definition at `mkOptionDefault`, as an option's is.
# Omitted, a collection keeps the inferred lazy container (`collection-element.nix`). Each value cell
# runs one fixture through both engines where nixpkgs has a twin: the gen arm is the collection on a
# schema kind, the nixpkgs arm an option of the declared type on an `attrsOf (submodule …)` entry, one
# module evaluation above the field as gen's `schema` submodule is (`collection-no-default.nix`), so
# the definitions fold in the order they are written. The refusals (the closed field set, a
# failed check, `type` beside `merge` or on a built-in) are in `../tests-error.nix`.
#
# RED before: `type` was an unread field, so `[ (mkIf false "a") "b" ]` counted 2 and read as a raw
# `mkIf` record, `[ 1 ]` was served under `listOf str`, and a depth-2 property was never resolved.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  gm = genMerge;
  T = gm.types;
  NT = lib.types;
  userWith =
    opts: defs:
    (gm.evalModuleTree { } (
      [
        { options.schema = genSchema.mkSchemaOption opts; }
        { config.schema.user = { }; }
      ]
      ++ map (d: { config.schema.user = d; }) defs
    )).config.schema.user;
  user = collections: userWith { inherit collections; };
  twin =
    type: default: defs:
    (lib.evalModules {
      modules = [
        {
          options.schema = lib.mkOption {
            type = NT.attrsOf (
              NT.submodule {
                options.c =
                  lib.mkOption {
                    inherit type;
                  }
                  // default;
              }
            );
          };
        }
        { config.schema.user = { }; }
      ]
      ++ map (d: { config.schema.user.c = d; }) defs;
    }).config.schema.user.c;
  lsStr = T.listOf T.str;
  typed = default: type: { inherit default type; };
  # gen-merge's stated untyped law (`mergeUntyped`'s agreement) under a declared `unspecified`, where
  # nixpkgs refuses: the served value and its `typeOf`, since `1 == 1.0` in Nix
  agreement = defs: {
    gen =
      let
        v = (user { p = typed 5 T.unspecified; } (map (x: { p = x; }) defs)).p;
      in
      {
        value = v;
        type = builtins.typeOf v;
      };
    nixpkgs = (builtins.tryEval (twin NT.unspecified { default = 5; } defs)).success;
  };
  e2g52 = l: [
    (l.mkIf false "a")
    "b"
  ];
  # the seed law, over `default = [ "a" ]`, declared and undeclared: one value per case
  seedOf = coll: defs: (user { c = coll; } (map (x: { c = x; }) defs)).c;
  seedCase = defs: {
    declared = seedOf (typed [ "a" ] lsStr) defs;
    undeclared = seedOf { default = [ "a" ]; } defs;
  };
  seedSame = v: {
    declared = v;
    undeclared = v;
  };
  attrsSeedCase = defs: {
    declared = seedOf (typed { x = "1"; } (T.attrsOf T.str)) defs;
    undeclared = seedOf { default.x = "1"; } defs;
  };
  # the kind's foreign key, over a declared type whose every field but `_type` aborts
  opaque = {
    _type = "option-type";
    name = abort "opaque type forced: name";
    check = abort "opaque type forced: check";
    merge = abort "opaque type forced: merge";
    description = abort "opaque type forced: description";
    functor = abort "opaque type forced: functor";
  };
  even = x: builtins.isInt x && x / 2 * 2 == x;
  evenT = gm.mkOptionType {
    name = "even";
    check = even;
    merge = _: defs: (builtins.head defs).value;
  };
  oneEntry = genSchema.mkSchemaEntryType { collections.ports = typed [ ] (T.listOf evenT); };
  redeclared =
    entries: val:
    (gm.evalModuleTree { } (
      map (e: { options.kinds = gm.mkOption { type = T.lazyAttrsOf e; }; }) entries
      ++ [ { kinds.k.ports = val; } ]
    )).config.kinds.k.ports;
  # a declared type's scalar default, gen arm and nixpkgs arm over one fixture: `ty` names the
  # element type in both engines, `def` builds the definitions with its engine's properties
  scalarVals = {
    str = {
      d = "d";
      v = "x";
    };
    int = {
      d = 4;
      v = 7;
    };
    bool = {
      d = false;
      v = true;
    };
  };
  scalarCase = ty: default: def: {
    gen = (user { p = typed default (T.nullOr T.${ty}); } (map (x: { p = x; }) (def gm))).p;
    nixpkgs = twin (NT.nullOr NT.${ty}) { inherit default; } (def lib);
  };
  # one cell per (type, default, definition), its expected value hand-stated in `scalarExpected`
  scalarDefs = ty: {
    one = _: [ scalarVals.${ty}.v ];
    mkiffalse = l: [ (l.mkIf false scalarVals.${ty}.v) ];
    mkforce = l: [ (l.mkForce scalarVals.${ty}.v) ];
    mkdefault = l: [ (l.mkDefault scalarVals.${ty}.v) ];
  };
  # a definition outranks the default; where every definition discharges, the default answers
  scalarExpected = d: v: {
    one = v;
    mkiffalse = d;
    mkforce = v;
    mkdefault = v;
  };
  # an order-reading type's definitions, N = 2 and 3 and every order property, against the twin:
  # `sep` is the type's separator, and the expected value is the written order resolved by the
  # order properties, as nixpkgs' option on the entry gives it
  orderTypes = {
    lines = {
      sep = "\n";
      t = NT.lines;
      d = "";
    };
    commas = {
      sep = ",";
      t = NT.commas;
      d = "";
    };
    nulloflines = {
      sep = "\n";
      t = NT.nullOr NT.lines;
      d = null;
    };
    unspecified = {
      sep = "";
      t = T.unspecified;
      nt = NT.unspecified;
      d = "";
    };
  };
  orderDefs = {
    two = _: [
      "x"
      "y"
    ];
    three = _: [
      "x"
      "y"
      "z"
    ];
    before = l: [
      "x"
      (l.mkBefore "y")
    ];
    after = l: [
      (l.mkAfter "x")
      "y"
    ];
    order = l: [
      (l.mkOrder 1600 "x")
      (l.mkOrder 400 "y")
      "z"
    ];
  };
  orderExpected = {
    two = [
      "x"
      "y"
    ];
    three = [
      "x"
      "y"
      "z"
    ];
    before = [
      "y"
      "x"
    ];
    after = [
      "y"
      "x"
    ];
    order = [
      "y"
      "z"
      "x"
    ];
  };
  orderCells = builtins.listToAttrs (
    builtins.concatMap (
      tn:
      let
        o = orderTypes.${tn};
      in
      map (dn: {
        name = "test-scalar-default-order-${tn}-${dn}";
        value = {
          expr = {
            gen = (user { p = typed o.d o.t; } (map (x: { p = x; }) (orderDefs.${dn} gm))).p;
            nixpkgs = twin (o.nt or o.t) { default = o.d; } (orderDefs.${dn} lib);
          };
          expected =
            let
              v = builtins.concatStringsSep o.sep orderExpected.${dn};
            in
            {
              gen = v;
              nixpkgs = v;
            };
        };
      }) (builtins.attrNames orderDefs)
    ) (builtins.attrNames orderTypes)
  );
  scalarCells = builtins.listToAttrs (
    builtins.concatMap (
      ty:
      builtins.concatMap
        (
          dn:
          let
            d = if dn == "null" then null else scalarVals.${ty}.d;
            want = scalarExpected d scalarVals.${ty}.v;
          in
          map (def: {
            name = "test-scalar-default-${ty}-${dn}-${def}";
            value = {
              expr = scalarCase ty d (scalarDefs ty).${def};
              expected = {
                gen = want.${def};
                nixpkgs = want.${def};
              };
            };
          }) (builtins.attrNames (scalarDefs ty))
        )
        [
          "null"
          "value"
        ]
    ) (builtins.attrNames scalarVals)
  );
in
{
  flake.tests.collection-declared-type =
    scalarCells
    // orderCells
    // {
      # ── the type merges the definitions, as an option of that type does ──────────────────────────
      # e2g52: a discharged element is not counted (undeclared, it is; `collection-element.nix`)
      test-discharged-element-not-counted = {
        expr = {
          gen = builtins.length (user { classes = typed [ ] lsStr; } [ { classes = e2g52 gm; } ]).classes;
          nixpkgs = builtins.length (twin (NT.listOf NT.str) { default = [ ]; } [ (e2g52 lib) ]);
        };
        expected = {
          gen = 1;
          nixpkgs = 1;
        };
      };
      test-discharged-element-value = {
        expr = {
          gen = (user { classes = typed [ ] lsStr; } [ { classes = e2g52 gm; } ]).classes;
          nixpkgs = twin (NT.listOf NT.str) { default = [ ]; } [ (e2g52 lib) ];
        };
        expected = {
          gen = [ "b" ];
          nixpkgs = [ "b" ];
        };
      };
      # a property at depth 2 is resolved
      test-depth-two-property-resolved = {
        expr = {
          gen =
            (user { env = typed { } (T.attrsOf (T.attrsOf T.int)); } [
              {
                env.a = {
                  b = gm.mkIf false 1;
                  c = 2;
                };
              }
            ]).env;
          nixpkgs = twin (NT.attrsOf (NT.attrsOf NT.int)) { default = { }; } [
            {
              a = {
                b = lib.mkIf false 1;
                c = 2;
              };
            }
          ];
        };
        expected = {
          gen.a.c = 2;
          nixpkgs.a.c = 2;
        };
      };
      # a foreign (nixpkgs) type is accepted, as gen-merge accepts one for an option
      test-foreign-type-merges = {
        expr = (user { classes = typed [ ] (NT.listOf NT.str); } [ { classes = e2g52 gm; } ]).classes;
        expected = [ "b" ];
      };
      # a mixin's contribution is one more definition through the type
      test-mixin-contribution-merged = {
        expr =
          (userWith {
            collections.classes = typed [ ] lsStr;
            baseModule = { };
            mixins = [
              (genSchema.mkMixin { } (_: {
                classes = [ "m" ];
              }))
            ];
          } [ { classes = [ "k" ]; } ]).classes;
        expected = [
          "k"
          "m"
        ];
      };
      # `computed` and the `mkType` arm read the merged value
      test-computed-reads-declared-value = {
        expr =
          (userWith {
            collections.ports = typed [ ] (T.listOf T.int);
            computed = collections: _: { n = builtins.length collections.ports; };
          } [ { ports = e2g52 gm; } ]).n;
        expected = 1;
      };
      test-mktype-arm-reads-declared-value = {
        expr =
          (userWith {
            collections.ports = typed [ ] (T.listOf T.str);
            mkType = { collections, ... }: { inherit (collections) ports; };
          } [ { ports = e2g52 gm; } ]).ports;
        expected = [ "b" ];
      };
      # the published key set is unchanged by a declared type
      test-collection-keys-unchanged = {
        expr =
          (gm.evalModuleTree { } [
            { options.schema = genSchema.mkSchemaOption { collections.ports = typed [ ] lsStr; }; }
          ]).config.schema._collectionKeys;
        expected = [
          "inherits"
          "methods"
          "parent"
          "ports"
          "validators"
        ];
      };
      # one entry value declared twice merges, and its check still applies (planted: `../tests-error.nix`)
      test-one-entry-value-redeclared-merges = {
        expr =
          redeclared
            [
              oneEntry
              oneEntry
            ]
            [ 4 ];
        expected = [ 4 ];
      };
      # the kind's key never forces the declared type
      test-key-does-not-force-the-type = {
        expr =
          let
            k = userWith {
              collections.w = {
                default = [ ];
                identity = false;
                type = opaque;
              };
            } [ ];
          in
          builtins.isString (k.__functor k { }).key;
        expected = true;
      };

      # ── the seed law is kept: declared = undeclared on every case ────────────────────────────────
      test-seed-plain = {
        expr = seedCase [ [ "b" ] ];
        expected = seedSame [
          "a"
          "b"
        ];
      };
      test-seed-mkforce = {
        expr = seedCase [ (gm.mkForce [ "b" ]) ];
        expected = seedSame [
          "a"
          "b"
        ];
      };
      test-seed-mkdefault = {
        expr = seedCase [ (gm.mkDefault [ "b" ]) ];
        expected = seedSame [
          "a"
          "b"
        ];
      };
      test-seed-mkbefore = {
        expr = seedCase [ (gm.mkBefore [ "b" ]) ];
        expected = seedSame [
          "a"
          "b"
        ];
      };
      test-seed-discharged = {
        expr = seedCase [ (gm.mkIf false [ "b" ]) ];
        expected = seedSame [ "a" ];
      };
      test-seed-no-definition = {
        expr = seedCase [ ];
        expected = seedSame [ "a" ];
      };
      test-seed-attrs-disjoint = {
        expr = attrsSeedCase [ { y = "2"; } ];
        expected = seedSame {
          x = "1";
          y = "2";
        };
      };
      test-seed-attrs-overlap = {
        expr = attrsSeedCase [ { x = "3"; } ];
        expected = seedSame { x = "3"; };
      };
      # the seed fold is the default's shape fold (`//`, shallow), never the type's own merge
      test-seed-nested-attrs-shallow = {
        expr = {
          declared = seedOf (typed { a.b = 1; } (T.attrsOf (T.attrsOf T.int))) [ { a.c = 2; } ];
          undeclared = seedOf { default.a.b = 1; } [ { a.c = 2; } ];
        };
        expected = seedSame { a.c = 2; };
      };
      # a property on a default's element is resolved by the type, as the seed alone
      test-seed-element-property-resolved = {
        expr = seedOf (typed (e2g52 gm) lsStr) [ ];
        expected = [ "b" ];
      };
      # with no default there is no seed
      test-no-default-typed = {
        expr = seedOf { type = lsStr; } [ [ "x" ] ];
        expected = [ "x" ];
      };

      # ── a scalar default is an option default (ADR-0039 rule (1)) ────────────────────────────────
      # A declared type's default that is neither a list nor an attrset has no seed shape: it is one
      # definition at `mkOptionDefault`, so a definition outranks it, as nixpkgs drops an option's
      # default. RED before: every cell below was refused, "no seed to fold".
      # two equal definitions of a bool are one value, under either default
      test-scalar-default-bool-null-two = {
        expr = scalarCase "bool" null (_: [
          true
          true
        ]);
        expected = {
          gen = true;
          nixpkgs = true;
        };
      };
      test-scalar-default-bool-value-two = {
        expr = scalarCase "bool" false (_: [
          true
          true
        ]);
        expected = {
          gen = true;
          nixpkgs = true;
        };
      };
      # a mixin's contribution is a definition: it outranks the default as the kind's own does
      test-scalar-default-mixin-contribution = {
        expr =
          (userWith {
            collections.p = typed null (T.nullOr T.str);
            baseModule = { };
            mixins = [
              (genSchema.mkMixin { } (_: {
                p = "m";
              }))
            ];
          } [ ]).p;
        expected = "m";
      };
      # a mixin's contribution is one more definition after the kind's own, in one pool with the
      # default, as `collection-mixin.nix` models it on the nixpkgs arm
      test-scalar-default-mixin-order = {
        expr = {
          gen =
            (userWith {
              collections.p = typed "" NT.lines;
              baseModule = { };
              mixins = [
                (genSchema.mkMixin { } (_: {
                  p = "m";
                }))
              ];
            } [ { p = "k"; } ]).p;
          nixpkgs = twin NT.lines { default = ""; } [
            "k"
            "m"
          ];
        };
        expected = {
          gen = "k\nm";
          nixpkgs = "k\nm";
        };
      };
      # gen-merge's stated untyped law under a declared `unspecified`, not a twin equality: equal nulls
      # are one value, where nixpkgs refuses them (gen-merge README, `mergeUntyped`)
      test-scalar-default-unspecified-equal-nulls = {
        expr = {
          gen =
            (user { p = typed 5 T.unspecified; } [
              { p = null; }
              { p = null; }
            ]).p;
          nixpkgs =
            (builtins.tryEval (
              twin NT.unspecified { default = 5; } [
                null
                null
              ]
            )).success;
        };
        expected = {
          gen = null;
          nixpkgs = false;
        };
      };
      # gen-merge's stated untyped law, not a twin equality (ADR-0039 Reach "SERVING BEYOND NIXPKGS IS
      # BOUNDED BY CORRECTNESS", value oracle): equal floats are one value, and an int beside an equal
      # float is the first-written definition, its type kept; nixpkgs refuses each. The check oracle is
      # vacuous: `T.unspecified.check` accepts every value, so there is no rejected value to plant.
      test-scalar-default-unspecified-equal-floats = {
        expr = agreement [
          1.5
          1.5
        ];
        expected = {
          gen = {
            value = 1.5;
            type = "float";
          };
          nixpkgs = false;
        };
      };
      test-scalar-default-unspecified-int-beside-float = {
        expr = agreement [
          1
          1.0
        ];
        expected = {
          gen = {
            value = 1;
            type = "int";
          };
          nixpkgs = false;
        };
      };
      test-scalar-default-unspecified-float-beside-int = {
        expr = agreement [
          1.0
          1
        ];
        expected = {
          gen = {
            value = 1.0;
            type = "float";
          };
          nixpkgs = false;
        };
      };
      # a list value under a scalar default: the definitions concatenate in the written order
      test-scalar-default-order-nullor-list = {
        expr = {
          gen =
            (user { p = typed null (T.nullOr (T.listOf T.str)); } [
              { p = [ "x" ]; }
              { p = [ "y" ]; }
            ]).p;
          nixpkgs = twin (NT.nullOr (NT.listOf NT.str)) { default = null; } [
            [ "x" ]
            [ "y" ]
          ];
        };
        expected = {
          gen = [
            "x"
            "y"
          ];
          nixpkgs = [
            "x"
            "y"
          ];
        };
      };
      # the law is the type's, not `nullOr`'s: a plain `str` with a default
      test-scalar-default-plain-type = {
        expr = {
          gen = (user { p = typed "d" T.str; } [ { p = "x"; } ]).p;
          nixpkgs = twin NT.str { default = "d"; } [ "x" ];
        };
        expected = {
          gen = "x";
          nixpkgs = "x";
        };
      };
      # a foreign (nixpkgs) type takes the same law: the definition outranks the default
      test-scalar-default-foreign-type = {
        expr = {
          one = (user { p = typed null (NT.nullOr NT.str); } [ { p = "x"; } ]).p;
          mkdefault = (user { p = typed null (NT.nullOr NT.str); } [ { p = gm.mkDefault "x"; } ]).p;
          mkiffalse = (user { p = typed "d" (NT.nullOr NT.str); } [ { p = gm.mkIf false "x"; } ]).p;
        };
        expected = {
          one = "x";
          mkdefault = "x";
          mkiffalse = "d";
        };
      };
      # a kind that never defines it is served the default resolved through the type, as before
      test-scalar-default-undefined-served = {
        expr = (user { p = typed "d" (T.nullOr T.str); } [ ]).p;
        expected = "d";
      };

      # ── guards: the legal fields, and an undeclared collection, as before ────────────────────────
      test-legal-fields-served = {
        expr =
          (user {
            classes = {
              default = [ ];
              merge = a: b: a ++ b;
              identity = false;
            };
          } [ { classes = [ "x" ]; } ]).classes;
        expected = [ "x" ];
      };
      test-empty-declaration-served = {
        expr = (user { c = { }; } [ { c = [ "x" ]; } ]).c;
        expected = [ "x" ];
      };
      # e2g52 undeclared stays at 2: its residue is open (`collection-element.nix`)
      test-undeclared-discharged-element-still-counted = {
        expr = builtins.length (user { classes.default = [ ]; } [ { classes = e2g52 gm; } ]).classes;
        expected = 2;
      };
    };
}
