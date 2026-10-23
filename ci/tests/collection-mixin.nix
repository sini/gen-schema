# A collection value a mixin contributes is a definition of the collection, folded with the kind's
# own definitions through the collection's type: a property on the mixin's value or on one of its
# elements is resolved as it is on the kind, and the kind's priorities and the mixin's meet in one
# pool, as a mixin's ordinary field already meets the kind's. Each value cell runs ONE fixture
# through both engines: the gen arm is the collection on a schema kind with one mixin, the nixpkgs
# arm the same field on an `attrsOf (submodule …)` entry with the kind's definitions, then the
# mixin's, as definitions of one option. The wrong-shape and discharged-element refusals are in
# `../tests-error.nix`.
#
# RED before: the mixin's values were folded raw onto the kind's value, so a `{ _type = …; }` record
# reached the served value, and a property on the mixin's whole value aborted the list fold.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  gm = genMerge;
  L = {
    default = [ ];
  };
  A = {
    default = { };
  };
  listT = t: t.listOf t.str;
  lazyAttrsT = t: t.lazyAttrsOf t.str;

  # `coll` null: a built-in collection, never redeclared. `kind`: the kind's own definitions; `mix`:
  # one value per mixin, in the order the mixins are listed.
  genOf =
    coll: field: kind: mix:
    (gm.evalModuleTree { } (
      [
        {
          options.schema = genSchema.mkSchemaOption (
            (if coll == null then { } else { collections.${field} = coll; })
            // {
              baseModule = { };
              mixins = map (
                v:
                genSchema.mkMixin { } (_: {
                  ${field} = v;
                })
              ) mix;
            }
          );
        }
        { config.schema.user = { }; }
      ]
      ++ map (v: { config.schema.user.${field} = v; }) kind
    )).config.schema.user.${field};
  twinOf =
    type: default: field: defs:
    (lib.evalModules {
      modules = [
        {
          options.schema = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options.${field} = lib.mkOption {
                  type = type lib.types;
                  inherit default;
                };
              }
            );
          };
        }
      ]
      ++ map (v: { config.schema.user.${field} = v; }) defs;
    }).config.schema.user.${field};
  # `mk` builds `{ kind; mix; }` from a constructor set, so neither engine gets its own fixture. One
  # mixin per cell, so the twin's order (the kind's, then the mixin's) is the bridge's.
  bothLaws =
    coll: type: default: field: mk:
    let
      g = mk gm;
      n = mk lib;
    in
    {
      gen = genOf coll field g.kind g.mix;
      nixpkgs = twinOf type default field (n.kind ++ n.mix);
    };
  same = v: {
    gen = v;
    nixpkgs = v;
  };
in
{
  flake.tests.collection-mixin = {
    # the positive control: the kind's elements, then the mixin's, on both arms
    test-plain = {
      expr = bothLaws L listT [ ] "classes" (_: {
        kind = [ [ "k" ] ];
        mix = [ [ "a" ] ];
      });
      expected = same [
        "k"
        "a"
      ];
    };

    # ── a property on a mixin's element or key is resolved ──────────────────────────────────────
    test-list-element-mkif-true = {
      expr = bothLaws L listT [ ] "classes" (l: {
        kind = [ [ "k" ] ];
        mix = [ [ (l.mkIf true "a") ] ];
      });
      expected = same [
        "k"
        "a"
      ];
    };
    test-list-element-mkdefault = {
      expr = bothLaws L listT [ ] "classes" (l: {
        kind = [ ];
        mix = [
          [
            (l.mkDefault "a")
            "b"
          ]
        ];
      });
      expected = same [
        "a"
        "b"
      ];
    };
    test-attrs-key-mkmerge = {
      expr = bothLaws A lazyAttrsT { } "metadata" (l: {
        kind = [ ];
        mix = [ { region = l.mkMerge [ "eu" ]; } ];
      });
      expected = same { region = "eu"; };
    };
    test-builtin-inherits-element-mkif-true = {
      expr = bothLaws null listT [ ] "inherits" (l: {
        kind = [ ];
        mix = [ [ (l.mkIf true "x") ] ];
      });
      expected = same [ "x" ];
    };

    # ── a property on a mixin's whole value is resolved ─────────────────────────────────────────
    test-attrs-top-mkif-true = {
      expr = bothLaws A lazyAttrsT { } "metadata" (l: {
        kind = [ ];
        mix = [ (l.mkIf true { r = "m"; }) ];
      });
      expected = same { r = "m"; };
    };
    # an explicit `merge` folds whole definitions; their top level is resolved
    test-explicit-top-mkif-false = {
      expr =
        bothLaws
          {
            default = null;
            merge = _: v: v;
          }
          (
            _:
            lib.mkOptionType {
              name = "last";
              merge = _: defs: (lib.last defs).value;
            }
          )
          null
          "rank"
          (l: {
            kind = [ 5 ];
            mix = [ (l.mkIf false 7) ];
          });
      expected = same 5;
    };

    # ── the kind's priorities and the mixin's meet in one pool ──────────────────────────────────
    test-pool-kind-mkforce = {
      expr = bothLaws L listT [ ] "classes" (l: {
        kind = [ (l.mkForce [ "k" ]) ];
        mix = [ [ "a" ] ];
      });
      expected = same [ "k" ];
    };
    test-pool-attrs-key-mixin-mkdefault = {
      expr = bothLaws A lazyAttrsT { } "metadata" (l: {
        kind = [ { region = "us"; } ];
        mix = [ { region = l.mkDefault "eu"; } ];
      });
      expected = same { region = "us"; };
    };
    # every stack entry is a definition in the pool, so a priority ranks one mixin's against
    # another's, where an ordinary field in the same stack keeps the head (the last mixin applied)
    test-pool-mixin-mkforce-over-mixin = {
      expr = bothLaws L listT [ ] "classes" (l: {
        kind = [ ];
        mix = [
          (l.mkForce [ "x" ])
          [ "y" ]
        ];
      });
      expected = same [ "x" ];
    };

    # ── gen-schema's law, kept: the cells that served before the mixin's value was resolved ──────
    # two mixins: the kind's elements, then the last mixin applied, then the first
    test-keep-order = {
      expr =
        genOf L "classes"
          [ [ "k" ] ]
          [
            [ "m1" ]
            [ "m2" ]
          ];
      expected = [
        "k"
        "m2"
        "m1"
      ];
    };
    # an attrset key keeps `//`'s last-wins over plain definitions, in that order
    test-keep-attrs-key-last-wins = {
      expr =
        genOf A "metadata"
          [ { r = "k"; } ]
          [
            { r = "m1"; }
            { r = "m2"; }
          ];
      expected = {
        r = "m1";
      };
    };
    test-keep-seed-list = {
      expr = genOf { default = [ "base" ]; } "classes" [ ] [ [ "a" ] ];
      expected = [
        "base"
        "a"
      ];
    };
    test-keep-lazy-element-length = {
      expr = builtins.length (genOf L "classes" [ ] [ [ (throw "lazy-element") ] ]);
      expected = 1;
    };
  };
}
