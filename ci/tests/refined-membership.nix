# A refined type's refinements are part of its membership wherever it is used (§ Rondon 2008:
# `{v:B | e}` has no member failing `e`), den-hoag-refined-outside-kind-silent-1jlsq. Outside a kind
# the type refuses a violating value by name; inside one, a field whose refinements are ALL `lazy` is
# decided when it is demanded, and one strict refinement makes construction decide the whole
# conjunction (position (ii), defaulted and reversible). No registry argument, mixin path or nesting
# drops a declared refinement. Every value cell reads a value or "REFUSED" (`tryEval` over `deepSeq`);
# the `testsError` cells pin WHICH refusal fired.
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema)
    refined
    refinements
    mkSchemaOption
    mkInstanceRegistry
    mkMixin
    ;
  t = genMerge.types;

  tr =
    e:
    let
      r = builtins.tryEval (builtins.deepSeq e e);
    in
    if r.success then r.value else "REFUSED";

  pos = {
    check = v: v > 0;
    message = "must be positive";
  };
  lt10 = {
    check = v: v < 10;
    message = "lt10";
  };
  isInt = {
    check = builtins.isInt;
    message = "must be an int";
  };
  lazy = r: r // { lazy = true; };
  posT = refined t.int pos;
  mixedT = refined t.int [
    pos
    (lazy lt10)
  ];

  outside =
    ty: v:
    (genMerge.evalModuleTree { } [
      { options.o = genMerge.mkOption { type = ty; }; }
      { config.o = v; }
    ]).config.o;

  labelOpt = genMerge.mkOption {
    type = t.str;
    default = "w";
  };
  tagMixin =
    mkMixin
      {
        requires = [ ];
        provides = [ "tag" ];
      }
      (_: {
        tag = genMerge.mkOption {
          type = t.str;
          default = "t";
        };
      });
  # One instance `w1` of kind `widget` with fields `n` (typed `ty`) and `label`. `mixin` declares the
  # kind through `mkSchemaOption { mixins; baseModule; }` (the bridge path) instead of inline.
  inKindWith =
    mixin: ty: regRefs: v:
    (genMerge.evalModuleTree { } [
      {
        options.schema =
          if mixin then
            mkSchemaOption {
              mixins = [ tagMixin ];
              baseModule = {
                n = genMerge.mkOption { type = ty; };
                label = labelOpt;
              };
            }
          else
            mkSchemaOption { };
      }
      (
        if mixin then
          { config.schema.widget = { }; }
        else
          {
            config.schema.widget = {
              options.n = genMerge.mkOption { type = ty; };
              options.label = labelOpt;
            };
          }
      )
      (
        { config, ... }:
        {
          options.widgets = mkInstanceRegistry (
            if regRefs == null then { } else { refinements = regRefs; }
          ) config.schema.widget;
        }
      )
      { config.widgets.w1.n = v; }
    ]).config.widgets.w1;
  inKind = inKindWith false;

  # A non-flat base: `b` is a throw that neither the program (it reads `.label`) nor a strict
  # conjunct demands.
  hasA = {
    check = v: v ? a;
    message = "must have a";
  };
  allLt10 = lazy {
    check = v: builtins.all (x: x < 10) (builtins.attrValues v);
    message = "all lt10";
  };
  unforced = {
    a = 1;
    b = throw "unforced attribute";
  };
in
{
  flake.tests.refined-membership = {
    # ── outside a kind ────────────────────────────────────────────────────────────────────────
    test-outside-a-kind-refuses-a-violating-value = {
      expr = map tr [
        (outside posT (-1))
        (outside (t.listOf posT) [
          4
          (-1)
        ])
        (outside (refined t.int (lazy pos)) (-1))
      ];
      expected = [
        "REFUSED"
        "REFUSED"
        "REFUSED"
      ];
    };
    test-outside-a-kind-admits-a-member = {
      expr = map tr [
        (outside posT 4)
        (outside (t.listOf posT) [ 4 ])
      ];
      expected = [
        4
        [ 4 ]
      ];
    };
    test-the-published-check-is-the-membership = {
      expr = [
        (posT.check (-1))
        (posT.check 4)
        ((refined t.int (lazy pos)).check (-1))
      ];
      expected = [
        false
        true
        false
      ];
    };
    # An earlier refinement guards a later one: `positive` is ill-typed over a string and is never
    # applied to one, so the refusal is catchable (gen-types' `firstFailingRefinement` order).
    test-the-first-failing-refinement-guards-the-rest = {
      expr = tr (
        outside (refined (t.either t.int t.str) [
          isInt
          pos
        ]) "x"
      );
      expected = "REFUSED";
    };

    # ── in a kind: decisions RED (9031968) also made ──────────────────────────────────────────
    test-in-kind-decisions = {
      expr = builtins.mapAttrs (_: tr) {
        strictGood = (inKind posT null 5).n;
        strictBad = (inKind posT null (-1)).n;
        strictBadSibling = (inKind posT null (-1)).label;
        lazyGood = (inKind (refined t.int (lazy pos)) null 5).n;
        lazyBad = (inKind (refined t.int (lazy pos)) null (-1)).n;
        lazyBadSibling = (inKind (refined t.int (lazy pos)) null (-1)).label;
        ctlIntBad = (inKind t.int null "x").n;
        regArgLazyBadSibling = (inKind t.int { n = [ (lazy pos) ]; } (-1)).label;
        allLazyBothSibling = (inKind (refined t.int (lazy pos)) { n = [ (lazy lt10) ]; } 11).label;
      };
      expected = {
        strictGood = 5;
        strictBad = "REFUSED";
        strictBadSibling = "REFUSED";
        lazyGood = 5;
        lazyBad = "REFUSED";
        lazyBadSibling = "w";
        ctlIntBad = "REFUSED";
        regArgLazyBadSibling = "w";
        allLazyBothSibling = "w";
      };
    };

    # ── in a kind: decisions that changed from RED ────────────────────────────────────────────
    # One strict refinement on a field makes construction decide its whole conjunction, lazy conjuncts
    # included, whatever the conjuncts' source (type or registry argument). RED read "w" on the first
    # four and -1 on the fifth.
    test-a-strict-conjunct-decides-the-field-at-construction = {
      expr = builtins.mapAttrs (_: tr) {
        mixedLazyBadSibling = (inKind mixedT null 11).label;
        mixedStrictBadSibling = (inKind mixedT null (-1)).label;
        regArgMixedLazyBadSibling =
          (inKind t.int {
            n = [
              pos
              (lazy lt10)
            ];
          } 11).label;
        shadowLazyArgFailsSibling = (inKind posT { n = [ (lazy lt10) ]; } 11).label;
        shadowStrictTypeLazyArgSibling = (inKind posT { n = [ (lazy lt10) ]; } (-1)).label;
        shadowStrictTypeLazyArgBad = (inKind posT { n = [ (lazy lt10) ]; } (-1)).n;
      };
      expected = {
        mixedLazyBadSibling = "REFUSED";
        mixedStrictBadSibling = "REFUSED";
        regArgMixedLazyBadSibling = "REFUSED";
        shadowLazyArgFailsSibling = "REFUSED";
        shadowStrictTypeLazyArgSibling = "REFUSED";
        shadowStrictTypeLazyArgBad = "REFUSED";
      };
    };
    # A registry argument replaces only the refinements no type carries: the type keeps its own, on
    # the plain path and on the mixin (bridge) path alike. RED read -1 on all but the control.
    test-a-registry-argument-cannot-drop-a-declared-refinement = {
      expr = builtins.mapAttrs (_: tr) {
        mixinNoArgBad = (inKindWith true posT null (-1)).n;
        mixinOtherArgBad = (inKindWith true posT { label = [ refinements.nonEmpty ]; } (-1)).n;
        mixinShadowBad = (inKindWith true posT { n = [ (lazy lt10) ]; } (-1)).n;
        plainOtherArgBad = (inKind posT { label = [ refinements.nonEmpty ]; } (-1)).n;
      };
      expected = {
        mixinNoArgBad = "REFUSED";
        mixinOtherArgBad = "REFUSED";
        mixinShadowBad = "REFUSED";
        plainOtherArgBad = "REFUSED";
      };
    };
    # A refined type nested under a container is enforced when the field is read (RED admitted it),
    # and, being no top-level conjunct of the field, does not make construction demand it.
    test-a-nested-refined-type-is-enforced-at-access = {
      expr = builtins.mapAttrs (_: tr) {
        nestNullOrBad = (inKind (t.nullOr posT) null (-1)).n;
        nestNullOrBadSibling = (inKind (t.nullOr posT) null (-1)).label;
        nestListBad =
          (inKind (t.listOf posT) null [
            4
            (-1)
          ]).n;
        nestListBadSibling =
          (inKind (t.listOf posT) null [
            4
            (-1)
          ]).label;
      };
      expected = {
        nestNullOrBad = "REFUSED";
        nestNullOrBadSibling = "w";
        nestListBad = "REFUSED";
        nestListBadSibling = "w";
      };
    };
    # An all-lazy field is not demanded by construction, so a lazy predicate that would force a part
    # nobody demanded does not run (RED applied it at construction and refused the sibling read).
    test-an-all-lazy-non-flat-field-is-not-forced-by-a-sibling-read = {
      expr = builtins.mapAttrs (_: tr) {
        nonflatAllLazySibling = (inKind (refined (t.lazyAttrsOf t.int) [ allLt10 ]) null unforced).label;
        nonflatStrictOnlySibling = (inKind (refined (t.lazyAttrsOf t.int) [ hasA ]) null unforced).label;
      };
      expected = {
        nonflatAllLazySibling = "w";
        nonflatStrictOnlySibling = "w";
      };
    };
  };

  flake.testsError.refined-membership-refusals = {
    test-outside-a-kind-refuses-by-name = {
      expr = outside posT (-1);
      expectedError = {
        type = "ThrownError";
        msg = "^gen-merge: a definition for option `o' is not of the expected type: must be positive";
      };
    };
    test-outside-a-kind-under-listOf-names-the-element = {
      expr = outside (t.listOf posT) [
        4
        (-1)
      ];
      expectedError = {
        type = "ThrownError";
        msg = "^gen-merge: a definition for option `o[.]\"\\[definition 1-entry 2\\]\"' is not of the expected type: must be positive";
      };
    };
    # `refined-identity`'s control: the same refinement declared twice merges, and the option refuses
    # the value it forbids.
    test-a-refinement-declared-twice-refuses-by-name = {
      expr =
        (genMerge.evalModuleTree { } [
          { options.probe = genMerge.mkOption { type = refined t.int [ refinements.tcpPort ]; }; }
          { options.probe = genMerge.mkOption { type = refined t.int [ refinements.tcpPort ]; }; }
          { config.probe = 70000; }
        ]).config.probe;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-merge: a definition for option `probe' is not of the expected type: must be a valid TCP port";
      };
    };
    test-the-first-failing-refinement-is-the-reason = {
      expr = outside (refined (t.either t.int t.str) [
        isInt
        pos
      ]) "x";
      expectedError = {
        type = "ThrownError";
        msg = "^gen-merge: a definition for option `o' is not of the expected type: must be an int";
      };
    };
    test-a-mixed-field-refuses-its-lazy-conjunct-at-construction = {
      expr = (inKind mixedT null 11).label;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-merge: a definition for option `widgets[.]w1[.]n' is not of the expected type: lt10";
      };
    };
    test-a-mixed-argument-refuses-at-construction = {
      expr =
        (inKind t.int {
          n = [
            pos
            (lazy lt10)
          ];
        } 11).label;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: refinement failed at widget:w1[.]n";
      };
    };
  };
}
