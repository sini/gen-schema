# THE TRANSITIVE ANCESTOR MAP, THE CLASS CHECK AND THE MARK-KEYED KIND MODULE (den-hoag-l0y U1) —
# the cells that must stay GREEN.
#
# The by-name refusals live in `ci/tests-error.nix` (`kind-lineage-refusals`), because `tryEval`
# discards the message. Every admitted fixture here is the control of a refused twin there: the same
# topology with the one difference the refusal names removed.
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkSchemaOption kindEq;
  T = genMerge.types;
  intOpt = genMerge.mkOption { type = T.int; };
  openInt =
    d:
    genMerge.mkOption {
      type = T.int;
      default = d;
    };
  treeWith =
    schemaOption: modules:
    (genMerge.evalModuleTree { } ([ { options.schema = schemaOption; } ] ++ modules)).config.schema;
  tree = treeWith (mkSchemaOption { });
  mark = k: k.__mint.minted;
  ancestorCount = k: builtins.length (builtins.attrNames k.__kindAncestors);
  # is `v` the kind `k` or a subkind of it: the lookup the selector operator makes (design §1)
  isA =
    k: v:
    if mark v == mark k then
      kindEq v k
    else
      v.__kindAncestors ? ${mark k} && kindEq v.__kindAncestors.${mark k} k;

  # ── C3 · a depth-2 diamond: `d` spells `x` and `y`, each spelling a `p` from its own tree ─────────
  pOf = d: (tree [ { config.schema.p.options.base = openInt d; } ]).p;
  mid =
    p: o:
    (tree [
      {
        config.schema.${o} = {
          imports = [ p ];
          options.${o} = intOpt;
        };
      }
    ]).${o};
  diamondOf =
    a: b:
    (tree [
      {
        config.schema.d.imports = [
          a
          b
        ];
      }
    ]).d;
  p80 = pOf 80;
  # `p` reached twice along two paths, one kind value: admitted
  dOk = diamondOf (mid p80 "x") (mid p80 "y");

  # ── C2 · the class rule: tree A's `base` under keySemantics `{ alpha }`, a subkind in tree B ──────
  ksBase = {
    alpha.category = "class";
  };
  baseA =
    (treeWith (mkSchemaOption { keySemantics = ksBase; }) [
      { config.schema.base.options.b = intOpt; }
    ]).base;
  subUnder =
    ks:
    (treeWith (mkSchemaOption { keySemantics = ks; }) [
      {
        config.schema.sub = {
          imports = [ baseA ];
          options.extra = intOpt;
        };
      }
    ]).sub;

  # ── K2 · one generator in two trees differing only in an option type ─────────────────────────────
  gen = t: {
    config.schema.root.options.r = intOpt;
    config.schema.base = {
      inherits = [ "root" ];
      options.b = genMerge.mkOption { type = t; };
    };
  };
  baseInt = (tree [ (gen T.int) ]).base;
  k2Tree = tree [
    (gen T.str)
    {
      config.schema.sub = {
        imports = [ baseInt ];
        options.s = intOpt;
      };
    }
    {
      config.schema.x = {
        inherits = [ "base" ];
        options.xx = intOpt;
      };
    }
    {
      config.schema.d.inherits = [
        "sub"
        "x"
      ];
    }
  ];

  # ── K3 · the `evalSchema` arm publishes the parent the caller reads ──────────────────────────────
  esOpen = evalSchema { } [
    { config.schema.base.options.b = openInt 0; }
    {
      config.schema.sub = {
        inherits = [ "base" ];
        options.extra = intOpt;
      };
    }
  ];
  esDiamond = evalSchema { } [
    { config.schema.base.options.b = openInt 0; }
    {
      config.schema.x = {
        inherits = [ "base" ];
        options.xx = intOpt;
      };
    }
    {
      config.schema.d = {
        inherits = [
          "base"
          "x"
        ];
        options.dd = intOpt;
      };
    }
  ];
in
{
  flake.tests.kind-ancestors = {
    # A parentless kind publishes an empty map; a child publishes its transitive ancestors as kind
    # VALUES keyed by mark, read by `kindEq` as the very kinds it composed.
    test-map-is-keyed-by-mark-and-holds-the-kind-values = {
      expr =
        let
          t = tree [
            { config.schema.root.options.r = intOpt; }
            {
              config.schema.mid = {
                inherits = [ "root" ];
                options.m = intOpt;
              };
            }
            {
              config.schema.leaf = {
                inherits = [ "mid" ];
                options.l = intOpt;
              };
            }
          ];
        in
        {
          root = t.root.__kindAncestors;
          leafHoldsRootAndMid =
            builtins.attrNames t.leaf.__kindAncestors == builtins.sort (a: b: a < b) [
              (mark t.root)
              (mark t.mid)
            ];
          leafRootEntryIsRoot = kindEq t.leaf.__kindAncestors.${mark t.root} t.root;
          leafIsARoot = isA t.root t.leaf;
          rootIsALeaf = isA t.leaf t.root;
        };
      expected = {
        root = { };
        leafHoldsRootAndMid = true;
        leafRootEntryIsRoot = true;
        leafIsARoot = true;
        rootIsALeaf = false;
      };
    };

    # C3's control: one `p` reached along two paths is one ancestor, composed once.
    test-diamond-over-one-kind-is-admitted = {
      expr = {
        ancestors = ancestorCount dOk;
        default = dOk.options.base.default;
      };
      expected = {
        ancestors = 3;
        default = 80;
      };
    };

    # C2's control and F14-5: a subkind whose keySemantics holds the base's keys, with the same
    # category, plus its own, is admitted; the base's class reads the same on it.
    test-subkind-holding-every-base-class-is-admitted = {
      expr =
        let
          sub = subUnder (ksBase // { beta.category = "class"; });
        in
        {
          options = builtins.attrNames sub.options;
          alpha = sub.keySemantics.alpha.category;
          isABase = isA baseA sub;
        };
      expected = {
        options = [
          "b"
          "extra"
        ];
        alpha = "class";
        isABase = true;
      };
    };

    # K2's map half: the two `base`s carry equal witnesses and different marks, so they are two kinds
    # and the map holds both (sub, tree A's base, its root, x, the local base; the two roots share a
    # mark and are one), with no collision. Their composition is gen-merge's to refuse
    # (`kind-lineage-refusals.test-differing-mark-parents-are-not-dropped-by-the-module-key`).
    test-differing-mark-parents-are-two-ancestors = {
      expr = {
        witnessEq = baseInt.__kindWitness == k2Tree.base.__kindWitness;
        markEq = mark baseInt == mark k2Tree.base;
        ancestors = ancestorCount k2Tree.d;
      };
      expected = {
        witnessEq = true;
        markEq = false;
        ancestors = 5;
      };
    };

    # K3a: `evalSchema` publishes the parent the caller reads (`tree.${p}`), so `kindEq` decides the
    # published parent `true` against it even where an option carries a default, and the lookup holds.
    test-operator-over-evalSchema-with-a-default = {
      expr = {
        imports = builtins.length esOpen.sub.__kindImports;
        publishedIsRead =
          esOpen.sub.__kindImports != [ ] && kindEq (builtins.head esOpen.sub.__kindImports) esOpen.base;
        isABase = isA esOpen.base esOpen.sub;
      };
      expected = {
        imports = 1;
        publishedIsRead = true;
        isABase = true;
      };
    };

    # K3b: a mixed-depth diamond under `evalSchema` (`d` inherits `base` and `x`, `x` inherits
    # `base`) is one `base`, admitted, with the default it declares.
    test-mixed-depth-evalSchema-diamond-is-admitted = {
      expr = {
        options = builtins.attrNames esDiamond.d.options;
        default = esDiamond.d.options.b.default;
        ancestors = ancestorCount esDiamond.d;
        isABase = isA esDiamond.base esDiamond.d;
      };
      expected = {
        options = [
          "b"
          "dd"
          "xx"
        ];
        default = 0;
        ancestors = 2;
        isABase = true;
      };
    };
  };
}
