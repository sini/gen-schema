# ONE CONSTRUCTION REACHED ON N PATHS IS ONE MODULE, IN GEN AND IN NIXPKGS, IN EVERY ORDER. Every kind
# is keyed by its declaration node (gen) and by its reference key (the functor result, nixpkgs), so a
# shared ancestor composes once in both engines. Each cell evaluates its shape in gen-merge's
# `evalModuleTree` and in nixpkgs' `lib.evalModules`, over every order of what varies, and pins the
# set of outcomes to ONE `{ gen = v; nixpkgs = v; }` with `v` derived by hand: gen = nixpkgs alone
# passes where both refuse (a refusal raised by the schema's own construction reaches both columns),
# so the value is pinned too. `orders` pins the evaluated count, so a cell that evaluates nothing
# fails. A read is the SORTED trail, a string, or "REFUSED".
#
#   sameValue          : the kind value imported N times beside `t`, every position of `t` (N + 1)
#   diamond / guardedG : `d.inherits` = every permutation of [ t base m1 .. m(N-1) ] ((N + 1)!)
#   diamond2 / guardedG2 : `d.inherits` = every permutation of [ t t1 .. tN ], each `t*` inheriting
#                        `m1 .. mN` in `d`'s relative order of the `t*` ((N + 1)!)
#   removal            : the diamond, `disabledModules` naming the key nixpkgs sees
#   guarded*           : `g`, an option `base` declares with a default (the both-carry guard's field)
#
# THE GUARDED KIND (`key-guarded-kind-dedup`): the schema keeps `collections.excludes` in identity and
# `base` defines it, so a one-node pair is decided by the construction's token; the control declares
# the collection `identity = false` (the seal path).
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  T = genMerge.types;
  trailOpt = genMerge.mkOption { type = T.listOf T.str; };
  str =
    d:
    genMerge.mkOption {
      type = T.str;
      default = d;
    };
  listO = genMerge.mkOption { type = T.listOf T.str; };
  names = p: n: map (i: "${p}${toString i}") (lib.range 1 n);
  perms =
    l:
    if l == [ ] then
      [ [ ] ]
    else
      lib.concatMap (
        i:
        map (rest: [ (builtins.elemAt l i) ] ++ rest) (
          perms (lib.sublist 0 i l ++ lib.sublist (i + 1) (builtins.length l) l)
        )
      ) (lib.range 0 (builtins.length l - 1));
  try =
    v:
    let
      r = builtins.tryEval (builtins.deepSeq v v);
    in
    if r.success then r.value else "REFUSED";
  run =
    engine: read: ms:
    let
      c =
        if engine == "gen" then
          (genMerge.evalModuleTree { } ms).config
        else
          (lib.evalModules { modules = ms; }).config;
      v = try (c.${read} or "ABSENT");
    in
    if builtins.isList v then builtins.sort builtins.lessThan v else v;
  both = read: ms: {
    gen = run "gen" read ms;
    nixpkgs = run "nixpkgs" read ms;
  };
  over = rows: {
    orders = builtins.length rows;
    outcomes = lib.unique rows;
  };
  pinned = orders: v: {
    inherit orders;
    outcomes = [
      {
        gen = v;
        nixpkgs = v;
      }
    ];
  };
  fact = n: if n <= 1 then 1 else n * fact (n - 1);

  # the shared-ancestor tree; `ord` is a permutation of the names `d` inherits
  build =
    parented: guarded: levels: n: ord:
    (genMerge.evalModuleTree { } [
      { options.schema = genSchema.mkSchemaOption { }; }
      (
        { config, ... }:
        let
          ms = names "m" (if levels == 1 then n - 1 else n);
          ts = names "t" n;
          sch = config.schema;
          mOrder = map (t: "m" + builtins.substring 1 1 t) (builtins.filter (x: x != "t") ord);
        in
        {
          config.schema = {
            r = { };
            t.options.trail = trailOpt;
            base = {
              inherits = if parented then [ sch.r ] else [ ];
              options = if guarded then { g = str "x"; } else { };
              config.trail = [ "base" ];
            };
            d = {
              inherits = map (x: sch.${x}) ord;
              config.trail = [ "d" ];
            };
          }
          // lib.genAttrs ms (m: {
            inherits = [ sch.base ];
            config.trail = [ m ];
          })
          // (
            if levels == 2 then
              lib.genAttrs ts (t: {
                inherits = map (m: sch.${m}) mOrder;
                config.trail = [ t ];
              })
            else
              { }
          );
        }
      )
    ]).config.schema;
  ord1 =
    n:
    perms (
      [
        "t"
        "base"
      ]
      ++ names "m" (n - 1)
    );
  ord2 = n: perms ([ "t" ] ++ names "t" n);
  shapes =
    parented: n:
    let
      canon = [
        "t"
        "base"
      ]
      ++ names "m" (n - 1);
      s = build parented false 1 n canon;
    in
    {
      sameValue = {
        expr = over (
          map (i: both "trail" (lib.replicate i s.base ++ [ s.t ] ++ lib.replicate (n - i) s.base)) (
            lib.range 0 n
          )
        );
        expected = pinned (n + 1) [ "base" ];
      };
      diamond = {
        expr = over (map (o: both "trail" [ (build parented false 1 n o).d ]) (ord1 n));
        expected = pinned (fact (n + 1)) (
          [
            "base"
            "d"
          ]
          ++ names "m" (n - 1)
        );
      };
      diamond2 = {
        expr = over (map (o: both "trail" [ (build parented false 2 n o).d ]) (ord2 n));
        expected = pinned (fact (n + 1)) (
          [
            "base"
            "d"
          ]
          ++ names "m" n
          ++ names "t" n
        );
      };
      guardedG = {
        expr = over (map (o: both "g" [ (build parented true 1 n o).d ]) (ord1 n));
        expected = pinned (fact (n + 1)) "x";
      };
      guardedG2 = {
        expr = over (map (o: both "g" [ (build parented true 2 n o).d ]) (ord2 n));
        expected = pinned (fact (n + 1)) "x";
      };
      # removed by the computed key, as a caller writes it
      removal = {
        expr = over (
          map (
            o:
            both "trail" [
              (build parented false 1 n o).d
              { disabledModules = [ { key = (s.base { }).key; } ]; }
            ]
          ) (ord1 n)
        );
        expected = pinned (fact (n + 1)) ([ "d" ] ++ names "m" (n - 1));
      };
    };

  excludes =
    guarded:
    {
      default = [ ];
      merge = acc: val: acc ++ val;
    }
    // (if guarded then { } else { identity = false; });
  buildGuarded =
    guarded: parented: n: ord:
    (genMerge.evalModuleTree { } [
      (
        { config, ... }:
        let
          sch = config.schema;
        in
        {
          options.schema = genSchema.mkSchemaOption { collections.excludes = excludes guarded; };
          config.schema = {
            r = { };
            t.options.trail = trailOpt;
            base = {
              inherits = if parented then [ sch.r ] else [ ];
              excludes = [ "e" ];
              config.trail = [ "base" ];
            };
            d = {
              inherits = map (x: sch.${x}) ord;
              config.trail = [ "d" ];
            };
          }
          // lib.genAttrs (names "m" (n - 1)) (m: {
            inherits = [ sch.base ];
            config.trail = [ m ];
          });
        }
      )
    ]).config.schema;
  guardedShapes =
    guarded: parented: n:
    let
      canon = [
        "t"
        "base"
      ]
      ++ names "m" (n - 1);
      s = buildGuarded guarded parented n canon;
    in
    {
      sameValue = {
        expr = over (
          map (i: both "trail" (lib.replicate i s.base ++ [ s.t ] ++ lib.replicate (n - i) s.base)) (
            lib.range 0 n
          )
        );
        expected = pinned (n + 1) [ "base" ];
      };
      diamond = {
        expr = over (map (o: both "trail" [ (buildGuarded guarded parented n o).d ]) (perms canon));
        expected = pinned (fact (n + 1)) (
          [
            "base"
            "d"
          ]
          ++ names "m" (n - 1)
        );
      };
    };

  # the grid as cells `test-<parentage>-n<N>-<shape>`
  grid =
    f:
    builtins.listToAttrs (
      lib.concatMap
        (
          parented:
          lib.concatMap
            (
              n:
              lib.mapAttrsToList (shape: cell: {
                name = "test-${if parented then "parented" else "parentless"}-n${toString n}-${shape}";
                value = cell;
              }) (f parented n)
            )
            [
              2
              3
              4
            ]
        )
        [
          true
          false
        ]
    );

  # K2 (b): the schema's plain base module, keyed by its declaration node and sealed by its value
  schemaOf =
    opts:
    (genMerge.evalModuleTree { } [
      { options.schema = genSchema.mkSchemaOption opts; }
      { config.schema.p.options.pa = str "from-p"; }
      {
        config.schema.user = {
          options.ua = str "u";
          inherits = [ "p" ];
        };
      }
    ]).config.schema;
  kindOf =
    opts: name:
    (genMerge.evalModuleTree { } [
      { options.schema = genSchema.mkSchemaOption opts; }
      { config.schema.${name} = { }; }
    ]).config.schema.${name};
  plain = {
    options.tag = str "x";
  };
  shared = {
    options.tag = str "s";
  };
  baseA = {
    options.ta = listO;
    config.ta = [ "a" ];
  };
  # derived by `//`: its first attribute's position is baseA's, and its value equals baseA's
  baseC = {
    options.tc = listO;
  }
  // baseA;
  schemaMod = name: {
    options.schema = genSchema.mkSchemaOption {
      baseModule = {
        options.t = listO;
        config.t = [ "b" ];
      };
    };
    config.schema.${name} = { };
  };
  mkBase = v: {
    options.t = listO;
    config.t = [ v ];
  };
  # two fromJSON literals: their first attribute carries no position, so neither is keyed
  cleanA = builtins.fromJSON ''{"config":{"ta":["a"]},"options":{}}'' // {
    options.ta = listO;
  };
  cleanB = builtins.fromJSON ''{"config":{"tb":["b"]},"options":{}}'' // {
    options.tb = listO;
  };
  poslessPlain = builtins.fromJSON ''{"config":{}}'' // {
    options.tag = str "x";
  };
  mixedGuard =
    args:
    try (
      import ../test-fixtures/mixed-guard.nix (
        {
          inherit genSchema genMerge;
        }
        // args
      )
    );
in
{
  flake.tests.key-dedup-every-order = grid shapes;

  flake.tests.key-guarded-kind-dedup =
    lib.mapAttrs' (n: v: lib.nameValuePair "${n}-guarded" v) (grid (guardedShapes true))
    // lib.mapAttrs' (n: v: lib.nameValuePair "${n}-identity-false" v) (grid (guardedShapes false));

  # the mixed-guard fixture's live control: no second construction reached, so the instance reads its
  # address under either schema, whichever reads the instance (its refusals: ci/tests-error.nix,
  # `key-guarded-pair-refusals`)
  flake.tests.key-guarded-pair-control = {
    test-one-construction-under-either-schema-serves = {
      expr =
        lib.concatMap
          (
            outer:
            lib.concatMap
              (
                self:
                map
                  (
                    read:
                    mixedGuard {
                      inherit outer self read;
                      inner = outer;
                      copies = 0;
                    }
                  )
                  [
                    "instance"
                    "const"
                  ]
              )
              [
                "parented"
                "parentless"
              ]
          )
          [
            "guarded"
            "plain"
          ];
      expected = lib.replicate 8 "10.0.1.1";
    };
  };

  flake.tests.key-base-module = {
    # one plain base reached through parent and child is one module in both engines
    test-a-plain-base-through-parent-and-child-composes-once = {
      expr = both "tag" [ (schemaOf { baseModule = plain; }).user ];
      expected = {
        gen = "x";
        nixpkgs = "x";
      };
    };
    # one base value shared by two schema constructions is one value: one module
    test-one-base-value-under-two-schemas-is-one-module = {
      expr = both "tag" [
        (kindOf { baseModule = shared; } "x")
        (kindOf {
          baseModule = shared;
          collections.c = { };
        } "y")
      ];
      expected = {
        gen = "s";
        nixpkgs = "s";
      };
    };
    # one literal reached from two trees is one construction
    test-one-base-literal-in-two-trees-is-one-module = {
      expr = both "t" [
        (genMerge.evalModuleTree { } [ (schemaMod "x") ]).config.schema.x
        (genMerge.evalModuleTree { } [ (schemaMod "y") ]).config.schema.y
      ];
      expected = {
        gen = [ "b" ];
        nixpkgs = [ "b" ];
      };
    };
    # a base derived by `//` that equals its source is the same construction
    test-a-base-derived-equal-to-its-source-is-one-module = {
      expr = both "ta" [
        (kindOf { baseModule = baseA; } "x")
        (kindOf { baseModule = baseC; } "y")
      ];
      expected = {
        gen = [ "a" ];
        nixpkgs = [ "a" ];
      };
    };
    # two explicitly empty bases are no keyed module
    test-two-empty-bases-compose = {
      expr = both "z" [
        (kindOf { baseModule = { }; } "x")
        (kindOf { baseModule = { }; } "y")
        { options.z = str "z"; }
      ];
      expected = {
        gen = "z";
        nixpkgs = "z";
      };
    };
    # two posless bases written apart stay unkeyed and both compose
    test-two-posless-bases-both-compose = {
      expr = run "gen" "ta" [
        (kindOf { baseModule = cleanA; } "x")
        (kindOf { baseModule = cleanB; } "y")
      ];
      expected = [ "a" ];
    };
    # a posless base with a defaulted option, reached through parent and child, is two unkeyed
    # declarations, which both engines refuse
    test-a-posless-base-through-parent-and-child-is-refused = {
      expr = both "tag" [ (schemaOf { baseModule = poslessPlain; }).user ];
      expected = {
        gen = "REFUSED";
        nixpkgs = "REFUSED";
      };
    };
    # two values at one declaration node are two constructions: gen refuses by name in either order
    test-two-base-values-at-one-node-are-refused = {
      expr = {
        ab = run "gen" "t" [
          (kindOf { baseModule = mkBase "a"; } "x")
          (kindOf { baseModule = mkBase "b"; } "y")
        ];
        ba = run "gen" "t" [
          (kindOf { baseModule = mkBase "b"; } "y")
          (kindOf { baseModule = mkBase "a"; } "x")
        ];
      };
      expected = {
        ab = "REFUSED";
        ba = "REFUSED";
      };
    };
  };
}
