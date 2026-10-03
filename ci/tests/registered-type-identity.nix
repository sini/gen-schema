# A REGISTERED predicate (gen-algebra `mkIntensional`) is decided by comparison and never keyed
# (den-hoag-6orb8 U1; den-hoag-hhki8). It enters a type, and through the type a kind, as a COMPARED
# component: the mark is blind to it (a revision bump leaves the mark unmoved), and `typeEq` and
# `kindEq` decide by its declared subject. A `refined` type's base enters by its mark, or SEALED where
# a wrapper rewrote its `check` (the C6 base collapse). Names are invented (ADR-0035).
{
  genSchema,
  genMerge,
  genAlgebra,
  genIdentity,
  genTypes,
  lib,
  ...
}:
let
  inherit (genSchema) mkSchemaOption kindEq;
  T = genMerge.types;
  refused = e: !(builtins.tryEval (builtins.deepSeq e e)).success;
  tree =
    modules:
    (genMerge.evalModuleTree {
      modules = [ { options.schema = mkSchemaOption { }; } ] ++ modules;
    }).config.schema;
  kindOf = t: (tree [ { config.schema.bobbin.options.n = genMerge.mkOption { type = t; }; } ]).bobbin;
  evalOpt =
    t: v:
    (genMerge.evalModuleTree {
      modules = [
        { options.o = genMerge.mkOption { type = t; }; }
        { config.o = v; }
      ];
    }).config.o;
  tryOpt =
    t: v:
    let
      r = builtins.tryEval (builtins.deepSeq (evalOpt t v) (evalOpt t v));
    in
    if r.success then r.value else "REFUSED";

  basting = {
    revision = "r1";
    members.stitch = a: v: builtins.isInt v && v >= a.lo && v <= a.hi;
  };
  # the honest mistake: same members and revision, a different builder body
  bastingB = {
    revision = "r1";
    members.stitch = a: v: builtins.isInt v && v > a.lo && v < a.hi;
  };
  basting2 = basting // {
    revision = "r2";
  };
  its = reg: args: genAlgebra.mkIntensional genIdentity.hashIdentity reg "stitch" args;
  range = {
    lo = 1;
    hi = 9;
  };
  t1 = its basting range;
  t1' = its basting range;
  t9 = its basting {
    lo = 1;
    hi = 10;
  };
  srf =
    base: c:
    genSchema.refined base {
      check = c;
      message = "range";
    };
  kindOfChk = c: kindOf (srf T.int c);
  oddBase = lib.types.addCheck T.int (v: builtins.bitAnd v 1 == 1);
in
{
  flake.tests.registered-type-identity = {
    # The registered term keys nothing: no exact identity, a sealed preimage tag.
    test-a-registered-term-keys-nothing = {
      expr = {
        exact = genAlgebra.isExact (genAlgebra.identityOf t1);
        tagMinted = genAlgebra.preimageTagOf genIdentity.hashIdentity t1 ? minted;
      };
      expected = {
        exact = false;
        tagMinted = false;
      };
    };

    # A revision bump leaves the kind's mark unmoved and is decided by `kindEq` (`false`); the
    # honest-mistake pair (same members and revision, different body) is the stated residue: one mark,
    # decided `true`, though the two compute differently.
    test-the-revision-decides-and-the-mark-is-blind-to-it = {
      expr = {
        markBlindToRevision =
          (kindOfChk t1).__mint.minted == (kindOfChk (its basting2 range)).__mint.minted;
        revisionDecides = kindEq (kindOfChk t1) (kindOfChk (its basting2 range));
        residueMark = (kindOfChk t1).__mint.minted == (kindOfChk (its bastingB range)).__mint.minted;
        residueDecides = kindEq (kindOfChk t1) (kindOfChk (its bastingB range));
        residueBehaviour = [
          (t1 1)
          ((its bastingB range) 1)
        ];
      };
      expected = {
        markBlindToRevision = true;
        revisionDecides = false;
        residueMark = true;
        residueDecides = true;
        residueBehaviour = [
          true
          false
        ];
      };
    };

    # Two constructions of one registered term are one type and one kind; a different term is decided
    # `false`; the term still enforces.
    test-registered-twins-are-one-type-and-one-kind = {
      expr = {
        schemaRefinedTwins = T.typeEq (srf T.int t1) (srf T.int t1');
        schemaRefinedDifferent = T.typeEq (srf T.int t1) (srf T.int t9);
        kindTypedefTwins = kindEq (kindOf (T.typedef "stitched" t1)) (kindOf (T.typedef "stitched" t1'));
        kindTypedefDifferent = kindEq (kindOf (T.typedef "stitched" t1)) (kindOf (T.typedef "stitched" t9));
        checks = [
          (tryOpt (T.typedef "stitched" t1) 5)
          (tryOpt (T.typedef "stitched" t1) 50)
        ];
      };
      expected = {
        schemaRefinedTwins = true;
        schemaRefinedDifferent = false;
        kindTypedefTwins = true;
        kindTypedefDifferent = false;
        checks = [
          5
          "REFUSED"
        ];
      };
    };

    # PROPAGATION through the kind: kinds over gen-types' `listOf (typedef R1)` and `listOf (typedef R9)`
    # share a mark and decide `false`. (gen-merge's `listOf` carries no mint yet, so a kind over it
    # compares the type record and refuses the pair by name; `refusedOverUnminted` pins that.)
    test-sealed-subjects-propagate-into-the-kind = {
      expr = {
        refusedOverUnminted = refused (
          kindEq (kindOf (T.listOf (T.typedef "stitched" t1))) (kindOf (T.listOf (T.typedef "stitched" t9)))
        );
        markShared =
          (kindOf (genTypes.listOf (T.typedef "stitched" t1))).__mint.minted
          == (kindOf (genTypes.listOf (T.typedef "stitched" t9))).__mint.minted;
        different = kindEq (kindOf (genTypes.listOf (T.typedef "stitched" t1))) (
          kindOf (genTypes.listOf (T.typedef "stitched" t9))
        );
        twins = kindEq (kindOf (genTypes.listOf (T.typedef "stitched" t1))) (
          kindOf (genTypes.listOf (T.typedef "stitched" t1'))
        );
      };
      expected = {
        refusedOverUnminted = true;
        markShared = true;
        different = false;
        twins = true;
      };
    };

    # C6: `refined` over one registered term, on base `int` and on base `addCheck int odd`, admits and
    # refuses 4 differently, so the two are two types: their mints differ and `typeEq`/`kindEq` decide
    # `false`. The base `str` is the control.
    test-a-rewritten-base-is-not-its-bases-mint = {
      expr = {
        mintsEqual = (srf T.int t1).__mint.minted == (srf oddBase t1).__mint.minted;
        typeEq = T.typeEq (srf T.int t1) (srf oddBase t1);
        kindEq = kindEq (kindOfChk t1) (kindOf (srf oddBase t1));
        values = [
          (tryOpt (srf T.int t1) 4)
          (tryOpt (srf oddBase t1) 4)
        ];
        controlBaseStr = kindEq (kindOfChk t1) (kindOf (srf T.str t1));
      };
      expected = {
        mintsEqual = false;
        typeEq = false;
        kindEq = false;
        values = [
          4
          "REFUSED"
        ];
        controlBaseStr = false;
      };
    };

    # P2: the ancestor fold keys by mark, so two kinds named alike that share a mark and differ only
    # at a registered construction are refused by name, never kept first-wins; one kind reached twice
    # is one ancestor (the control).
    test-the-ancestor-fold-refuses-two-kinds-under-one-mark = {
      expr =
        let
          pWith = t: (tree [ { config.schema.p.options.n = genMerge.mkOption { type = t; }; } ]).p;
          d =
            a: b:
            (tree [
              {
                config.schema.d.imports = [
                  a
                  b
                ];
              }
            ]).d;
          p1 = pWith (T.typedef "s" t1);
          p9 = pWith (T.typedef "s" t9);
        in
        {
          marksEqual = p1.__mint.minted == p9.__mint.minted;
          twoKinds = refused (builtins.attrNames (d p1 p9).__kindAncestors);
          control = builtins.length (builtins.attrNames (d p1 p1).__kindAncestors);
        };
      expected = {
        marksEqual = true;
        twoKinds = true;
        control = 1;
      };
    };
  };
}
