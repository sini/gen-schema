# `ancestorsForKind` (den-hoag-w523e): a kind's transitive ancestors as kind values, each once, every
# kind before each of its ancestors, ties broken by first reach over `__kindImports`.
#
# The by-name refusals live in `ci/tests-error.nix` (`ancestors-for-kind-refusals`), because `tryEval`
# discards the message; the cells here pin that each of them is catchable.
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption ancestorsForKind kindEq;
  intOpt = genMerge.mkOption { type = genMerge.types.int; };
  tree =
    modules:
    (genMerge.evalModuleTree { } ([ { options.schema = mkSchemaOption { }; } ] ++ modules))
    .config.schema;
  # a kind graph, name -> parent names, each kind declaring its own option `o<name>`
  kinds =
    g:
    tree [
      {
        config.schema = builtins.mapAttrs (n: ps: {
          inherits = ps;
          options.${"o" + n} = intOpt;
        }) g;
      }
    ];
  names = ks: map (k: k.kind) (ancestorsForKind ks);
  mapOf = k: builtins.mapAttrs (_: v: v.kind) k.__kindAncestors;
  catches = v: (builtins.tryEval (builtins.deepSeq v v)).success;

  chain = kinds {
    c = [ "b" ];
    b = [ "a" ];
    a = [ ];
  };
  diamond = kinds {
    d = [
      "b"
      "c"
    ];
    b = [ "a" ];
    c = [ "a" ];
    a = [ ];
  };
  # S3: `a` reaches `d` directly and through `b → c`, so `d` is last although it is a direct parent
  skip = kinds {
    a = [
      "b"
      "d"
    ];
    b = [ "c" ];
    c = [ "d" ];
    d = [ ];
  };
  # S4: `b` and `c` list `d` and `e` in opposite orders, which C3 cannot linearise
  crossed = kinds {
    a = [
      "b"
      "c"
    ];
    b = [
      "d"
      "e"
    ];
    c = [
      "e"
      "d"
    ];
    d = [ ];
    e = [ ];
  };
  # one `p` value from its own tree, reached through `x` (tree 2) and `y` (tree 3)
  p = (tree [ { config.schema.p.options.op = intOpt; } ]).p;
  mid =
    o:
    (tree [
      {
        config.schema.${o} = {
          inherits = [ p ];
          options.${"o" + o} = intOpt;
        };
      }
    ]).${o};
  foreign =
    (tree [
      {
        config.schema.d.inherits = [
          (mid "x")
          (mid "y")
        ];
      }
    ]).d;
  # `inherits = [ "b" f ]` with `f` foreign: composition order puts the foreign value first
  f = (tree [ { config.schema.f.options.of = intOpt; } ]).f;
  nameThenForeign =
    (tree [
      {
        config.schema = {
          b.options.ob = intOpt;
          d.inherits = [
            "b"
            f
          ];
        };
      }
    ]).d;
in
{
  flake.tests.kind-ancestors-in-order = {
    # G1, G2: a chain reads nearest first, root last; the root has none
    test-chain-is-nearest-first = {
      expr = names chain.c;
      expected = [
        "b"
        "a"
      ];
    };
    test-root-has-no-ancestors = {
      expr = names chain.a;
      expected = [ ];
    };

    # G3, G4: the shared ancestor once, after both kinds that inherit it; the incomparable pair in
    # the order the subject composes them
    test-diamond-shared-ancestor-once-and-last = {
      expr = names diamond.d;
      expected = [
        "b"
        "c"
        "a"
      ];
    };
    test-diamond-follows-composition-order = {
      expr =
        names
          (kinds {
            d = [
              "c"
              "b"
            ];
            b = [ "a" ];
            c = [ "a" ];
            a = [ ];
          }).d;
      expected = [
        "c"
        "b"
        "a"
      ];
    };

    # G5: one foreign value reached along two paths is one ancestor
    test-foreign-diamond = {
      expr = names foreign;
      expected = [
        "x"
        "y"
        "p"
      ];
    };

    # S3: a direct parent that is also a further ancestor comes after the path through it; a
    # breadth-first order reads `[ b d c ]` here
    test-direct-parent-after-its-descendants = {
      expr = names skip.a;
      expected = [
        "b"
        "c"
        "d"
      ];
    };

    # S4: answered, never refused, in first-reach order; reverse postorder reads `[ c b e d ]`
    test-crossed-parents-answer-by-first-reach = {
      expr = names crossed.a;
      expected = [
        "b"
        "c"
        "d"
        "e"
      ];
    };

    # C3: the tie key is first reach over `__kindImports`, not the written `inherits` order
    test-tie-key-is-composition-order = {
      expr = {
        written = map (k: k.kind) nameThenForeign.__kindImports;
        ancestors = names nameThenForeign;
      };
      expected = {
        written = [
          "f"
          "b"
        ];
        ancestors = [
          "f"
          "b"
        ];
      };
    };

    # G6: each element is the map's value at its mark
    test-elements-are-the-map-values = {
      expr = builtins.all (v: kindEq v diamond.d.__kindAncestors.${v.__mint.minted}) (
        ancestorsForKind diamond.d
      );
      expected = true;
    };

    # G7: the internal map is unchanged by the accessor (marks pinned as evaluated at d910c2c; the
    # parented ones re-pinned when a parent entered its child's mark by its own, den-hoag-a7c9r: the
    # parentless `a` and `p` are the d910c2c literals still)
    test-internal-map-unchanged = {
      expr = {
        chain = mapOf chain.c;
        diamond = mapOf diamond.d;
        foreign = mapOf foreign;
      };
      expected = {
        chain = {
          "schemakind:42567102824bdbf49c7b15301297c887d43699879136574e87e1d4cbdb02e2f5" = "b";
          "schemakind:ff1105f30503ae8e687e3a3e3982d9d6e6f31cf4fda602114a0754ef03f5b06b" = "a";
        };
        diamond = {
          "schemakind:3797d0918e49b7635ec9e1330dfbe47d63c036788452b4f5941a4d943fed867a" = "c";
          "schemakind:42567102824bdbf49c7b15301297c887d43699879136574e87e1d4cbdb02e2f5" = "b";
          "schemakind:ff1105f30503ae8e687e3a3e3982d9d6e6f31cf4fda602114a0754ef03f5b06b" = "a";
        };
        foreign = {
          "schemakind:193ef77bc6cf63adb8f5105b50810ded9407ed3dc8ee9b6641bdd13905dcd472" = "p";
          "schemakind:550c3a0f225af7a6ce75efa02ef96e23c5e3641d701a2ca6058f9f12cf655cb4" = "x";
          "schemakind:1817fd5676cf7665b77048c5ea92de954b3fd1d57d0da713c10d91def6db5065" = "y";
        };
      };
    };

    # every refusal is a catchable throw, never an abort
    test-refusals-are-catchable = {
      expr = map catches [
        (ancestorsForKind "a")
        (ancestorsForKind { kind = "a"; })
        (ancestorsForKind 3)
        (ancestorsForKind {
          kind = "a";
          __mint.minted = "m0";
        })
        (ancestorsForKind (diamond.d // { __kindImports = [ ]; }))
        (ancestorsForKind (chain.c // { __kindAncestors = { }; }))
      ];
      expected = [
        false
        false
        false
        false
        false
        false
      ];
    };
  };
}
