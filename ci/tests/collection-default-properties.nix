# A property inside a collection's `default` is resolved, as nixpkgs resolves one inside an option's
# default: the default is one definition of the collection, resolved alone, and is the fold's seed.
# Each `bothLaws` cell runs ONE fixture with no definition through both engines: the gen arm is the
# collection on a schema kind, the nixpkgs arm the same field on an `attrsOf (submodule …)` entry
# whose option carries the default. The `seed` cells have definitions too, where nixpkgs drops its
# default and gen keeps the seed (gen-schema's seed law, README), so they assert gen's value alone.
# The refusals (a property at the default's top, a discharged or conflicting element) are in
# `../tests-error.nix`.
#
# RED before: the default was the seed unresolved, so a `{ _type = …; }` record reached the value.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  gm = genMerge;
  listT = t: t.listOf t.str;
  lazyAttrsT = t: t.lazyAttrsOf t.str;

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
      ++ map (v: { config.schema.user.${field} = v; }) kind
    )).config.schema.user.${field};
  twinOf =
    type: default: field:
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
      ];
    }).config.schema.user.${field};
  bothLaws = type: field: d: {
    gen = genOf (l: { default = d l; }) field [ ] null;
    nixpkgs = twinOf type (d lib) field;
  };
  same = v: {
    gen = v;
    nixpkgs = v;
  };
in
{
  flake.tests.collection-default-properties = {
    # the positive control: a plain default on both arms
    test-plain = {
      expr = bothLaws listT "classes" (_: [ "a" ]);
      expected = same [ "a" ];
    };

    # ── a property on a default's element or key is resolved ────────────────────────────────────
    test-list-element-mkif-true = {
      expr = bothLaws listT "classes" (l: [ (l.mkIf true "a") ]);
      expected = same [ "a" ];
    };
    test-list-element-mkdefault = {
      expr = bothLaws listT "classes" (l: [ (l.mkDefault "a") ]);
      expected = same [ "a" ];
    };
    test-list-element-mkmerge = {
      expr = bothLaws listT "classes" (l: [ (l.mkMerge [ "a" ]) ]);
      expected = same [ "a" ];
    };
    test-list-element-mkbefore = {
      expr = bothLaws listT "classes" (l: [
        "b"
        (l.mkBefore "a")
      ]);
      expected = same [
        "b"
        "a"
      ];
    };
    test-attrs-key-mkif-true = {
      expr = bothLaws lazyAttrsT "metadata" (l: {
        r = l.mkIf true "eu";
      });
      expected = same { r = "eu"; };
    };
    test-attrs-key-mkmerge = {
      expr = bothLaws lazyAttrsT "metadata" (l: {
        r = l.mkMerge [ "eu" ];
      });
      expected = same { r = "eu"; };
    };
    # one `mkOrder` at the top is stripped, as nixpkgs strips it from an option's default
    test-top-mkafter = {
      expr = bothLaws listT "classes" (l: l.mkAfter [ "a" ]);
      expected = same [ "a" ];
    };

    # ── the seed, resolved alone, beside the definitions (gen-schema's seed law) ────────────────
    test-seed-list-element-mkif-true-with-kind = {
      expr = genOf (l: { default = [ (l.mkIf true "a") ]; }) "classes" [ [ "b" ] ] null;
      expected = [
        "a"
        "b"
      ];
    };
    test-seed-list-element-mkif-true-with-mixin = {
      expr = genOf (l: { default = [ (l.mkIf true "a") ]; }) "classes" [ ] [ "b" ];
      expected = [
        "a"
        "b"
      ];
    };
    # an element's priority ranks nothing against a definition: the seed is resolved alone
    test-seed-list-element-mkforce-kept = {
      expr = genOf (l: { default = [ (l.mkForce "a") ]; }) "classes" [ [ "b" ] ] null;
      expected = [
        "a"
        "b"
      ];
    };
    test-seed-attrs-key-mkforce-loses-to-kind = {
      expr = genOf (l: {
        default = {
          r = l.mkForce "eu";
        };
      }) "metadata" [ { r = "us"; } ] null;
      expected = {
        r = "us";
      };
    };
    test-seed-attrs-key-mkdefault-kept = {
      expr = genOf (l: {
        default = {
          r = l.mkDefault "eu";
        };
      }) "metadata" [ { t = "x"; } ] null;
      expected = {
        r = "eu";
        t = "x";
      };
    };

    # ── guards: unchanged values ────────────────────────────────────────────────────────────────
    test-keep-seed-kind-mkforce = {
      expr = genOf (_: { default = [ "base" ]; }) "classes" [ (gm.mkForce [ "k" ]) ] null;
      expected = [
        "base"
        "k"
      ];
    };
    # an explicit collection whose merge never reads its accumulator never reads its default
    test-keep-explicit-default-unread = {
      expr = genOf (l: {
        default = l.mkIf true 5;
        merge = _: v: v;
      }) "rank" [ 7 ] null;
      expected = 7;
    };
    # a default neither a list nor an attrset, with no `merge`, is served as it is to a kind that
    # never defines the collection; only a definition needs a merge strategy
    test-keep-scalar-default-unread = {
      expr = map (d: genOf (_: { default = d; }) "rank" [ ] null) [
        5
        "x"
        null
      ];
      expected = [
        5
        "x"
        null
      ];
    };
  };
}
