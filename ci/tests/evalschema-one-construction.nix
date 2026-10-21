# `evalSchema` EVALUATES THE KIND TREE ONCE, with each declared parent injected from that same
# evaluation, so a kind is one construction for every reader (ADR-0012: a module however often
# imported is one node). Each cell reads how often a kind composes, off a list option every kind
# appends its own name to (`trail`): a second construction of `base` under one key is refused by
# name, and a second one under no key (a parentless `base`) reads `2`.
#
# The readers: a mixed-depth diamond's child, the tree returned mounted beside a child, both
# deprecated spellings, and a SHALLOWER kind holding a deeper kind of its own tree (an option default,
# an instance type), whose closure must read the same tree its caller does.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema kindEq mkInstanceType;
  T = genMerge.types;
  trailOpt = genMerge.mkOption { type = T.listOf T.str; };
  openInt =
    d:
    genMerge.mkOption {
      type = T.int;
      default = d;
    };
  compose = ks: (genMerge.evalModuleTree { } ks).config;
  count = n: l: builtins.length (builtins.filter (x: x == n) l);
  counts =
    names: l:
    builtins.listToAttrs (
      map (n: {
        name = n;
        value = count n l;
      }) names
    );
  # the subject's trail with its own entry dropped
  trailOf = k: builtins.filter (n: n != k.kind) (compose [ k ]).trail;
  root = {
    config.schema.r.config = { };
  };
  # `base` declares the list option and the default; parented puts it under the root `r`
  baseDecl =
    parented:
    {
      options.trail = trailOpt;
      options.b = openInt 0;
      config.trail = [ "base" ];
    }
    // (if parented then { inherits = [ "r" ]; } else { });

  # the mixed-depth diamond: d -> [ base x ], x -> base
  mixedDepth =
    parented:
    evalSchema { } [
      root
      { config.schema.base = baseDecl parented; }
      {
        config.schema.x = {
          inherits = [ "base" ];
          config.trail = [ "x" ];
        };
      }
      {
        config.schema.d = {
          inherits = [
            "base"
            "x"
          ];
          config.trail = [ "d" ];
        };
      }
    ];
  mdParented = mixedDepth true;
  mdParentless = mixedDepth false;
  diamondRead = t: {
    default = t.d.options.b.default;
    trail = counts [ "base" "x" ] (trailOf t.d);
  };

  # depth-3 mixed: e -> [ base y x ], y -> x, x -> base
  mixedDepth3 =
    parented:
    evalSchema { } [
      root
      { config.schema.base = baseDecl parented; }
      {
        config.schema.x = {
          inherits = [ "base" ];
          config.trail = [ "x" ];
        };
      }
      {
        config.schema.y = {
          inherits = [ "x" ];
          config.trail = [ "y" ];
        };
      }
      {
        config.schema.e = {
          inherits = [
            "base"
            "y"
            "x"
          ];
          config.trail = [ "e" ];
        };
      }
    ];

  # `x` reaches `base` through a VALUE read off the tree being declared, in either spelling; `d`
  # declares both by name
  spelledBy =
    spelling:
    evalSchema { } [
      root
      { config.schema.base = baseDecl true; }
      (
        { config, ... }:
        {
          config.schema.x = {
            ${spelling} = [ config.schema.base ];
            config.trail = [ "x" ];
          };
        }
      )
      {
        config.schema.d = {
          inherits = [
            "base"
            "x"
          ];
          config.trail = [ "d" ];
        };
      }
    ];
  spelledRead = t: {
    x = count "base" (compose [ t.x ]).trail;
    d = count "base" (compose [ t.d ]).trail;
    beside =
      count "base"
        (compose [
          t.d
          t.base
        ]).trail;
  };

  # two parentless kinds of one shape and different names
  twoKinds = evalSchema { } [
    { config.schema.base = baseDecl false; }
    { config.schema.base2.config.trail = [ "base2" ]; }
    {
      config.schema.x = {
        inherits = [
          "base"
          "base2"
        ];
        config.trail = [ "x" ];
      };
    }
    {
      config.schema.d = {
        inherits = [
          "base"
          "x"
          "base2"
        ];
        config.trail = [ "d" ];
      };
    }
  ];

  # another tree's `base`, a different declaration of the name (it adds `fbase`), inherited by value
  foreignBase = (evalSchema { } [ { config.schema.base.config.trail = [ "fbase" ]; } ]).base;
  withForeign = evalSchema { } [
    root
    { config.schema.base = baseDecl false; }
    {
      config.schema.x = {
        inherits = [ "base" ];
        config.trail = [ "x" ];
      };
    }
    {
      config.schema.d = {
        inherits = [
          "base"
          "x"
          foreignBase
        ];
        config.trail = [ "d" ];
      };
    }
  ];

  # a depth-0 `host` whose option default is the depth-2 `user` of its own tree
  crossRead =
    parented:
    evalSchema { } [
      root
      {
        config.schema.base = {
          options.trail = trailOpt;
          config.trail = [ "base" ];
        }
        // (if parented then { inherits = [ "r" ]; } else { });
      }
      {
        config.schema.user = {
          inherits = [ "base" ];
          config.trail = [ "user" ];
        };
      }
      (
        { config, ... }:
        {
          config.schema.host.options.owner = genMerge.mkOption {
            type = T.raw;
            default = config.schema.user;
          };
        }
      )
    ];
  crossReadOf =
    t:
    let
      u = t.host.options.owner.default;
    in
    {
      kindEq = kindEq u t.user;
      same = u == t.user;
      beside =
        count "base"
          (compose [
            t.user
            u
          ]).trail;
    };

  # the registry form: `host`'s option is typed by instances of its tree's `user`
  instanceRead = evalSchema { } [
    root
    { config.schema.base = baseDecl true; }
    {
      config.schema.user = {
        inherits = [ "base" ];
        config.trail = [ "user" ];
      };
    }
    (
      { config, ... }:
      {
        config.schema.host = {
          options.users = genMerge.mkOption {
            type = T.attrsOf (mkInstanceType { } config.schema.user);
            default = { };
          };
          config.users.alice = { };
        };
      }
    )
  ];
in
{
  flake.tests.evalschema-one-construction = {
    # G1: `d` composes `base` once, with the default `base` declares.
    test-mixed-depth-diamond-parented-composes-once = {
      expr = diamondRead mdParented;
      expected = {
        default = 0;
        trail = {
          base = 1;
          x = 1;
        };
      };
    };

    # G2: the same with a parentless `base` is admitted. The `2` is a parentless kind's own double
    # import, which no key refuses; it is not a second construction.
    test-mixed-depth-diamond-parentless-is-admitted = {
      expr = diamondRead mdParentless;
      expected = {
        default = 0;
        trail = {
          base = 2;
          x = 1;
        };
      };
    };

    # G3: depth 3, every kind once under a parented `base`; admitted under a parentless one.
    test-mixed-depth-3-composes-once = {
      expr = {
        parented = counts [ "base" "x" "y" ] (trailOf (mixedDepth3 true).e);
        parentless = counts [ "base" "x" "y" ] (trailOf (mixedDepth3 false).e);
      };
      expected = {
        parented = {
          base = 1;
          x = 1;
          y = 1;
        };
        parentless = {
          base = 2;
          x = 1;
          y = 1;
        };
      };
    };

    # G4: the diamond's child mounted in nixpkgs `lib.evalModules` composes `base` once too.
    test-mixed-depth-diamond-in-nixpkgs-composes-once = {
      expr = counts [ "base" "x" ] (
        builtins.filter (n: n != "d") (lib.evalModules { modules = [ mdParented.d ]; }).config.trail
      );
      expected = {
        base = 1;
        x = 1;
      };
    };

    # G5: the tree returned, a child mounted beside its parent, holds one `base`.
    test-the-tree-returned-is-the-tree-injected = {
      expr =
        counts [ "base" "x" ]
          (compose [
            mdParented.x
            mdParented.base
          ]).trail;
      expected = {
        base = 1;
        x = 1;
      };
    };

    # G6: the deprecated spelling `imports = [ config.schema.base ]` reads the one `base`.
    test-the-imports-spelling-reads-the-one-construction = {
      expr = spelledRead (spelledBy "imports");
      expected = {
        x = 1;
        d = 1;
        beside = 1;
      };
    };

    # G6b: the value spelling `inherits = [ config.schema.base ]` reads the one `base`.
    test-the-value-spelled-inherits-reads-the-one-construction = {
      expr = spelledRead (spelledBy "inherits");
      expected = {
        x = 1;
        d = 1;
        beside = 1;
      };
    };

    # G7: two kinds of one shape stay two kinds.
    test-two-same-shape-kinds-stay-two = {
      expr = {
        names = map (k: twoKinds.${k}.kind) [
          "base"
          "base2"
        ];
        trail = counts [ "base" "base2" "x" ] (trailOf twoKinds.d);
      };
      expected = {
        names = [
          "base"
          "base2"
        ];
        trail = {
          base = 2;
          base2 = 2;
          x = 1;
        };
      };
    };

    # G8: another tree's same-named kind, inherited by value, stays distinct from the tree's own.
    test-a-foreign-same-name-kind-stays-distinct = {
      expr = counts [ "base" "fbase" "x" ] (trailOf withForeign.d);
      expected = {
        base = 2;
        fbase = 1;
        x = 1;
      };
    };

    # X1: a depth-0 kind's option default holding its tree's depth-2 kind IS that kind.
    test-a-shallow-kind-holds-the-deeper-kind-of-its-tree = {
      expr = crossReadOf (crossRead true);
      expected = {
        kindEq = true;
        same = true;
        beside = 1;
      };
    };

    # X2: X1 with a parentless `base`.
    test-a-shallow-kind-holds-the-deeper-kind-parentless = {
      expr = crossReadOf (crossRead false);
      expected = {
        kindEq = true;
        same = true;
        beside = 1;
      };
    };

    # X3: the registry form, one instance.
    test-an-instance-type-over-a-deeper-kind-composes-once = {
      expr =
        let
          h = compose [ instanceRead.host ];
        in
        {
          inherit (h.users.alice) b;
          trail = counts [ "base" "user" ] h.users.alice.trail;
        };
      expected = {
        b = 0;
        trail = {
          base = 1;
          user = 1;
        };
      };
    };

    # X4: the same option declared again over the tree's `user` merges with `host`'s own: the two
    # instance types are over one construction.
    test-an-instance-type-over-the-trees-kind-merges-with-the-shallow-kinds = {
      expr =
        (compose [
          instanceRead.host
          {
            options.users = genMerge.mkOption {
              type = T.attrsOf (mkInstanceType { } instanceRead.user);
            };
          }
        ]).users.alice.b;
      expected = 0;
    };
  };
}
