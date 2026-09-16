# The schema pass — kind inheritance resolved BEFORE evaluation, at gen-schema's own stratum.
#
# A kind is a node, an inheritance edge is a relation, and a kind may inherit only kinds frozen by
# a STRICTLY EARLIER pass (ADR-0016 ruling 7). The reference travels as a NAME — `inherits = [ "p" ]`
# — never as a value read out of the tree being declared, and that is the whole of what separates
# this from the `imports = [ config.schema.p ]` idiom it replaces: no `config` is read at any point
# below, so nothing here consumes its own stratum's in-flight output.
#
# The user-visible consequence is ruling 7's own: a structure two levels deep takes two passes.
{
  prelude,
  merge,
  mkSchemaOption,
}:
let
  evalSchema =
    {
      modules,
      schemaOption ? mkSchemaOption { },
    }:
    let
      # One evaluation of the schema tree. `injected` carries this pass's parent defs and is empty
      # at pass 0.
      evalAt =
        injected:
        (merge.evalModuleTree {
          modules = [ { options.schema = schemaOption; } ] ++ modules ++ injected;
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
      # refuses a conflict outright. Wrapped, the module system applies the value through its
      # `__functor` exactly as `imports = [ config.schema.<p> ]` does today.
      injectFor =
        prev: n:
        prelude.concatMap (
          k:
          if settled.${k} > n then
            [ ]
          else
            map (p: {
              config.schema.${k} = {
                imports = [ prev.${p} ];
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
