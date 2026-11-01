# THE KEY-vs-MARK AGREEMENT RAZOR (den-hoag-a7c9r arm B′): a kind's foreign key must split exactly where
# its mark splits. The key is a syntactic reading of what the mark mints wherever no opaque module is
# reached, and the mark itself where one is; a mark component with no twin in the key makes the key
# COARSER (marks differ, keys equal: nixpkgs keeps one of two constructions the mark tells apart), a
# key component with no twin in the mark makes it FINER. Each row is two constructions of one kind
# declaration position under two schema evaluations, read as `{ w; m; k; }`: witnesses equal (one
# declaration node), marks equal, foreign keys equal. Only one-node rows (`w`) are the property's; the
# others compose by node and are carried as rows only.
#
# The corpus: 17 constructed shapes, each as a differing pair and as a twin, and the granularity
# razor's default-arm rows (`kind-preimage-razor.nix`, read here for `{ w; m; k; }`). The `mkType` arm
# writes no foreign key.
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
  shapes = {
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
  rows = shapeRows // lib.mapAttrs' (n: v: lib.nameValuePair "razor-${n}" v) razorRows;
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
    test-the-foreign-key-splits-exactly-where-the-mark-splits = {
      expr = verdict (n: rows.${n}.k);
      expected = {
        rows = 54;
        oneNode = 40;
        nonBool = [ ];
        coarser = [ ];
        finer = [ ];
      };
    };
    # the planted RED: a node-only key is equal on every one-node row
    test-a-node-only-key-reads-coarser-wherever-the-marks-differ = {
      expr = (verdict (_: true)).coarser;
      expected = [
        "computedField"
        "functionModuleDef"
        "importedAttrsetModule"
        "importedFunctionModule"
        "keptCollectionValue"
        "nestedOption"
        "parentType"
        "razor-diamondAncestorDefault"
        "razor-diamondShortcut"
        "razor-schemaCollection"
        "schemaCollection"
        "topOption"
        "twoDeclsMerged"
      ];
    };
  };
}
