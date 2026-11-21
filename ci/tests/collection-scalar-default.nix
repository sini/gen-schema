# A collection declaring a `default` that is neither a list nor an attrset, and neither a `type` nor a
# `merge`, is an option declaring that default and no type: the default is one definition at
# `mkOptionDefault`, so a definition outranks it and it answers where every definition discharges, and
# the definitions fold untyped, as an option's do. Each `bothLaws` cell runs one fixture through both
# engines: the gen arm is the collection on a schema kind, the nixpkgs arm `mkOption { default; }` on an
# `attrsOf (submodule …)` entry, one module evaluation above the field (`collection-no-default.nix`).
# The typed half is `collection-declared-type.nix`'s; an explicit `merge` keeps its fold
# (`collection-default-properties.nix`).
#
# RED before: every cell with a definition was refused, "no merge strategy".
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  gm = genMerge;
  userOf =
    coll: kind: mix:
    (gm.evalModuleTree { } (
      [
        {
          options.schema = genSchema.mkSchemaOption (
            {
              collections.rank = coll;
            }
            // (
              if mix == null then
                { }
              else
                {
                  baseModule = { };
                  mixins = [
                    (genSchema.mkMixin { } (_: {
                      rank = mix;
                    }))
                  ];
                }
            )
          );
        }
        { config.schema.user = { }; }
      ]
      ++ map (v: { config.schema.user.rank = v; }) kind
    )).config.schema.user.rank;
  twinOf =
    default: kind:
    (lib.evalModules {
      modules = [
        {
          options.schema = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule { options.rank = lib.mkOption { inherit default; }; }
            );
          };
        }
        { config.schema.user = { }; }
      ]
      ++ map (v: { config.schema.user.rank = v; }) kind;
    }).config.schema.user.rank;
  # `mk` builds the definitions from an engine's property constructors
  bothLaws = default: mk: {
    gen = userOf { inherit default; } (mk gm) null;
    nixpkgs = twinOf default (mk lib);
  };
  same = v: {
    gen = v;
    nixpkgs = v;
  };
  # gen-merge's stated untyped law (`mergeUntyped`'s agreement), where nixpkgs refuses: the served
  # value and its `typeOf`, since `1 == 1.0` in Nix
  agreement = defs: {
    gen =
      let
        v = userOf { default = 5; } defs null;
      in
      {
        value = v;
        type = builtins.typeOf v;
      };
    nixpkgs = (builtins.tryEval (twinOf 5 defs)).success;
  };
in
{
  flake.tests.collection-scalar-default = {
    # the former refusal `test-scalar-default-definition-has-no-merge-strategy` (tests-error)
    test-definition-outranks-the-default = {
      expr = bothLaws 5 (_: [ 7 ]);
      expected = same 7;
    };
    # the former `collection-no-merge.test-int-default-throws`: a kind defining it is served
    test-int-default-defined = {
      expr = bothLaws 0 (_: [ 10 ]);
      expected = same 10;
    };
    test-mkdefault-definition-outranks-the-default = {
      expr = bothLaws 5 (l: [ (l.mkDefault 7) ]);
      expected = same 7;
    };
    test-discharged-definitions-answer-the-default = {
      expr = bothLaws 5 (l: [ (l.mkIf false 7) ]);
      expected = same 5;
    };
    test-equal-definitions-are-one-value = {
      expr = bothLaws 5 (_: [
        7
        7
      ]);
      expected = same 7;
    };
    test-bool-definitions-or = {
      expr = bothLaws false (_: [
        true
        false
      ]);
      expected = same true;
    };
    # strings and lists concatenate in the order the definitions are written, N = 2 and 3
    test-string-definitions-concatenate = {
      expr = bothLaws "" (_: [
        "x"
        "y"
      ]);
      expected = same "xy";
    };
    test-three-string-definitions-concatenate = {
      expr = bothLaws null (_: [
        "x"
        "y"
        "z"
      ]);
      expected = same "xyz";
    };
    test-list-definitions-concatenate = {
      expr = bothLaws null (_: [
        [ "x" ]
        [ "y" ]
      ]);
      expected = same [
        "x"
        "y"
      ];
    };
    test-order-properties-resolve-first = {
      expr = bothLaws "" (l: [
        (l.mkOrder 1600 "x")
        (l.mkOrder 400 "y")
        "z"
      ]);
      expected = same "yzx";
    };
    test-mkafter-resolves-first = {
      expr = bothLaws "" (l: [
        (l.mkAfter "x")
        "y"
      ]);
      expected = same "yx";
    };
    # a mixin's contribution is one more definition after the kind's own
    test-mixin-contribution-follows-the-kind = {
      expr = {
        gen = userOf { default = ""; } [ "k" ] "m";
        nixpkgs = twinOf "" [
          "k"
          "m"
        ];
      };
      expected = same "km";
    };
    # gen-merge's stated untyped law, not a twin equality: equal nulls (and floats, and an int beside
    # an equal float) are one value, where nixpkgs refuses them (gen-merge README, `mergeUntyped`)
    test-equal-nulls-are-one-value = {
      expr = {
        gen = userOf { default = 5; } [
          null
          null
        ] null;
        nixpkgs =
          (builtins.tryEval (
            twinOf 5 [
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
    # vacuous: an untyped collection declares no check (`types.unspecified.check` accepts every value).
    test-equal-floats-are-one-value = {
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
    test-int-beside-float-is-the-int = {
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
    test-float-beside-int-is-the-float = {
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
    # a kind that never defines it is still served the default as written
    test-undefined-served = {
      expr = userOf { default = 5; } [ ] null;
      expected = 5;
    };
  };
}
