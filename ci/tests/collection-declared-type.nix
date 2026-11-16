# A collection may declare its WHOLE type (`type`, opt-in): its definitions, a mixin's included, are
# merged by that type through gen-merge, so its element checks, its property resolution at every depth
# and its discharged-element count are the type's, as an option of that type gives them. Its `default`
# is still the fold's seed (resolved and checked through the type, then folded on by its shape, outside
# the definitions' priority pool), so a declared and an undeclared collection agree on every seed case.
# Omitted, a collection keeps the inferred lazy container (`collection-element.nix`). Each value cell
# runs one fixture through both engines where nixpkgs has a twin: the gen arm is the collection on a
# schema kind, the nixpkgs arm an option of the declared type. The refusals (the closed field set, a
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
          options.c =
            lib.mkOption {
              inherit type;
            }
            // default;
        }
      ]
      ++ map (d: { config.c = d; }) defs;
    }).config.c;
  lsStr = T.listOf T.str;
  typed = default: type: { inherit default type; };
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
in
{
  flake.tests.collection-declared-type = {
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
