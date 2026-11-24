# A collection's `default` that is no value of the collection is one definition at `mkOptionDefault`, as
# an option's default is: a default whose top is a condition, a merge or a priority (a module-system
# term, which resolves to no value as an option's default), and a list or attrset default its declared
# type's check refuses. Beside a surviving definition it is unread, so the definitions alone are the
# value; alone, or where it wins, it is refused (`../tests-error.nix`). A list or attrset default that
# is a value of the collection is still the fold's seed.
# Each `bothLaws` cell runs ONE fixture with definitions through both engines: the gen arm is the
# collection on a schema kind, the nixpkgs arm the same field on an `attrsOf (submodule …)` entry
# whose option carries the default, the kind's definitions and the mixin's as definitions of it.
#
# RED before: the default was read beside the definitions, and refused.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  gm = genMerge;
  # `coll` builds the collection from a constructor set; `kind`: the kind's definitions; `mix`: one
  # mixin's contribution, or null for none
  genOf =
    coll: field: kind: mix:
    (gm.evalModuleTree { } (
      [
        {
          options.schema = genSchema.mkSchemaOption (
            {
              collections.${field} = coll gm;
            }
            // (
              if mix == null then
                { }
              else
                {
                  baseModule = { };
                  mixins = [
                    (genSchema.mkMixin { } (_: {
                      ${field} = mix;
                    }))
                  ];
                }
            )
          );
        }
        { config.schema.user = { }; }
      ]
      ++ map (v: { config.schema.user.${field} = v; }) (kind gm)
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
        { config.schema.user = { }; }
      ]
      ++ map (v: { config.schema.user.${field} = v; }) defs;
    }).config.schema.user.${field};
  # `coll` carries the default as `d`; the twin's type is `type`
  bothLaws = type: coll: field: kind: mix: {
    gen = genOf coll field kind mix;
    nixpkgs = twinOf type (coll lib).default field (kind lib ++ (if mix == null then [ ] else [ mix ]));
  };
  same = v: {
    gen = v;
    nixpkgs = v;
  };
  listT = t: t.listOf t.str;
  lazyAttrsT = t: t.lazyAttrsOf t.str;
  neT = t: lib.types.nonEmptyListOf t.str;
  kindB = _: [ [ "b" ] ];
in
{
  flake.tests.collection-default-beside-definition = {
    # the plane's positive control: a plain default stays the seed (`../tests/collection-default-properties.nix`)
    test-plain-seed-kept = {
      expr = genOf (_: { default = [ "base" ]; }) "classes" kindB null;
      expected = [
        "base"
        "b"
      ];
    };
    test-top-list-mkif-true-beside-kind = {
      expr = bothLaws listT (l: { default = l.mkIf true [ "a" ]; }) "classes" kindB null;
      expected = same [ "b" ];
    };
    test-top-list-mkif-false-beside-kind = {
      expr = bothLaws listT (l: { default = l.mkIf false [ "a" ]; }) "classes" kindB null;
      expected = same [ "b" ];
    };
    test-top-list-mkforce-beside-kind = {
      expr = bothLaws listT (l: { default = l.mkForce [ "a" ]; }) "classes" kindB null;
      expected = same [ "b" ];
    };
    test-top-attrs-mkif-true-beside-kind = {
      expr = bothLaws lazyAttrsT (l: { default = l.mkIf true { r = "eu"; }; }) "metadata" (_: [
        { t = "x"; }
      ]) null;
      expected = same { t = "x"; };
    };
    # the same beside a mixin's contribution, on a declared type, and beside a definition that survives a discharged one
    test-top-typed-list-mkmerge-beside-mixin = {
      expr = bothLaws listT (l: {
        type = l.types.listOf l.types.str;
        default = l.mkMerge [
          [ "a" ]
          [ "c" ]
        ];
      }) "classes" (_: [ ]) [ "m" ];
      expected = same [ "m" ];
    };
    test-top-list-mkdefault-beside-surviving-kind = {
      expr = bothLaws listT (l: { default = l.mkDefault [ "a" ]; }) "classes" (l: [
        (l.mkIf false [ "x" ])
        [ "b" ]
      ]) null;
      expected = same [ "b" ];
    };
    # a second `mkOrder` under the one stripped is a term as well
    test-top-double-mkafter-beside-kind = {
      expr = bothLaws listT (l: { default = l.mkAfter (l.mkAfter [ "a" ]); }) "classes" kindB null;
      expected = same [ "b" ];
    };
    # a default its declared type refuses (`[ ]` for `nonEmptyListOf`) beside a surviving definition
    test-type-refused-default-beside-kind = {
      expr = bothLaws neT (_: {
        type = lib.types.nonEmptyListOf lib.types.str;
        default = [ ];
      }) "classes" kindB null;
      expected = same [ "b" ];
    };
    test-type-refused-default-beside-mixin = {
      expr = bothLaws neT (_: {
        type = lib.types.nonEmptyListOf lib.types.str;
        default = [ ];
      }) "classes" (_: [ ]) [ "m" ];
      expected = same [ "m" ];
    };
    # guards: a value default is still the seed beside a definition (one `mkOrder` at its top is stripped,
    # and an element's property resolves inside it), so these keep gen-schema's seed law
    test-top-mkafter-stays-the-seed = {
      expr = genOf (l: { default = l.mkAfter [ "a" ]; }) "classes" kindB null;
      expected = [
        "a"
        "b"
      ];
    };
    test-typed-identity-default-the-type-accepts-stays-the-seed = {
      expr = genOf (l: {
        type = l.types.listOf l.types.str;
        default = [ ];
      }) "classes" (l: [ (l.mkOverride 1600 [ "b" ]) ]) null;
      expected = [ "b" ];
    };
  };
}
