# den-hoag-6b5ia. `kindEq` compares a sealed component holding type records through gen-merge's
# `closuresFirst`, so two kinds whose option, freeform or keySemantics facet is typed by two
# constructions of one check-only `mkOptionType` are refused BY NAME. Before it, the bare `==` over
# the two cyclic records recursed until the evaluator aborted, uncatchably, whenever `==` reached the
# back-edge before a difference.
#
# ★ THE DISCRIMINATOR CARRIES ITS BACK-EDGE UNDER `description`, a key the evaluator interns at
# startup, so `==` reaches it before any closure in every context: a pair of plain records answers
# or aborts depending on what text was parsed first, and would not red here. A
# `declarationOf`-carrying type sits in two sealed components, the option's `type` and `refs.x`; `hasRefsSubject` names `refs.x` in this
# file's text, which interns it at parse, ahead of `options.x.type`, so `==` meets the refs component
# first. Each cell answers `true`, `false` or REFUSED under tryEval; the twins share one construction
# and must stay `true`.
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption kindEq;
  T = genMerge.types;
  kindIn =
    args: decl:
    (genMerge.evalModuleTree {
      modules = [
        { options.schema = mkSchemaOption args; }
        { config.schema.host = decl; }
      ];
    }).config.schema.host;
  verdict =
    a: b:
    let
      r = builtins.tryEval (kindEq a b);
    in
    if r.success then r.value else "REFUSED";
  tension =
    _:
    let
      back = {
        self = back;
      };
    in
    T.mkOptionType {
      name = "tension";
      description = back;
      check = v: builtins.isInt v && v < 10;
    };
  shared = tension null;
  refTension = tag: tension tag // { refKind = "host"; };
  sharedRef = refTension null;
  optionKind = ty: kindIn { } { options.x = genMerge.mkOption { type = ty; }; };
  freeformKind = ty: kindIn { } { freeformType = ty; };
  facetKind =
    ty:
    kindIn {
      keySemantics.k = {
        category = "facet";
        option = genMerge.mkOption { type = ty; };
      };
    } { };
in
{
  flake.tests.kind-eq-typed-components = {
    test-two-constructions-refuse = {
      expr = {
        option = verdict (optionKind (tension 1)) (optionKind (tension 2));
        freeform = verdict (freeformKind (tension 1)) (freeformKind (tension 2));
        facet = verdict (facetKind (tension 1)) (facetKind (tension 2));
        declarationOf = verdict (optionKind (genSchema.declarationOf "host")) (
          optionKind (genSchema.declarationOf "host")
        );
        refs = verdict (optionKind (refTension 1)) (optionKind (refTension 2));
        hasRefsSubject = (optionKind sharedRef).__sealed ? "refs.x";
      };
      expected = {
        option = "REFUSED";
        freeform = "REFUSED";
        facet = "REFUSED";
        declarationOf = "REFUSED";
        refs = "REFUSED";
        hasRefsSubject = true;
      };
    };

    # One construction shared by both kinds is one kind: a subject that refuses everything reds this.
    test-one-construction-is-one-kind = {
      expr = {
        option = verdict (optionKind shared) (optionKind shared);
        freeform = verdict (freeformKind shared) (freeformKind shared);
        facet = verdict (facetKind shared) (facetKind shared);
        refs = verdict (optionKind sharedRef) (optionKind sharedRef);
      };
      expected = {
        option = true;
        freeform = true;
        facet = true;
        refs = true;
      };
    };

    # A position declared to hold a type can hold a string (`type = "gauge"`, the NixOS spelling): it
    # has no closures, so the value decides. Were it handed to `intersectAttrs` as a record, the
    # evaluator would abort past `tryEval` (☢️).
    test-a-string-type-answers = {
      expr = {
        option = verdict (optionKind "gauge") (optionKind "gauge");
        freeform = verdict (freeformKind "gauge") (freeformKind "gauge");
        facet = verdict (facetKind "gauge") (facetKind "gauge");
      };
      expected = {
        option = true;
        freeform = true;
        facet = true;
      };
    };
  };
}
