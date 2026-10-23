# A collection's definitions carry module-system properties (`mkDefault`, `mkForce`, `mkOverride`,
# `mkBefore`/`mkAfter`/`mkOrder`, `mkIf`, `mkMerge`) at their top level, and the module system
# resolves them before the strategy folds. Every cell runs ONE fixture through both engines: the gen
# arm is the collection on a schema kind, the nixpkgs arm is the same field declared as an option on
# an `attrsOf (submodule …)` entry, which is where a collection sits. Both arms are asserted against
# one literal, so an upstream move reds on the property rather than passing on a stale copy.
#
# RED before: the raw `{ _type = …; }` records reached the fold, so a list collection aborted
# (`expected a list but found a set`, uncatchable), an attrs collection splatted the record's keys
# into its value, and an explicit `merge` folded the record as a value.
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
  Last = {
    default = null;
    merge = _acc: val: val;
  };
  listT = t: t.listOf t.str;
  attrsT = t: t.attrsOf t.str;

  # `coll` null: a built-in collection (`inherits`, `parent`), never redeclared.
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
  flake.tests.collection-priority = {
    # the positive control: plain definitions concatenate in definition order on both arms
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
    test-list-mkdefault-alone = {
      expr = bothLaws L listT [ ] "classes" (l: [ (l.mkDefault [ "homeManager" ]) ]);
      expected = same [ "homeManager" ];
    };
    test-list-plain-beats-mkdefault = {
      expr = bothLaws L listT [ ] "classes" (l: [
        [ "a" ]
        (l.mkDefault [ "b" ])
      ]);
      expected = same [ "a" ];
    };
    test-list-mkforce = {
      expr = bothLaws L listT [ ] "classes" (l: [
        [ "a" ]
        (l.mkForce [ "b" ])
      ]);
      expected = same [ "b" ];
    };
    test-list-mkoverride-900-loses = {
      expr = bothLaws L listT [ ] "classes" (l: [
        [ "a" ]
        (l.mkOverride 900 [ "b" ])
      ]);
      expected = same [ "a" ];
    };
    test-list-mkoverride-10-wins = {
      expr = bothLaws L listT [ ] "classes" (l: [
        [ "a" ]
        (l.mkOverride 10 [ "b" ])
      ]);
      expected = same [ "b" ];
    };
    test-list-mkbefore-mkafter = {
      expr = bothLaws L listT [ ] "classes" (l: [
        [ "b" ]
        (l.mkAfter [ "c" ])
        (l.mkBefore [ "a" ])
      ]);
      expected = same [
        "a"
        "b"
        "c"
      ];
    };
    test-list-mkorder = {
      expr = bothLaws L listT [ ] "classes" (l: [
        [ "y" ]
        (l.mkOrder 600 [ "x" ])
      ]);
      expected = same [
        "x"
        "y"
      ];
    };
    test-list-mkif-false = {
      expr = bothLaws L listT [ ] "classes" (l: [
        [ "b" ]
        (l.mkIf false [ "a" ])
      ]);
      expected = same [ "b" ];
    };
    # every definition discharged: the collection answers its default
    test-list-all-mkif-false = {
      expr = bothLaws L listT [ ] "classes" (l: [ (l.mkIf false [ "a" ]) ]);
      expected = same [ ];
    };
    test-list-mkmerge = {
      expr = bothLaws L listT [ ] "classes" (l: [
        (l.mkMerge [
          [ "a" ]
          [ "b" ]
        ])
      ]);
      expected = same [
        "a"
        "b"
      ];
    };
    test-attrs-mkdefault = {
      expr = bothLaws A attrsT { } "metadata" (l: [
        { region = "eu"; }
        (l.mkDefault { tier = "dev"; })
      ]);
      expected = same { region = "eu"; };
    };
    test-attrs-mkforce = {
      expr = bothLaws A attrsT { } "metadata" (l: [
        { region = "eu"; }
        (l.mkForce { tier = "prod"; })
      ]);
      expected = same { tier = "prod"; };
    };
    test-explicit-merge-mkforce-first = {
      expr = bothLaws Last (t: t.nullOr t.int) null "rank" (l: [
        (l.mkForce 50)
        10
      ]);
      expected = same 50;
    };
    test-builtin-inherits-mkdefault = {
      expr = bothLaws null listT [ ] "inherits" (l: [ (l.mkDefault [ ]) ]);
      expected = same [ ];
    };
    test-builtin-parent-mkdefault = {
      expr = bothLaws null (t: t.nullOr t.str) null "parent" (l: [ (l.mkDefault "host") ]);
      expected = same "host";
    };
    test-builtin-parent-mkforce-over-plain = {
      expr = bothLaws null (t: t.nullOr t.str) null "parent" (l: [
        "a"
        (l.mkForce "b")
      ]);
      expected = same "b";
    };
    # gen-schema's seed law, NOT the twin: a collection's `default` is the fold's seed and is kept
    # beside its definitions, where nixpkgs drops an option default once any definition exists
    # (it answers `[ "a" ]`). Pinned at its current value so this landing provably moves no seed.
    test-seed-kept-beside-definitions = {
      expr = genOf { default = [ "base" ]; } "classes" [ [ "a" ] ];
      expected = [
        "base"
        "a"
      ];
    };
  };
}
