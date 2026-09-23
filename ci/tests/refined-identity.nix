# A refined type's IDENTITY and its MERGE RELATION — the two axes on which a refinement used to be
# invisible.
#
# THE CLASS. `mkRefinedType` derives its result from the base, and what it does not overwrite arrives
# from the base verbatim. Two things arrived that way: the base's `__mint`/`__id`, so two DIFFERENT
# refinements of one base shared an identity with each other AND with the bare base while the `__id`
# demand still ANSWERED; and the merge decision, taken on `functor.name` alone, which carries only
# the base — so one option declared once as `refined int tcpPort` and once as `refined int positive`
# MERGED, with one refinement silently dropped and the value it forbade then accepted.
#
# ADR-0034 admits two states for a component whose distinguishing content is a caller lambda:
# migrated, or "that component's collapse is replaced by a refusal rather than by a structural
# identity". A silently-collapsing identity that answers is neither, which is what these cells pin.
#
# ★ THE `.success` ARM IS WHY THIS IS NOT AN "IT ANSWERED" CELL. Reading `a.__id != b.__id` would
# pass today for the wrong reason the moment the mint changed shape, and would also pass a refusal.
# Asserting `.success == false` TOGETHER WITH `__mint ? unmintable` pins the REGIME rather than the
# answer — "the ids differ" is a different and weaker claim than "the comparison refuses".
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  t = genMerge.types;
  inherit (genSchema) refined refinements checkRefinements;

  L = t.listOf t.str;

  # Whether a demand ANSWERS at all, as distinct from what it answers.
  answers = x: (builtins.tryEval (builtins.seq x null)).success;

  regime =
    ty:
    if ty.__mint ? minted then
      "minted"
    else if ty.__mint ? unmintable then
      "unmintable"
    else
      "OTHER";

  # ── the evalModuleTree entry: one option DECLARED TWICE ──────────────────────────────────────
  # `deepSeq` inside the wrapper is load-bearing: `tryEval` stops at WHNF, so a list whose element
  # throws would escape it and land outside the cell.
  redeclare =
    tA: tB:
    let
      attempt = builtins.tryEval (
        let
          opt =
            (genMerge.evalModuleTree {
              modules = [
                { options.probe = genMerge.mkOption { type = tA; }; }
                { options.probe = genMerge.mkOption { type = tB; }; }
              ];
            }).options.probe;
          msgs = map (r: r.message) (opt.type.__schema.refinements or [ ]);
        in
        builtins.deepSeq msgs msgs
      );
    in
    if attempt.success then
      {
        answer = "merged";
        survivors = attempt.value;
      }
    else
      {
        answer = "refused";
        survivors = [ ];
      };

  # ── the DIRECT `t.typeMerge f` entry, which no redeclare pair above reaches ──────────────────
  direct =
    a: b:
    let
      r = a.typeMerge b.functor;
    in
    if r == null then
      {
        answer = "null";
        survivors = [ ];
      }
    else
      {
        answer = "merged";
        survivors = map (x: x.message) r.__schema.refinements;
      };
in
{
  flake.tests.refined-identity = {
    # ── O1 · the identity regime ──────────────────────────────────────────────────────────────
    test-refined-does-not-inherit-the-bases-identity = {
      expr =
        let
          a = refined t.int [ refinements.tcpPort ];
          b = refined t.int [ refinements.positive ];
        in
        {
          mintIsSealed = a.__mint ? unmintable;
          sealedCtor = a.__mint.unmintable.ctor;
          idDemandAnswers = answers a.__id;
          twoRefinementsCompare = answers (a.__id == b.__id);
          refinementVsBaseCompares = answers (a.__id == t.int.__id);
        };
      expected = {
        mintIsSealed = true;
        sealedCtor = "refined";
        idDemandAnswers = false;
        twoRefinementsCompare = false;
        refinementVsBaseCompares = false;
      };
    };

    # A refined type over a PARAMETRIC base reaches the same outcome by a different route: every
    # structural type gen-merge ships carries no `__mint` AT ALL, so the base has no identity to
    # contribute and the composite cannot mint even with inert refinements.
    test-refined-over-a-parametric-base-is-sealed-too = {
      expr = {
        parametric = regime (refined L [ refinements.nonEmpty ]);
        nullary = regime (refined t.int [ refinements.tcpPort ]);
      };
      expected = {
        parametric = "unmintable";
        nullary = "unmintable";
      };
    };

    # ── O1's live controls: the mint is not dead, and `unmintable` is ATTRIBUTABLE ─────────────
    # An INERT refinement set — no `check`, so no lambda — MINTS over a nullary base and its `__id`
    # ANSWERS, and two inert sets SEPARATE. The same inert set over a PARAMETRIC base reads
    # `unmintable`, which attributes that reading to the base's missing mint rather than to the
    # predicate. Without these, every row above is satisfied by a constructor that refuses
    # everything.
    test-control-an-inert-refinement-still-mints-and-separates = {
      expr =
        let
          one = refined t.int [ { message = "inert"; } ];
          two = refined t.int [ { message = "inert-two"; } ];
        in
        {
          mints = regime one;
          idAnswers = answers one.__id;
          separates = one.__id != two.__id;
          overParametricBase = regime (refined L [ { message = "inert"; } ]);
        };
      expected = {
        mints = "minted";
        idAnswers = true;
        separates = true;
        overParametricBase = "unmintable";
      };
    };

    # ── O2 · the merge relation at the `evalModuleTree` entry ──────────────────────────────────
    # Rows 1-3 must MERGE with refinements intact, rows 4-5 must REFUSE, and rows 6-8 refuse in
    # BOTH the broken and the fixed state — so a relation that refused everything fails 1-3 and one
    # that merged everything fails 4-5. `L` is written PER DECLARATION on purpose: the base record
    # is rebuilt each time, and a relation taking `==` over it would refuse row 3, which is a
    # REGRESSION rather than a tightening. The base's own relation is asked instead.
    test-redeclaration-merges-on-the-same-refinements = {
      expr =
        let
          shared = refined t.int [ refinements.tcpPort ];
        in
        {
          sameLetBound = redeclare shared shared;
          twoOverNullary = redeclare (refined t.int [ refinements.tcpPort ]) (
            refined t.int [ refinements.tcpPort ]
          );
          # ★ THE PARAMETRIC BASE IS WRITTEN OUT TWICE ON PURPOSE, not bound once and reused. A
          # shared binding makes this row pass under a relation taking `==` over the base record,
          # because both sides are then the same pointer — so the row would stop discriminating
          # against exactly the mechanism it exists to rule out. Written per declaration the record
          # is rebuilt, `==` answers `false`, and only asking the base its own relation merges it.
          twoOverParametric = redeclare (refined (t.listOf t.str) [ refinements.nonEmpty ]) (
            refined (t.listOf t.str) [ refinements.nonEmpty ]
          );
        };
      expected = {
        sameLetBound = {
          answer = "merged";
          survivors = [ "must be a valid TCP port (1-65535)" ];
        };
        twoOverNullary = {
          answer = "merged";
          survivors = [ "must be a valid TCP port (1-65535)" ];
        };
        twoOverParametric = {
          answer = "merged";
          survivors = [ "must not be empty" ];
        };
      };
    };

    test-redeclaration-refuses-two-different-refinements-of-one-base = {
      expr = {
        nullaryBase = redeclare (refined t.int [ refinements.tcpPort ]) (
          refined t.int [ refinements.positive ]
        );
        parametricBase = redeclare (refined L [ refinements.nonEmpty ]) (
          refined L [ refinements.positive ]
        );
      };
      expected = {
        nullaryBase = {
          answer = "refused";
          survivors = [ ];
        };
        parametricBase = {
          answer = "refused";
          survivors = [ ];
        };
      };
    };

    # The in-cell controls: these three refuse in BOTH states, so they show the entry is reached and
    # the pairs are distinguishable rather than the relation being uniformly closed.
    test-control-redeclaration-refuses-across-different-bases = {
      expr = {
        differentElement = redeclare (refined L [ refinements.nonEmpty ]) (
          refined (t.listOf t.int) [ refinements.nonEmpty ]
        );
        differentBase = redeclare (refined t.int [ refinements.tcpPort ]) (
          refined t.str [ refinements.positive ]
        );
        refinedVersusBare = redeclare (refined t.int [ refinements.tcpPort ]) t.int;
      };
      expected = {
        differentElement = {
          answer = "refused";
          survivors = [ ];
        };
        differentBase = {
          answer = "refused";
          survivors = [ ];
        };
        refinedVersusBare = {
          answer = "refused";
          survivors = [ ];
        };
      };
    };

    # ── O2b · the DIRECT entry, which no O2 pair reaches ──────────────────────────────────────
    # `evalModuleTree` routes through `redeclareDecl`; nixpkgs' own redeclaration path asks one type
    # to merge the other's FUNCTOR directly, and `type-answer-ownership.nix` already tests that
    # entry. The defect lived at both, so the oracle covers both. Rows 3-4 are
    # `test-refined-does-not-merge-with-its-bare-base`'s two pinned data, unchanged in both states,
    # and they are why the functor NAME is preserved rather than moved off.
    test-refined-direct-typemerge-discriminates-the-refinements = {
      expr =
        let
          port = refined t.int [ refinements.tcpPort ];
        in
        {
          differentRefinement = direct port (refined t.int [ refinements.positive ]);
          sameRefinement = direct port (refined t.int [ refinements.tcpPort ]);
          refinedFirst = direct port t.int;
          bareFirst = direct t.int port;
          differentBase = direct port (refined t.str [ refinements.positive ]);
        };
      expected = {
        differentRefinement = {
          answer = "null";
          survivors = [ ];
        };
        sameRefinement = {
          answer = "merged";
          survivors = [ "must be a valid TCP port (1-65535)" ];
        };
        refinedFirst = {
          answer = "null";
          survivors = [ ];
        };
        bareFirst = {
          answer = "null";
          survivors = [ ];
        };
        differentBase = {
          answer = "null";
          survivors = [ ];
        };
      };
    };

    # The fixpoint case: a refined type's base may itself be refined, and the delegation then asks
    # THIS relation rather than the shipped one. All three nested pairs were wrong before — the
    # inner-differing pair merged — so the recursion is what closes them.
    test-nested-refinement-discriminates-at-both-depths = {
      expr =
        let
          rel =
            a: b:
            let
              r = a.typeMergeRel b;
            in
            if r ? merged then
              "merged"
            else if r ? refused then
              "refused"
            else
              "OTHER";
          innerPositive = refined t.int [ refinements.positive ];
          innerTcp = refined t.int [ refinements.tcpPort ];
        in
        {
          innerDiffers = rel (refined innerPositive [ refinements.tcpPort ]) (
            refined innerTcp [ refinements.tcpPort ]
          );
          outerDiffers = rel (refined innerPositive [ refinements.tcpPort ]) (
            refined innerPositive [ refinements.positive ]
          );
          identical = rel (refined innerPositive [ refinements.tcpPort ]) (
            refined innerPositive [ refinements.tcpPort ]
          );
        };
      expected = {
        innerDiffers = "refused";
        outerDiffers = "refused";
        identical = "merged";
      };
    };

    # ── O3 · the VALUE-level fail-open, asserted as a value ───────────────────────────────────
    # O1 and O2b can both be green while a refinement goes unenforced, because neither ever defines
    # a value. Declaring one option as `refined int tcpPort` and as `refined int positive` used to
    # merge with `tcpPort` dropped, and `70000` — which `tcpPort` forbids — was then ACCEPTED with
    # `checkRefinements` returning `[ ]`. Now the declaration refuses before any value is produced.
    #
    # The control is the other arm, and it is what makes this non-vacuous: the SAME refinement
    # declared twice merges, the value is produced, and `70000` VIOLATES it. So a construction that
    # refused every declaration fails the control, and a `checkRefinements` that had stopped
    # checking fails it too.
    test-dropped-refinement-cannot-accept-the-value-it-forbade = {
      expr =
        let
          declare =
            tA: tB:
            let
              attempt = builtins.tryEval (
                let
                  tree = genMerge.evalModuleTree {
                    modules = [
                      { options.probe = genMerge.mkOption { type = tA; }; }
                      { options.probe = genMerge.mkOption { type = tB; }; }
                      { config.probe = 70000; }
                    ];
                  };
                  violations = map (x: x.message) (
                    checkRefinements "probe" tree.options.probe.type tree.config.probe
                  );
                in
                builtins.deepSeq violations violations
              );
            in
            if attempt.success then
              {
                answer = "declared";
                violations = attempt.value;
              }
            else
              {
                answer = "refused";
                violations = [ ];
              };
        in
        {
          twoDifferentRefinements = declare (refined t.int [ refinements.tcpPort ]) (
            refined t.int [ refinements.positive ]
          );
          control = declare (refined t.int [ refinements.tcpPort ]) (refined t.int [ refinements.tcpPort ]);
        };
      expected = {
        twoDifferentRefinements = {
          answer = "refused";
          violations = [ ];
        };
        control = {
          answer = "declared";
          violations = [ "must be a valid TCP port (1-65535)" ];
        };
      };
    };

    # ── a base with no `typeMergeRel` keeps the foreign protocol's own relation ────────────────
    # The base's half is answered by `genMerge.mergeTypes`. A RAW NIXPKGS type carries no
    # `typeMergeRel`, so it is answered by its own `typeMerge` over the partner's functor — the
    # foreign protocol's default for exactly the types that protocol governs. `examples/demo`'s
    # network kind declares `refined lib.types.str …` and `refined lib.types.int …`, so the
    # population is live. Identical content whose bare pair merges must merge here too.
    test-a-base-with-no-merge-relation-keeps-the-protocol-default = {
      expr =
        let
          f = lib.types;
        in
        {
          # A foreign NULLARY base, written per declaration: identical content, so it must MERGE with
          # the refinement intact. Refusing here — or comparing the reified base under `==`, which
          # only survives because nixpkgs shares its nullary leaves — is a regression on the shipped
          # constructor, which merged this pair.
          foreignNullary = direct (refined f.int [ refinements.tcpPort ]) (
            refined f.int [ refinements.tcpPort ]
          );
          # A foreign PARAMETRIC base, rebuilt per declaration. This is the row a reified `==` gets
          # WRONG: the two records are not the same value, so `==` refuses a pair the shipped
          # constructor merged.
          foreignParametric = direct (refined (f.listOf f.str) [ refinements.nonEmpty ]) (
            refined (f.listOf f.str) [ refinements.nonEmpty ]
          );
          # THE FIX STILL HOLDS over the foreign population: the refinements half is decided here
          # regardless of whether the base can answer.
          foreignDifferentRefinement = direct (refined f.int [ refinements.tcpPort ]) (
            refined f.int [ refinements.positive ]
          );
          # CONTROL, same instrument: a gen-merge base is answered by its own `typeMergeRel`, which
          # discriminates at the element type. The two vocabularies sit side by side, so a
          # construction that collapsed them fails one of these rows.
          genMergeTwin = direct (refined (t.listOf t.str) [ refinements.nonEmpty ]) (
            refined (t.listOf t.str) [ refinements.nonEmpty ]
          );
          genMergeDifferentElement = direct (refined (t.listOf t.str) [ refinements.nonEmpty ]) (
            refined (t.listOf t.int) [ refinements.nonEmpty ]
          );
        };
      expected = {
        foreignNullary = {
          answer = "merged";
          survivors = [ "must be a valid TCP port (1-65535)" ];
        };
        foreignParametric = {
          answer = "merged";
          survivors = [ "must not be empty" ];
        };
        foreignDifferentRefinement = {
          answer = "null";
          survivors = [ ];
        };
        genMergeTwin = {
          answer = "merged";
          survivors = [ "must not be empty" ];
        };
        genMergeDifferentElement = {
          answer = "null";
          survivors = [ ];
        };
      };
    };

    # ── a FOREIGN base is asked through gen-merge's one merge relation ────────────────────────
    # The base's half is `genMerge.mergeTypes`, the binding gen-merge's declaration and element
    # strata both answer through: the base's own `typeMergeRel` where it has one, the foreign
    # protocol's own `typeMerge` over the partner's functor where it has not. A raw nixpkgs
    # container is therefore discriminated at its PARAMETER, exactly as it is when declared bare.
    test-a-foreign-parametric-base-is-discriminated-at-its-parameter = {
      expr =
        let
          f = lib.types;
        in
        {
          # the row this cell exists for: same container, same refinement, different element
          foreignDifferentElement = direct (refined (f.listOf f.str) [ refinements.nonEmpty ]) (
            refined (f.listOf f.int) [ refinements.nonEmpty ]
          );
          # one level down, so a relation that stopped at the outer container fails it
          foreignDifferentNestedElement = direct (refined (f.attrsOf (f.listOf f.str)) [
            refinements.nonEmpty
          ]) (refined (f.attrsOf (f.listOf f.int)) [ refinements.nonEmpty ]);
          # a twin rebuilt per declaration still merges, with the refinement intact
          foreignTwin = direct (refined (f.attrsOf (f.listOf f.str)) [ refinements.nonEmpty ]) (
            refined (f.attrsOf (f.listOf f.str)) [ refinements.nonEmpty ]
          );
          # a base that refuses its OWN twin is refused under a refinement too: `coercedTo` carries a
          # caller function nixpkgs' relation will not compare, and the bare pair refuses the same way
          foreignBaseRefusingItsTwin = direct (refined (f.coercedTo f.int toString f.str) [
            refinements.nonEmpty
          ]) (refined (f.coercedTo f.int toString f.str) [ refinements.nonEmpty ]);
        };
      expected = {
        foreignDifferentElement = {
          answer = "null";
          survivors = [ ];
        };
        foreignDifferentNestedElement = {
          answer = "null";
          survivors = [ ];
        };
        foreignTwin = {
          answer = "merged";
          survivors = [ "must not be empty" ];
        };
        foreignBaseRefusingItsTwin = {
          answer = "null";
          survivors = [ ];
        };
      };
    };

    # ── §2.5 · what does NOT change, so the readers of `__schema` are shown untouched ──────────
    test-refinement-checking-is-unchanged = {
      expr =
        let
          rp = refined t.int [ refinements.positive ];
        in
        {
          violated = map (v: v.message) (checkRefinements "n" rp (-3));
          clean = checkRefinements "n" rp 5;
          refinementCount = builtins.length rp.__schema.refinements;
          baseName = rp.__schema.baseType.name;
        };
      expected = {
        violated = [ "must be positive" ];
        clean = [ ];
        refinementCount = 1;
        baseName = "int";
      };
    };
  };
}
