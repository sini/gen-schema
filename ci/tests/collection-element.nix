# A list or attrset collection is a lazy container whose element the module system resolves: a
# property on a list element or an attrset key (`mkIf`, `mkDefault`, `mkForce`, `mkMerge`) is
# resolved when the element is read, as it is under a `listOf`/`attrsOf` option. Each value cell
# runs ONE fixture through both engines and asserts both arms against one literal: the gen arm is
# the collection on a schema kind, the nixpkgs arm the same field on an `attrsOf (submodule …)`
# entry, where a collection sits. The wrong-shape and discharged-element refusals are in
# `../tests-error.nix`.
#
# RED before: the collection was untyped, so the raw `{ _type = …; }` records reached the served
# value, and a `mkForce` on a key lost to a later plain definition.
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
  attrsT = t: t.attrsOf t.str;
  lazyAttrsT = t: t.lazyAttrsOf t.str;

  # `coll` null: a built-in collection (`methods`, `validators`), never redeclared.
  genOf =
    coll: field: defs:
    (gm.evalModuleTree { } (
      [
        {
          options.schema = genSchema.mkSchemaOption (
            if coll == null then { } else { collections.${field} = coll; }
          );
        }
      ]
      ++ map (v: { config.schema.user.${field} = v; }) defs
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
  # `mk` builds the definitions from a constructor set, so neither engine gets its own fixture.
  bothLaws = coll: type: default: field: mk: {
    gen = genOf coll field (mk gm);
    nixpkgs = twinOf type default field (mk lib);
  };
  same = v: {
    gen = v;
    nixpkgs = v;
  };
in
{
  flake.tests.collection-element = {
    # the positive control: plain elements concatenate in definition order on both arms
    test-plain = {
      expr = bothLaws L listT [ ] "classes" (_: [
        [ "a" ]
        [ "b" ]
      ]);
      expected = same [
        "a"
        "b"
      ];
    };

    # ── nixpkgs' value: a property on an element or a key is resolved ──────────────────────────
    test-list-element-mkif-true = {
      expr = bothLaws L listT [ ] "classes" (l: [ [ (l.mkIf true "a") ] ]);
      expected = same [ "a" ];
    };
    test-list-element-mkdefault = {
      expr = bothLaws L listT [ ] "classes" (l: [
        [
          (l.mkDefault "a")
          "b"
        ]
      ]);
      expected = same [
        "a"
        "b"
      ];
    };
    test-attrs-key-mkdefault-last = {
      expr = bothLaws A attrsT { } "metadata" (l: [
        { region = "us"; }
        { region = l.mkDefault "eu"; }
      ]);
      expected = same { region = "us"; };
    };
    test-attrs-key-mkforce-first = {
      expr = bothLaws A attrsT { } "metadata" (l: [
        { region = l.mkForce "eu"; }
        { region = "us"; }
      ]);
      expected = same { region = "eu"; };
    };
    test-attrs-key-mkmerge = {
      expr = bothLaws A attrsT { } "metadata" (l: [ { region = l.mkMerge [ "eu" ]; } ]);
      expected = same { region = "eu"; };
    };

    # ── gen-schema's law, kept: the cells that served before the element was resolved ────────────
    # an attrset key keeps `//`'s last-wins among plain definitions (nixpkgs' `attrsOf str` refuses
    # the conflict)
    test-keep-attrs-key-last-wins = {
      expr = genOf A "metadata" [
        { region = "eu"; }
        { region = "us"; }
      ];
      expected = {
        region = "us";
      };
    };
    # the key's element is opaque: a nested attrset is replaced, never merged, as `//` does
    test-keep-attrs-shallow = {
      expr = genOf A "metadata" [
        { a.x = 1; }
        { a.y = 2; }
      ];
      expected = {
        a.y = 2;
      };
    };
    test-keep-list-all-mkif-false = {
      expr = genOf L "classes" [ (gm.mkIf false [ "a" ]) ];
      expected = [ ];
    };
    test-keep-list-top-mkdefault = {
      expr = genOf L "classes" [ (gm.mkDefault [ "homeManager" ]) ];
      expected = [ "homeManager" ];
    };
    test-keep-attrs-top-mkdefault = {
      expr = genOf A "metadata" [
        { region = "eu"; }
        (gm.mkDefault { tier = "dev"; })
      ];
      expected = {
        region = "eu";
      };
    };
    # the seed is the default, kept beside the definitions, on both shapes
    test-keep-seed-attrs = {
      expr = genOf { default.k = "d"; } "metadata" [ { j = "x"; } ];
      expected = {
        k = "d";
        j = "x";
      };
    };
    # the containers are lazy: an element is resolved on read, so counting never forces one
    # (nixpkgs' `listOf` forces it and refuses)
    test-keep-lazy-element-length = {
      expr = builtins.length (genOf L "classes" [ [ (throw "lazy-element") ] ]);
      expected = 1;
    };
    # as nixpkgs' `lazyAttrsOf` does
    test-keep-lazy-key-names = {
      expr = {
        gen = builtins.attrNames (genOf A "metadata" [ { a = throw "lazy-key"; } ]);
        nixpkgs = builtins.attrNames (twinOf lazyAttrsT { } "metadata" [ { a = throw "lazy-key"; } ]);
      };
      expected = same [ "a" ];
    };

    # ── open residue, pinned at its current value: a discharged element is still counted ────────
    # attrset: `attrNames` counts a key whose definitions all discharge, as nixpkgs' `lazyAttrsOf` does
    test-residue-attrs-discharged-key-counted = {
      expr = {
        gen = builtins.attrNames (
          genOf null "methods" [
            {
              f = gm.mkIf false (x: x);
              g = x: x;
            }
          ]
        );
        nixpkgs = builtins.attrNames (
          twinOf (t: t.lazyAttrsOf t.raw) { } "methods" [
            {
              f = lib.mkIf false (x: x);
              g = x: x;
            }
          ]
        );
      };
      expected = same [
        "f"
        "g"
      ];
    };
    # list: `length` counts a discharged element where nixpkgs' `listOf` drops it. A divergence, no
    # nixpkgs container equals it; the two arms are pinned apart so closing it reds this cell.
    test-residue-list-discharged-element-counted = {
      expr = {
        gen = builtins.length (genOf null "validators" [ [ (gm.mkIf false (_: true)) ] ]);
        nixpkgs = builtins.length (
          twinOf (t: t.listOf t.raw) [ ] "validators" [ [ (lib.mkIf false (_: true)) ] ]
        );
      };
      expected = {
        gen = 1;
        nixpkgs = 0;
      };
    };
  };
}
