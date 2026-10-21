# The schema pass — kind inheritance resolved BEFORE evaluation, at gen-schema's own stratum.
#
# A kind is a node, an inheritance edge is a relation, and a kind may inherit only kinds strictly
# earlier in the inheritance name graph. That is ADR-0016 ruling 7 applied by ANALOGY: the ruling
# governs a binding's relata (ADR-0033's ledger reading, 2026-09-22), and `inherits` is a
# payload-free edge, not a binding. The graph is read off a names-only evaluation and refused by name
# if it is cyclic. The reference travels as a NAME — `inherits = [ "p" ]` — never as a value read out
# of the tree being declared, and that is the whole of what separates this from the
# `imports = [ config.schema.p ]` idiom it replaces (now deprecated, and read as `inherits` with a
# warning).
#
# The tree is then evaluated ONCE, with each declared parent injected from that same evaluation, so
# every kind is one construction (ADR-0012: a module however often imported is one node), whoever
# reads it and however deep the reader. That is the knot the plain-tree desugar already ties (the
# owner-ruled 8c8pr Q-a, "C, desugar form"); this keeps the resolver's provenance. ADR-0033: the one
# evaluation reads its own output, as the desugar does, and a cycle is refused by name before it is
# forced, by the name-graph check below and again by the entry type's witness walk.
{
  prelude,
  merge,
  mkSchemaOption,
  inheritsResolvedFile,
  inheritedModule,
}:
let
  # OPTIONS FIRST, `modules` LAST (den-hoag-7gp66 P2, R7, as gen-merge's `evalModuleTree`):
  # `evalSchema { schemaOption?; specialArgs?; } modules`. The options are one closed set, a
  # `prelude.door` refused by name and catchably at `evalSchema opts`'s own WHNF, so `evalSchema
  # { specialArgs = …; }` is a value a caller can map over module lists. The module list is the
  # subject, a positional operand with no field contract.
  evalSchema = prelude.door {
    name = "gen-schema.evalSchema";
    optional = [
      "schemaOption"
      "specialArgs"
    ];
  } evalSchemaCore;
  evalSchemaCore =
    checked: modules:
    let
      # `null` rather than `mkSchemaOption { }` so "the caller supplied one" is a QUESTION THIS
      # FUNCTION CAN ASK. The resolved value is identical when nobody supplies one; what the sentinel
      # buys is the refusal below, which a defaulted record could not state.
      schemaOption = checked.schemaOption or null;
      # Base module args for the kind tree, forwarded into the schema option this builds. The surface
      # a consumer reaches first, so the channel is published here as well as on
      # `mkSchemaOption`/`mkSchemaEntryType` — one formal forwarded, never a second mechanism.
      specialArgs = checked.specialArgs or { };
    in
    let
      # ★ THE TWO TOGETHER ARE REFUSED BY NAME, because they are a SILENT LOSS. A caller-supplied
      # `schemaOption` is already built and its entry type has already closed over whatever args it
      # was given, so args stated here would be threaded nowhere and the kind tree would diverge
      # exactly as if none had been supplied — the very failure this channel exists to remove,
      # reappearing at the one call that states both. Refused where the caller states it, which is
      # the same discipline `withArgs` applies to a reserved key.
      resolvedSchemaOption =
        if schemaOption == null then
          mkSchemaOption { inherit specialArgs; }
        else if specialArgs != { } then
          throw (
            "gen-schema: `evalSchema' was given both `schemaOption' and `specialArgs'. The schema "
            + "option supplied here is already built, so those args would reach no kind tree; state "
            + "them where it is constructed instead — `mkSchemaOption { specialArgs = …; }'"
          )
        else
          schemaOption;

      # One evaluation of the schema tree. `injected` carries the resolver's parent defs and is empty
      # for the names-only read.
      evalAt =
        injected:
        (merge.evalModuleTree { } ([ { options.schema = resolvedSchemaOption; } ] ++ modules ++ injected))
        .config.schema;

      # THE NAMES READ: the tree with no parent injected, read for kind names and `inherits` only,
      # never composed. Reading `.inherits` off it is safe: collections are extracted by the entry
      # type's own merge, which folds over defs directly and never enters the nested evalModuleTree
      # that `options`/`refs` come from.
      names = evalAt [ ];
      kindNames = names._kindNames;
      # Every kind value carries `inherits`: the entry type writes it on both branches. A VALUE entry
      # (a foreign kind, den-hoag-l0y) is already minted, so it is strictly earlier and stages
      # nothing: the entry type composes it, and the name graph reads names only.
      parentsOf = k: builtins.filter builtins.isString names.${k}.inherits;

      undeclared = prelude.concatMap (
        k:
        map (p: "gen-schema: kind '${k}' inherits '${p}' which is not a declared kind") (
          prelude.filter (p: !(builtins.elem p kindNames)) (parentsOf k)
        )
      ) kindNames;

      # Depth over the NAME graph alone, a function of the names and not of presentation order. It
      # feeds only the cycle test: bounded iteration with the bound = the kind count, where an acyclic
      # graph settles within it and a cyclic one does not.
      step =
        d:
        prelude.genAttrs kindNames (
          k:
          let
            ps = parentsOf k;
          in
          if ps == [ ] then 0 else 1 + builtins.foldl' (a: p: if d.${p} > a then d.${p} else a) 0 ps
        );

      settled = builtins.foldl' (d: _: step d) (prelude.genAttrs kindNames (_: 0)) kindNames;
      once = step settled;
      cyclic = prelude.filter (k: once.${k} != settled.${k}) kindNames;

      # One module per (kind, parent) pair, carrying the parent's ONE construction: the kind the tree
      # this function returns holds (ADR-0012). The tree is evaluated once, so a kind is built once
      # and every reader of it (a child's injected parent, a value another kind reads off
      # `config.schema`, the tree returned, the deprecated spelling) holds that one value, however
      # deep the reader. Well-founded by the name graph checked above: the injection reads a parent's
      # construction only, and that reads only its own ancestors' injections. A read of a child that
      # the parent's own author writes is theirs, served or refused as on a plain tree.
      #
      # It is IMPORTED rather than assigned bare. A bare `config.schema.<k> = prev.<p>` hands the
      # entry type the parent's own collections as well, so the child would inherit the parent's
      # `inherits` — a spurious `type = "inherits"` edge — and the parent's `parent`, whose merge
      # refuses a conflict outright.
      #
      # What is imported is the parent's MODULE, its `__functor` applied here, never its kind
      # value: a kind value in a kind entry's `imports` is the deprecated spelling, which the entry
      # type reads as `inherits` and warns on (den-hoag-cxlc0). Injecting the kind value would make
      # every declared `inherits` warn on this pass's own injection. The module system applies a
      # functor the same way, so nothing composes differently. ★ The hand-applied functor is a
      # member of that alias's declared exception (README, "The deprecated inheritance spelling"),
      # and this injection composes through it: a change that decided applied functors would make
      # `evalSchema` warn too, so it moves this first. A parent with no `__functor` (an `mkType` result that is not a module) has nothing
      # to compose and is refused by name.
      injectFor =
        tree:
        prelude.concatMap (
          k:
          map (p: {
            # the resolver's provenance: the kind entry reads it to tell a resolved parent from one
            # nothing read (den-hoag-8c8pr)
            _file = inheritsResolvedFile k p;
            config.schema.${k} = {
              imports = [ (inheritedModule k p tree.${p}) ];
            };
          }) (parentsOf k)
        ) kindNames;

      # The tree, evaluated once with every declared parent injected from itself. With no parent
      # declared there is nothing to inject, and the names read is that one evaluation.
      injected = injectFor resolved;
      resolved = if injected == [ ] then names else evalAt injected;
    in
    if undeclared != [ ] then
      throw (builtins.head undeclared)
    else if cyclic != [ ] then
      # "pass" here is a stratum of the name graph: the wording is shared with the entry type's
      # witness walk and pinned in the error plane.
      throw
        "gen-schema: inheritance cycle among kinds [${prelude.concatStringsSep " " cyclic}] — a kind may inherit only kinds resolved in a strictly earlier pass"
    else
      resolved;
in
{
  inherit evalSchema;
}
