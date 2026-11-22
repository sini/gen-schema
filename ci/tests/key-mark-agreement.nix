# THE KEY-vs-MARK AGREEMENT RAZOR (den-hoag-a7c9r arm B′): a kind's foreign key must split exactly where
# its mark splits. The key is a syntactic reading of what the mark mints wherever no opaque module is
# reached, and the mark itself where one is; a mark component with no twin in the key makes the key
# COARSER (marks differ, keys equal: nixpkgs keeps one of two constructions the mark tells apart), a
# key component with no twin in the mark makes it FINER. Each row is two constructions of one kind
# declaration position under two schema evaluations, read as `{ w; m; k; }`: witnesses equal (one
# declaration node), marks equal, foreign keys equal. Only one-node rows (`w`) are the property's; the
# others compose by node and are carried as rows only.
#
# The corpus: 55 constructed shapes, each as a differing pair and as a twin, the granularity razor's
# default-arm rows (`kind-preimage-razor.nix`, read here for `{ w; m; k; }`), 11 declared-collection
# pairs under both identity settings, 2 rows over an `identity = false` collection and 2 over a kept
# collection the kind does not define. The `mkType` arm writes no foreign key. Four shapes redeclare one
# option embedding an instance type (twice, beside a plain submodule in either order, thrice), a join
# gen-merge mints over its declarations (den-hoag-2vtgj). Thirty-four vary one construction parameter: the
# base (absent, empty, attrset at one or two literals, positionless, function, path), the mixins (two
# lists that fold to one record among them, a no-op mixin once, twice or not at all), a
# sealed leaf beside an inert one (keySemantics, a seed, a computed field, a kept value), `{ }` against
# `[ ]` (a seed, a kept value, a typed default), a typed collection's seed resolved from its type's
# empty value, specialArgs, and a declaration's open paths and module order (den-hoag-y9j03).
#
# PLANTED RED, in the suite: the same predicate over a node-only key (the witness alone, no content)
# reads every one-node row whose marks differ as coarser, so a zero on the real key is read with the
# predicate seen to fire.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  T = genMerge.types;
  try =
    v:
    let
      r = builtins.tryEval (builtins.deepSeq v v);
    in
    if r.success then r.value else "REFUSED";
  fkey = k: try ((k.__functor k { }).key or "<none>");
  read = a: b: {
    w = try (a.__kindWitness == b.__kindWitness);
    m = try (a.__mint.minted == b.__mint.minted);
    k = fkey a == fkey b;
  };
  opt = t: genMerge.mkOption { type = t; };
  schema =
    args: kinds:
    (genMerge.evalModuleTree { } [
      { options.schema = genSchema.mkSchemaOption args; }
      ({ config, ... }: { config.schema = kinds config; })
    ]).config.schema;
  enumOpt =
    tag:
    opt (
      T.listOf (
        T.enum "e" [
          tag
          "k"
        ]
      )
    );
  # the redeclaration shapes: `owner` embeds an instance type of `user` (tag "a") or `grp`, declared more than once
  embedded = schema { } (_: {
    user.options.uname = opt T.str;
    grp.options.gid = opt T.int;
  });
  instanceOf = tag: genSchema.mkInstanceType { } (if tag == "a" then embedded.user else embedded.grp);
  plainSub = T.submodule { options.extra = genMerge.mkOption { default = ""; }; };
  redeclared = tys: {
    args = { };
    decl = lib.mkMerge (map (t: { options.owner = opt t; }) tys);
  };
  # the construction-parameter shapes (den-hoag-y9j03): a schema's base, mixins, sealed parameters and
  # specialArgs, and a declaration's open paths and module order, each one kind declaration `trail`
  noopMixin = genSchema.mkMixin { } (_: { });
  addMixin =
    t: d:
    genSchema.mkMixin { } (_: {
      mx = genMerge.mkOption {
        type = t;
        default = d;
      };
    });
  # one literal position, two contents: a base built by a function of its type
  baseOf = t: { options.bx = opt t; };
  # no attribute position at all: `listToAttrs` mints none
  positionlessBaseOf =
    t:
    builtins.listToAttrs [
      {
        name = "options";
        value = {
          bx = opt t;
        };
      }
    ];
  sealedFn = _: null;
  # a function base resolving to a function module that reads a specialArg
  specialArgBase = _: { baseType, ... }: { options.bx = opt baseType; };
  withArgs = args: {
    inherit args;
    decl = {
      options.trail = opt T.str;
    };
  };
  importedPair = {
    p = {
      options.p = opt T.str;
    };
    q = {
      options.q = opt T.str;
    };
  };
  shapes = {
    # ── construction parameters (den-hoag-y9j03): the key reads the base as a def, the sealed
    # parameters per leaf, the open paths, and no module index ──
    mixinsDiffer =
      tag:
      withArgs {
        baseModule = { };
        mixins = [ (if tag == "a" then noopMixin else addMixin T.str "") ];
      };
    mixinsTypeDiffer =
      tag:
      withArgs {
        baseModule = { };
        mixins = [ (if tag == "a" then addMixin T.str "" else addMixin T.int 0) ];
      };
    mixinNoopVsNone =
      tag: withArgs ({ baseModule = { }; } // (if tag == "a" then { } else { mixins = [ noopMixin ]; }));
    # a no-op mixin is the unit of mixin composition, so its multiplicity is no component
    mixinNoopTwoVsOne =
      tag:
      withArgs {
        baseModule = { };
        mixins =
          if tag == "a" then
            [ noopMixin ]
          else
            [
              noopMixin
              noopMixin
            ];
      };
    # the mark spreads `{ }` and `[ ]` to one component (den-hoag-0pwbu), so the key reading its
    # spellings per leaf adopts that class: a seed, a kept value, a typed default
    seedEmptyAttrsVsList =
      tag: withArgs { collections.extra.default = if tag == "a" then { } else [ ]; };
    keptEmptyAttrsVsList = tag: {
      args = {
        collections.tags.default = "d";
      };
      decl = {
        options.trail = opt T.str;
        tags = if tag == "a" then { } else [ ];
      };
    };
    typedListVsAttrsDefault =
      tag:
      withArgs {
        collections.p =
          if tag == "a" then
            {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            }
          else
            {
              type = lib.types.attrsOf lib.types.str;
              default = { };
            };
      };
    # a typed collection no kind defines and with no default holds its type's own empty value, so it
    # marks as a `default` of that value: the key reads the same resolved seed
    typedUndefVsDefault =
      tag:
      withArgs {
        collections.p = {
          type = lib.types.listOf lib.types.str;
        }
        // (if tag == "a" then { } else { default = [ ]; });
      };
    # and where a kind defines it, the seed both hold is one, so its presence is no component
    typedDefaultPresenceDefined = tag: {
      args.collections.tags = {
        type = lib.types.listOf lib.types.str;
      }
      // (if tag == "a" then { } else { default = [ ]; });
      decl = {
        options.trail = opt T.str;
        tags = [ "x" ];
      };
    };
    typedUndefListVsAttrs =
      tag:
      withArgs {
        collections.p.type =
          if tag == "a" then lib.types.listOf lib.types.str else lib.types.attrsOf lib.types.str;
      };
    typedUndefNullVsList =
      tag:
      withArgs {
        collections.p.type =
          if tag == "a" then lib.types.nullOr lib.types.str else lib.types.listOf lib.types.str;
      };
    # two mixin lists that fold to one record: the later `mx` shadows the earlier
    mixinShadowed =
      tag:
      withArgs {
        baseModule = { };
        mixins =
          if tag == "a" then
            [ (addMixin T.str "") ]
          else
            [
              (addMixin T.int 0)
              (addMixin T.str "")
            ];
      };
    baseFnDiffer =
      tag:
      withArgs {
        baseModule =
          if tag == "a" then (_: { options.bx = opt T.str; }) else (_: { options.bx = opt T.int; });
      };
    baseFnTwoSame =
      tag:
      withArgs {
        baseModule =
          if tag == "a" then (_: { options.bx = opt T.str; }) else (_: { options.bx = opt T.str; });
      };
    baseFnVsAttrs =
      tag:
      withArgs {
        baseModule = if tag == "a" then (_: { options.bx = opt T.str; }) else { options.bx = opt T.str; };
      };
    baseSpecialArgsDiffer =
      tag:
      withArgs {
        baseModule = specialArgBase;
        specialArgs.baseType = if tag == "a" then T.str else T.int;
      };
    specialArgsOnly = tag: withArgs { specialArgs.baseType = if tag == "a" then T.str else T.int; };
    baseAttrsOnePos = tag: withArgs { baseModule = baseOf (if tag == "a" then T.str else T.int); };
    baseNoPosDiffer =
      tag: withArgs { baseModule = positionlessBaseOf (if tag == "a" then T.str else T.int); };
    basePathDiffer =
      tag:
      withArgs {
        baseModule =
          if tag == "a" then ../test-fixtures/key-base-bx.nix else ../test-fixtures/key-base-by.nix;
      };
    basePathVsInline =
      tag:
      withArgs {
        baseModule =
          if tag == "a" then
            ../test-fixtures/key-base-bx.nix
          else
            {
              options.bx = {
                _type = "option";
              };
            };
      };
    baseEmptyVsAbsent = tag: withArgs (if tag == "a" then { } else { baseModule = { }; });
    baseModulePos =
      tag:
      withArgs {
        baseModule = if tag == "a" then { options.bx = opt T.str; } else { options.bx = opt T.str; };
      };
    baseTwoPosDiffer =
      tag:
      withArgs {
        baseModule = if tag == "a" then { options.bx = opt T.str; } else { options.bx = opt T.int; };
      };
    keySemSealedDiffer =
      tag:
      withArgs {
        keySemantics = {
          f = sealedFn;
          c = tag;
        };
      };
    collSealedAttrsDiffer =
      tag:
      withArgs {
        collections.extra.default = {
          f = sealedFn;
          v = tag;
        };
      };
    collSealedListDiffer =
      tag:
      withArgs {
        collections.extra.default = [
          sealedFn
          tag
        ];
      };
    computedSealedLeaf =
      tag:
      withArgs {
        computed = _: _: {
          f = sealedFn;
          c = tag;
        };
      };
    keptCollectionSealedAttrs = tag: {
      args = {
        collections.tags.default = { };
      };
      decl = {
        options.trail = opt T.str;
        tags = {
          f = sealedFn;
          v = tag;
        };
      };
    };
    mkTypeDiffer =
      tag:
      withArgs {
        mkType =
          { defs, ... }:
          {
            __functor = _: { ... }: { imports = map (d: d.value) defs; };
          };
      };
    computedDiffer = tag: withArgs { computed = _: _: { c = tag; }; };
    defConfigPresence = tag: {
      args = { };
      decl = {
        options.trail = opt T.str;
        config = if tag == "a" then { } else { trail = "x"; };
      };
    };
    optDefaultPresence = tag: {
      args = { };
      decl = {
        options.trail = genMerge.mkOption (
          { type = T.str; } // (if tag == "a" then { } else { default = ""; })
        );
      };
    };
    importOrderSwap = tag: {
      args = { };
      decl = {
        imports =
          if tag == "a" then
            [
              importedPair.p
              importedPair.q
            ]
          else
            [
              importedPair.q
              importedPair.p
            ];
      };
    };
    instanceTwice =
      tag:
      redeclared [
        (instanceOf tag)
        (instanceOf tag)
      ];
    instancePlus =
      tag:
      redeclared [
        (instanceOf tag)
        plainSub
      ];
    instancePlusRev =
      tag:
      redeclared [
        plainSub
        (instanceOf tag)
      ];
    instanceThrice =
      tag:
      redeclared [
        (instanceOf tag)
        (instanceOf tag)
        (instanceOf tag)
      ];
    schemaCollection = tag: {
      args =
        if tag == "a" then
          { }
        else
          {
            collections.tags = {
              default = [ "x" ];
              merge = acc: v: acc ++ v;
            };
          };
      decl = {
        options.trail = opt (T.listOf T.str);
      };
    };
    topOption = tag: {
      args = { };
      decl = {
        options.trail = enumOpt tag;
      };
    };
    nestedOption = tag: {
      args = { };
      decl = {
        options.n.trail = enumOpt tag;
      };
    };
    importedAttrsetModule = tag: {
      args = { };
      decl = {
        imports = [ { options.trail = enumOpt tag; } ];
      };
    };
    importedFunctionModule = tag: {
      args = { };
      decl = {
        imports = [ ({ ... }: { options.trail = enumOpt tag; }) ];
      };
    };
    functionModuleDef = tag: {
      args = { };
      decl = { ... }: { options.trail = enumOpt tag; };
    };
    computedField = tag: {
      args = {
        computed = _: _: { c = tag; };
      };
      decl = {
        options.trail = opt T.str;
      };
    };
    keptCollectionValue = tag: {
      args = {
        collections.tags.default = [ ];
      };
      decl = {
        options.trail = opt T.str;
        tags = [ tag ];
      };
    };
    keptCollectionLambda = tag: {
      args = {
        collections.tags.default = [ ];
      };
      decl = {
        options.trail = opt T.str;
        tags = [ (_: tag) ];
      };
    };
    keptCollectionPath = tag: {
      args = {
        collections.tags.default = [ ];
      };
      decl = {
        options.trail = opt T.str;
        tags = [ (if tag == "a" then ./key-mark-agreement.nix else ./key-construction-parity.nix) ];
      };
    };
    optionDefault = tag: {
      args = { };
      decl = {
        options.trail = genMerge.mkOption {
          type = T.str;
          default = tag;
        };
      };
    };
    configValue = tag: {
      args = { };
      decl = {
        options.trail = opt T.str;
        config.trail = tag;
      };
    };
    nixpkgsTypeOption = tag: {
      args = { };
      decl = {
        options.trail = lib.mkOption {
          type = lib.types.enum [
            tag
            "k"
          ];
        };
      };
    };
    submoduleOption = tag: {
      args = { };
      decl = {
        options.s = opt (T.submodule { options.${tag} = opt T.str; });
      };
    };
    freeform = tag: {
      args = { };
      decl = {
        freeformType = T.attrsOf (T.enum "e" [ tag ]);
        options.trail = opt T.str;
      };
    };
    twoDeclsMerged = tag: {
      args = { };
      decl = {
        options.trail = enumOpt tag;
      };
      extraDecl = {
        options.trail = enumOpt "k";
      };
    };
    parentType = tag: {
      args = { };
      parent = {
        options.p = enumOpt tag;
      };
      decl = {
        options.trail = opt T.str;
        inherits = [ "par" ];
      };
    };
  };
  build =
    shape: tag:
    let
      s = shape tag;
    in
    (schema s.args (
      _:
      {
        k =
          if s ? extraDecl then
            lib.mkMerge [
              s.decl
              s.extraDecl
            ]
          else
            s.decl;
      }
      // (if s ? parent then { par = s.parent; } else { })
    )).k;
  shapeRows = lib.concatMapAttrs (n: shape: {
    "${n}" = read (build shape "a") (build shape "b");
    "${n}Twin" = read (build shape "a") (build shape "a");
  }) shapes;
  razorRows =
    let
      opt = t: genMerge.mkOption { type = t; };
      optd =
        t: d:
        genMerge.mkOption {
          type = t;
          default = d;
        };
      arms = {
        default = { };
        mkType = {
          mkType =
            { defs, ... }:
            {
              __functor =
                _:
                { ... }:
                {
                  imports = map (d: d.value) defs;
                };
            };
        };
      };
      dec =
        a: b:
        let
          r = builtins.tryEval (builtins.deepSeq (genSchema.kindEq a b) (genSchema.kindEq a b));
        in
        if r.success then r.value else "REFUSED";
      fkey =
        k:
        let
          r = builtins.tryEval ((k.__functor k { }).key or "<none>");
        in
        if r.success then r.value else "REFUSED";
      read = a: b: {
        w = a.__kindWitness == b.__kindWitness;
        m = a.__mint.minted == b.__mint.minted;
        k = fkey a == fkey b;
      };
      sub = n: T.submodule { options.${n} = opt T.str; };
      chk =
        c:
        T.mkOptionType {
          name = "chk";
          check = c;
          merge = loc: defs: (builtins.head defs).value;
        };
      A = {
        options.x = opt T.str;
      };
      B = {
        options.y = opt T.str;
        inherits = [ "a" ];
      };
      rowsOf =
        args:
        let
          schemaWith =
            extra: kinds:
            (genMerge.evalModuleTree { } [
              { options.schema = genSchema.mkSchemaOption (args // extra); }
              { config.schema = kinds; }
            ]).config.schema;
          schemaOf = schemaWith { };
          # child `b` inherits `a`: the two parents' bodies and the two children's own bodies
          pair =
            pa: ca: pb: cb:
            read
              (schemaOf {
                a = pa;
                b = {
                  inherits = [ "a" ];
                }
                // ca;
              }).b
              (schemaOf {
                a = pb;
                b = {
                  inherits = [ "a" ];
                }
                // cb;
              }).b;
          dia =
            a: cInherits:
            schemaOf {
              inherit a;
              b = {
                options.y = opt T.str;
                inherits = [ "a" ];
              };
              c = {
                options.z = opt T.str;
                inherits = cInherits;
              };
              d = {
                options.w = opt T.str;
                inherits = [
                  "b"
                  "c"
                ];
              };
            };
          two =
            dInherits:
            schemaOf {
              a = A;
              b = B;
              c.inherits = [ "a" ];
              d = {
                options.w = opt T.str;
                inherits = dInherits;
              };
            };
          ord =
            dInherits:
            schemaOf {
              a = A;
              b = B;
              c.options.z = opt T.str;
              d.inherits = dInherits;
            };
          coll =
            d:
            schemaWith { collections.tags.default = d; } {
              a = A;
              b = B;
            };
          fm = {
            options.x = opt T.str;
            imports = [ ({ ... }: { options.f = opt T.str; }) ];
          };
        in
        {
          twinParented = pair A { } A { };
          parentDefault = pair A { } { options.x = optd T.str "d"; } { };
          parentCollection = pair A { } (A // { validators = [ "v" ]; }) { };
          diamondTwin = read (dia A [ "a" ]).d (dia A [ "a" ]).d;
          diamondAncestorDefault = read (dia A [ "a" ]).d (dia { options.x = optd T.str "d"; } [ "a" ]).d;
          diamondShortcut = read (dia A [ "a" ]).d (dia A [ "b" ]).d;
          redeclSameType = pair A { options.x = opt T.str; } A { };
          subChildHalfDiffers = pair { options.s = opt (sub "p"); } { options.s = opt (sub "q"); } {
            options.s = opt (sub "p");
          } { options.s = opt (sub "r"); };
          parentFunctionModuleTwin = pair fm { } fm { };
          childConfigDiffers = pair A { config.x = "u"; } A { config.x = "v"; };
          chkInheritedParentDiffers = pair { options.x = opt (chk builtins.isString); } { } {
            options.x = opt (chk builtins.isInt);
          } { };
          parentOptionType = pair A { } { options.x = opt T.int; } { };
          order =
            read
              (ord [
                "b"
                "c"
              ]).d
              (ord [
                "c"
                "b"
              ]).d;
          twoPathsVsOne =
            read
              (two [
                "b"
                "c"
              ]).d
              (two [ "b" ]).d;
          schemaCollection = read (coll [ ]).b (coll [ "t" ]).b;
          redeclWithDefault = pair A { options.x = optd T.str "d"; } A { };
          # the child re-declares the parent's `enum "e" [ "a" ]` as `enum "e" [ "b" ]`: the two merge, so the
          # child's type at the inherited path is minted, exact and NOT the parent's; only the guard's mark
          # comparison keeps it tagged (dropped, the pair reads equal marks against the undeclared child)
          enumMergedAtInheritedPath = pair { options.x = opt (T.enum "e" [ "a" ]); } {
            options.x = opt (T.enum "e" [ "b" ]);
          } { options.x = opt (T.enum "e" [ "a" ]); } { };
          # the child re-declares the parent's `str` option with a rewritten `check`: that type is not a
          # gen record with a mark, so the path is tagged by the guard's `m != null` half; with the whole
          # guard dropped the pair reads equal marks
          retypedAtInheritedPath = pair A {
            options.x = opt (T.str // { check = builtins.isString; });
          } A { };
        };
      # the default arm only: `mkType` refuses `identity = false`
      policy =
        tags:
        (genMerge.evalModuleTree { } [
          {
            options.schema = genSchema.mkSchemaOption {
              collections.tags = {
                default = [ ];
                identity = false;
              };
            };
          }
          {
            config.schema = {
              a = A // {
                inherit tags;
              };
              b = B;
            };
          }
        ]).config.schema;
    in
    rowsOf arms.default
    // {
      identityFalseA = read (policy [ "t1" ]).a (policy [ "t2" ]).a;
      identityFalseB = read (policy [ "t1" ]).b (policy [ "t2" ]).b;
    };
  # DECLARED collections: one kind declaration node (`portsDef`) under schemas whose `ports` differ
  # in one field of its declaration, both identity settings. The mark reads a collection's name and,
  # where it is kept in identity, its resolved default and its value; a `type`, a `merge` and an
  # `identity` enter no mark, so the key must not split on them, on their presence either
  # (den-hoag-collection-declared-element-type-fwjez for `type`). A `merge` that changes the merged
  # value splits the mark through the value, and the key with it.
  declaredRows =
    let
      portsDef = {
        ports = [ 3 ];
      };
      kindOf =
        decl:
        (schema { collections.ports = decl; } (_: {
          user = portsDef;
        })).user;
      chk =
        c:
        T.mkOptionType {
          name = "c";
          check = c;
          merge = _: defs: (builtins.head defs).value;
        };
      odd = x: x / 2 * 2 != x;
      cat = acc: v: acc ++ v;
      nullCat = acc: v: (if acc == null then [ ] else acc) ++ v;
      pairs = {
        mergePresence = {
          a = {
            default = [ ];
            merge = cat;
          };
          b.default = [ ];
        };
        mergeChangesValue = {
          a = {
            default = [ ];
            merge = acc: v: acc ++ v ++ v;
          };
          b.default = [ ];
        };
        identityPresence = {
          a = {
            default = [ ];
            identity = true;
          };
          b.default = [ ];
        };
        defaultValue = {
          a.default = [ ];
          b.default = [ 9 ];
        };
        defaultPresence = {
          a.merge = nullCat;
          b = {
            default = [ ];
            merge = nullCat;
          };
        };
        orderedDefault = {
          a.default = lib.mkOrder 500 [ ];
          b.default = [ ];
        };
        elemIfTrue = {
          a.default = [ (lib.mkIf true 9) ];
          b.default = [ 9 ];
        };
        attrMkDefault = {
          a.default = {
            x = lib.mkDefault 1;
          };
          b.default = {
            x = 1;
          };
        };
        declaredVsUndeclared = {
          a = {
            default = [ ];
            type = T.listOf T.int;
          };
          b.default = [ ];
        };
        checkOnly = {
          a = {
            default = [ ];
            type = T.listOf (chk odd);
          };
          b = {
            default = [ ];
            type = T.listOf (chk (_: true));
          };
        };
        elemTypeOnly = {
          a = {
            default = [ ];
            type = T.listOf T.int;
          };
          b = {
            default = [ ];
            type = T.listOf T.raw;
          };
        };
      };
    in
    lib.concatMapAttrs (n: p: {
      "${n}" = read (kindOf p.a) (kindOf p.b);
      "${n}IdFalse" = read (kindOf (p.a // { identity = false; })) (
        kindOf (p.b // { identity = false; })
      );
    }) pairs
    // (
      let
        kindWith =
          args:
          (schema args (_: {
            user = portsDef;
          })).user;
        # a kind that does not define `ports` reads its default where the mark reads its resolved seed
        undefinedOn =
          d:
          (schema { collections.ports.default = d; } (_: {
            user.options.trail = opt T.str;
          })).user;
        outOfIdentity = d: {
          default = d;
          identity = false;
        };
      in
      {
        # an `identity = false` collection's name is in the mark, its contents are not
        idFalseCollectionNamed =
          read
            (kindWith {
              collections = {
                ports.default = [ ];
                extra = outOfIdentity [ ];
              };
            })
            (kindWith {
              collections.ports.default = [ ];
            });
        # its default still reaches the mark through a computed field, which the key reads
        idFalseDefaultComputed =
          let
            k =
              d:
              kindWith {
                collections.ports = outOfIdentity d;
                computed = cs: _: { n = cs.ports; };
              };
          in
          read (k [ ]) (k [ 9 ]);
        elemIfTrueUndefined = read (undefinedOn [ (lib.mkIf true 9) ]) (undefinedOn [ 9 ]);
        attrMkDefaultUndefined = read (undefinedOn { x = lib.mkDefault 1; }) (undefinedOn {
          x = 1;
        });
      }
    );
  rows =
    shapeRows
    // lib.mapAttrs' (n: v: lib.nameValuePair "razor-${n}" v) razorRows
    // lib.mapAttrs' (n: v: lib.nameValuePair "declared-${n}" v) declaredRows;
  names = builtins.attrNames rows;
  oneNode = builtins.filter (n: rows.${n}.w == true) names;
  verdict = keyEq: {
    rows = builtins.length names;
    oneNode = builtins.length oneNode;
    nonBool = builtins.filter (n: !(builtins.isBool rows.${n}.w && builtins.isBool rows.${n}.m)) names;
    coarser = builtins.filter (n: !rows.${n}.m && keyEq n) oneNode;
    finer = builtins.filter (n: rows.${n}.m && !(keyEq n)) oneNode;
  };
in
{
  flake.tests.key-mark-agreement = {
    # A no-op mixin's delta is the empty record, the unit of mixin composition, so a kind built with it
    # equals one built with none, and one built with it twice (kindEq, the door the mark answers)
    test-a-no-op-mixin-kind-equals-the-kind-without-it = {
      expr = lib.genAttrs [ "mixinNoopVsNone" "mixinNoopTwoVsOne" ] (
        n: try (genSchema.kindEq (build shapes.${n} "a") (build shapes.${n} "b"))
      );
      expected = {
        mixinNoopVsNone = true;
        mixinNoopTwoVsOne = true;
      };
    };
    test-the-foreign-key-splits-exactly-where-the-mark-splits = {
      expr = verdict (n: rows.${n}.k);
      expected = {
        rows = 156;
        oneNode = 142;
        nonBool = [ ];
        coarser = [ ];
        finer = [ ];
      };
    };
    # the planted RED: a node-only key is equal on every one-node row
    test-a-node-only-key-reads-coarser-wherever-the-marks-differ = {
      expr = (verdict (_: true)).coarser;
      expected = [
        "baseAttrsOnePos"
        "baseFnDiffer"
        "baseNoPosDiffer"
        "basePathDiffer"
        "basePathVsInline"
        "baseSpecialArgsDiffer"
        "baseTwoPosDiffer"
        "collSealedAttrsDiffer"
        "computedDiffer"
        "computedField"
        "computedSealedLeaf"
        "declared-defaultPresence"
        "declared-defaultValue"
        "declared-idFalseCollectionNamed"
        "declared-idFalseDefaultComputed"
        "declared-mergeChangesValue"
        "defConfigPresence"
        "functionModuleDef"
        "importedAttrsetModule"
        "importedFunctionModule"
        "instancePlus"
        "instancePlusRev"
        "instanceThrice"
        "instanceTwice"
        "keptCollectionSealedAttrs"
        "keptCollectionValue"
        "keySemSealedDiffer"
        "mixinsDiffer"
        "mixinsTypeDiffer"
        "nestedOption"
        "optDefaultPresence"
        "parentType"
        "razor-diamondAncestorDefault"
        "razor-diamondShortcut"
        "razor-schemaCollection"
        "schemaCollection"
        "topOption"
        "twoDeclsMerged"
        "typedUndefNullVsList"
      ];
    };
  };
}
