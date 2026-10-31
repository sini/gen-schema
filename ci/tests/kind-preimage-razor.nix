# The granularity razor (den-hoag-a7c9r U2): a parent enters its child's mark by its own mark, so two
# constructions of one parented declaration share a mark and `kindEq` decides them, where a mark that
# sealed the parent made them refuse. Each row builds two kinds named alike in two schemas and reads
# `[ marksEqual kindEq ]`, `kindEq` being true, false or "REFUSED".
#
# Moves (base: refused): the parented and diamond twins decide true; parents differing at a default,
# a kept collection or a shared ancestor, and a diamond with a shortcut, decide false on differing
# marks. R->V: a child re-declaring a parent option with the same type (its published plane equals the
# undeclared one, `den-hoag-pa887` arm A), and parents differing only in an `identity = false`
# collection (`den-hoag-ux9xg` arm P; default arm only, `mkType` refuses `identity = false`).
# Unmoved (refused on base and head): the child's half of a shared submodule option differing, a parent
# function module twin, the child's own kind-level `config` differing, and a sealed `mkOptionType` at
# the inherited path differing. Never coarser (false on base and head): option type, `inherits` order,
# one option by two paths vs one, a schema collection, a re-declaration adding a `default`, and a
# re-declaration re-typing the inherited path. Each part of the exact-mark guard has a row a mutant
# removing it reddens: the mark comparison (`enumMergedAtInheritedPath`), `m != null` together with it
# (`retypedAtInheritedPath`), and the sealed-subjects condition (`subChildHalfDiffers`).
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  T = genMerge.types;
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
  read = a: b: [
    (a.__mint.minted == b.__mint.minted)
    (dec a b)
  ];
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
  expected = {
    enumMergedAtInheritedPath = [
      false
      false
    ];
    retypedAtInheritedPath = [
      false
      false
    ];
    twinParented = [
      true
      true
    ];
    parentDefault = [
      false
      false
    ];
    parentCollection = [
      false
      false
    ];
    diamondTwin = [
      true
      true
    ];
    diamondAncestorDefault = [
      false
      false
    ];
    diamondShortcut = [
      false
      false
    ];
    redeclSameType = [
      true
      true
    ];
    subChildHalfDiffers = [
      true
      "REFUSED"
    ];
    parentFunctionModuleTwin = [
      true
      "REFUSED"
    ];
    childConfigDiffers = [
      true
      "REFUSED"
    ];
    chkInheritedParentDiffers = [
      true
      "REFUSED"
    ];
    parentOptionType = [
      false
      false
    ];
    order = [
      false
      false
    ];
    twoPathsVsOne = [
      false
      false
    ];
    schemaCollection = [
      false
      false
    ];
    redeclWithDefault = [
      false
      false
    ];
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
{
  flake.tests.kind-preimage-razor =
    builtins.listToAttrs (
      builtins.concatLists (
        lib.mapAttrsToList (
          arm: args:
          lib.mapAttrsToList (row: v: {
            name = "test-${arm}-${row}";
            value = {
              expr = v;
              expected = expected.${row};
            };
          }) (rowsOf args)
        ) arms
      )
    )
    // {
      test-default-identity-false-collection = {
        expr = [
          (read (policy [ "t1" ]).a (policy [ "t2" ]).a)
          (read (policy [ "t1" ]).b (policy [ "t2" ]).b)
        ];
        expected = [
          [
            true
            true
          ]
          [
            true
            true
          ]
        ];
      };
    };
}
