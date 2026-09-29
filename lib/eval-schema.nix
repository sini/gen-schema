# The schema pass — kind inheritance resolved BEFORE evaluation, at gen-schema's own stratum.
#
# A kind is a node, an inheritance edge is a relation, and a kind may inherit only kinds frozen by
# a STRICTLY EARLIER pass (ADR-0016 ruling 7). The reference travels as a NAME — `inherits = [ "p" ]`
# — never as a value read out of the tree being declared, and that is the whole of what separates
# this from the `imports = [ config.schema.p ]` idiom it replaces (now refused): no `config` is
# read at any point below, so nothing here consumes its own stratum's in-flight output.
#
# The user-visible consequence is ruling 7's own: a structure two levels deep takes two passes.
{
  prelude,
  merge,
  mkSchemaOption,
}:
let
  # MIXED door (P1, den-hoag-7gp66): `modules` is required, `schemaOption`/`specialArgs` optional —
  # closed over the whole set, transitional until P2. The `assert` forces `checked` where the
  # record is applied: without it, the `if …` chain below happens to force `undeclared` (hence
  # `modules`) only because gen-merge's own `evalModuleTree` is strict enough to need it — an
  # incidental forcing this door does not want to depend on for its own catchability.
  evalSchema =
    args:
    let
      checked = prelude.checkOptions "gen-schema.evalSchema" [
        "modules"
        "schemaOption"
        "specialArgs"
      ] (prelude.checkRequired "gen-schema.evalSchema" [ "modules" ] args);
      inherit (checked) modules;
      # `null` rather than `mkSchemaOption { }` so "the caller supplied one" is a QUESTION THIS
      # FUNCTION CAN ASK. The resolved value is identical when nobody supplies one; what the sentinel
      # buys is the refusal below, which a defaulted record could not state.
      schemaOption = checked.schemaOption or null;
      # Base module args for the kind tree, forwarded into the schema option this builds. The surface
      # a consumer reaches first, so the channel is published here as well as on
      # `mkSchemaOption`/`mkSchemaEntryType` — one formal forwarded, never a second mechanism.
      specialArgs = checked.specialArgs or { };
    in
    assert builtins.isAttrs checked;
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

      # One evaluation of the schema tree. `injected` carries this pass's parent defs and is empty
      # at pass 0.
      evalAt =
        injected:
        (merge.evalModuleTree {
          modules = [ { options.schema = resolvedSchemaOption; } ] ++ modules ++ injected;
        }).config.schema;

      # Pass 0 freezes every kind that inherits nothing. Reading `.inherits` off it is safe on a
      # kind whose parents have not been injected yet: collections are extracted by the entry
      # type's own merge, which folds over defs directly and never enters the nested
      # evalModuleTree that `options`/`refs` come from.
      pass0 = evalAt [ ];
      kindNames = pass0._kindNames;
      # `or [ ]` for a custom `mkType` entry, whose result carries no collections at all — the
      # same fallback `_topology` takes on `parent`.
      parentsOf = k: pass0.${k}.inherits or [ ];

      undeclared = prelude.concatMap (
        k:
        map (p: "gen-schema: kind '${k}' inherits '${p}' which is not a declared kind") (
          prelude.filter (p: !(builtins.elem p kindNames)) (parentsOf k)
        )
      ) kindNames;

      # Depth over the NAME graph alone, so pass assignment is a function of the names and not of
      # presentation order — ruling 7's first staging obligation, discharged by construction
      # rather than asserted. Bounded iteration with the bound = the kind count: an acyclic graph
      # settles within it and a cyclic one does not, which is exactly the cycle test below.
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

      maxDepth = builtins.foldl' (a: k: if settled.${k} > a then settled.${k} else a) 0 kindNames;

      # One module per (kind, parent) pair, carrying the parent's value as frozen at pass n-1.
      #
      # It is IMPORTED rather than assigned bare. A bare `config.schema.<k> = prev.<p>` hands the
      # entry type the parent's own collections as well, so the child would inherit the parent's
      # `inherits` — a spurious `type = "inherits"` edge — and the parent's `parent`, whose merge
      # refuses a conflict outright.
      #
      # What is imported is the parent's MODULE, its `__functor` applied here, never its kind
      # value: a kind value in a kind entry's `imports` is the retired spelling, which the entry
      # type refuses (den-hoag-cxlc0). The module system applies a functor the same way, so nothing
      # composes differently. ★ The hand-applied functor is a member of that refusal's declared
      # exception (README, "The retired inheritance spelling"), and this injection composes through
      # it: a change that decided applied functors would refuse `evalSchema` too, so it moves this
      # first. A parent with no `__functor` (an `mkType` result that is not a module) has nothing
      # to compose and is refused by name.
      injectFor =
        prev: n:
        prelude.concatMap (
          k:
          if settled.${k} > n then
            [ ]
          else
            map (p: {
              config.schema.${k} = {
                imports = [
                  (
                    if prev.${p} ? __functor then
                      prev.${p}.__functor prev.${p}
                    else
                      throw "gen-schema: kind '${k}' inherits '${p}', whose kind value is not a module (its `mkType` result carries no `__functor`), so there is nothing to compose"
                  )
                ];
              };
            }) (parentsOf k)
        ) kindNames;
    in
    if undeclared != [ ] then
      throw (builtins.head undeclared)
    else if cyclic != [ ] then
      throw "gen-schema: inheritance cycle among kinds [${prelude.concatStringsSep " " cyclic}] — a kind may inherit only kinds resolved in a strictly earlier pass"
    else
      builtins.foldl' (prev: n: evalAt (injectFor prev n)) pass0 (
        if maxDepth == 0 then [ ] else prelude.range 1 maxDepth
      );
in
{
  inherit evalSchema;
}
