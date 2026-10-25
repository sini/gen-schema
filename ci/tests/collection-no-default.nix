# A collection declaring neither a `default` nor a `merge` is what an option declaring no type and no
# default is: its definitions fold as an untyped option's do (one definition is its own value), and,
# read where no definition of it survives, it is refused by name (`../tests-error.nix`). A collection
# declaring a `merge` and no `default` has no seed: its definitions fold while the `merge` does not
# read the seed. Each `bothLaws` cell runs one fixture through both engines: the gen arm is the
# collection on a schema kind, the nixpkgs arm the same field, declared `mkOption { }`, on an
# `attrsOf (submodule …)` entry, which is where a collection sits. On that entry nixpkgs folds an
# option's definitions in the order they are written, as every list collection does here; a top-level
# option would see them last module first, because each submodule level reverses its module list.
# The twin is faithful because it puts one module evaluation above the field, as gen's `schema`
# submodule does: a kind is never evaluated as a module, so no second level reverses the list.
#
# RED before: every cell but the guard aborted, uncatchably, on `attribute 'default' missing`.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  gm = genMerge;
  # `coll`: the collection's declaration; `kind`: the kind's definitions; `mix`: one mixin's
  # contribution, or null for none
  userOf =
    coll: field: kind: mix:
    (gm.evalModuleTree { } (
      [
        {
          options.schema = genSchema.mkSchemaOption (
            {
              collections.${field} = coll;
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
    )).config.schema.user;
  twinOf =
    field: kind:
    (lib.evalModules {
      modules = [
        {
          options.schema = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options.${field} = lib.mkOption { };
              }
            );
          };
        }
        { config.schema.user = { }; }
      ]
      ++ map (v: { config.schema.user.${field} = v; }) kind;
    }).config.schema.user.${field};
  bothLaws = field: kind: {
    gen = (userOf { } field kind null).${field};
    nixpkgs = twinOf field kind;
  };
  same = v: {
    gen = v;
    nixpkgs = v;
  };
in
{
  flake.tests.collection-no-default = {
    test-one-definition-is-its-value = {
      expr = bothLaws "rank" [ 7 ];
      expected = same 7;
    };
    test-one-list-definition-is-its-value = {
      expr = bothLaws "rank" [ [ "a" ] ];
      expected = same [ "a" ];
    };
    test-attrset-definitions-merge = {
      expr = bothLaws "rank" [
        { a = 1; }
        { b = 2; }
      ];
      expected = same {
        a = 1;
        b = 2;
      };
    };
    test-equal-definitions-are-one-value = {
      expr = bothLaws "rank" [
        7
        7
      ];
      expected = same 7;
    };
    test-list-definitions-concatenate-in-definition-order = {
      expr = bothLaws "rank" [
        [ "a" ]
        [ "b" ]
      ];
      expected = same [
        "a"
        "b"
      ];
    };
    test-string-definitions-concatenate = {
      expr = bothLaws "rank" [
        "a"
        "b"
      ];
      expected = same "ab";
    };
    test-bool-definitions-or = {
      expr = bothLaws "rank" [
        true
        false
      ];
      expected = same true;
    };
    # a mixin's contribution is one more definition after the kind's own, as `collection-mixin.nix`
    # models it on the nixpkgs arm
    test-mixin-contribution-follows-the-kind = {
      expr = {
        gen = (userOf { } "rank" [ [ "k" ] ] [ "m" ]).rank;
        nixpkgs = twinOf "rank" [
          [ "k" ]
          [ "m" ]
        ];
      };
      expected = same [
        "k"
        "m"
      ];
    };
    # an undefined collection enters the kind's identity as undefined, so the mark is minted
    test-undefined-collection-mints-the-kind = {
      expr = builtins.isString (userOf { } "rank" [ ] null).__mint.minted;
      expected = true;
    };
    # gen-merge's stated untyped law, not a twin equality: equal paths (and nulls, floats, an int
    # beside an equal float) are one value, where nixpkgs refuses them
    test-equal-paths-are-one-value = {
      expr = {
        gen = (userOf { } "rank" [ /a /a ] null).rank;
        nixpkgs =
          let
            v = twinOf "rank" [
              /a
              /a
            ];
          in
          (builtins.tryEval (builtins.deepSeq v v)).success;
      };
      expected = {
        gen = /a;
        nixpkgs = false;
      };
    };
    # guard: a `merge` that never reads its accumulator never reads the missing seed
    test-keep-merge-without-default-unread = {
      expr = (userOf { merge = _: v: v; } "rank" [ 7 ] null).rank;
      expected = 7;
    };
  };
}
