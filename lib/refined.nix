# Refinement contracts (§ Findler 2002, co-location from § Rondon 2008).
# Predicate metadata stored in __schema attr on gen-merge/gen-types types.
#
# `identity` is threaded in for the MINT (ADR-0034). It is taken as an injected leaf and
# CONSTRUCTED with — gen-schema does not re-export `hashIdentity`, which is the discipline
# `./id-hash.nix` and `./entry-type.nix` are already under and the reason ADR-0034's "no second
# minting authority" holds with the count of authorities still at one.
{ merge, identity }:
let
  normalizeRefinements = r: if builtins.isList r then r else [ r ];

  # A refined type is DERIVED from its base rather than described from scratch: it keeps the
  # base's value behaviour and adds the predicate metadata. That derivation still has to go
  # through the completion path. `baseType // { __schema = …; }` is an override over an already
  # completed type, and every field the override does not name still answers for the BASE —
  # including the two that rebuild it, `functor.type` (what typeMerge returns when an option is
  # declared twice) and `substSubModules`. Either path hands back the bare base with __schema
  # gone and the refinements silently unenforced, which is the fail-open answer this construction
  # exists to prevent. Re-completing WITHOUT the base's functor and typeMerge is what breaks the
  # inheritance. The relation stated below then answers the base's half by ASKING THE BASE
  # (`typeMergeRel`), so the part of the decision that is gen-merge's stays gen-merge's rather than
  # becoming a copy of it living here.
  #
  # The FUNCTOR carries the distinguishing name; the type keeps the base's. They are separate
  # axes: `name` is the value vocabulary a refined int still speaks in its error messages, while
  # the functor name is what a redeclaration is GATED on. That gate alone fails CLOSED between a
  # refined type and its bare base — "not mergeable", a stated conflict rather than a silent drop
  # to the unrefined type — but it carries only the BASE, so it cannot separate two DIFFERENT
  # refinements of one base. That pair is what the stated relation below decides, and leaving it to
  # the name alone is what let a refinement be silently dropped from a merged declaration.
  #
  # IDENTITY. A refinement's distinguishing content is a caller-supplied lambda, so ADR-0034 puts
  # this constructor on the arm where "that component's collapse is replaced by a refusal rather
  # than by a structural identity" until a first-order predicate vocabulary migrates. The base's
  # `__mint`/`__id` therefore join the removal list below: the inherited pair is never present to
  # be overwritten, so there is no shadowing order for a later reader to get wrong — the shape
  # `./id-hash.nix` argues for as "an expression with nowhere to attach".
  #
  # THE REGIME IS DECIDED BY THE MINT, never by a second predicate here. Nothing below asks
  # whether a refinement is a lambda. The encoder is total — it encodes or it refuses by name — so
  # handing it `args` and reading the answer IS the classification, and it cannot fall out of date
  # when a new refinement shape appears. The construction is `gen-types/lib/checkers.nix`'s
  # `mkChecker`, matched rather than re-authored, so the two implementations cannot drift apart on
  # the regime.
  mkRefinedType =
    baseType: refinements:
    let
      normalized = normalizeRefinements refinements;

      # The base enters the preimage as an IDENTITY, never as a value — `gen-types`' `idOf` is the
      # binding matched, and it is what keeps type NESTING off the encoder's depth bound, since an
      # identity is a fixed width whatever it stands for.
      #
      # ★ THE BASE HAS THREE STATES AND THE THIRD IS THE COMMON ONE, so the missing attribute is
      # refused HERE rather than left to an `or` that would name something false. Every structural
      # type gen-merge ships — `listOf`, `attrsOf`, `nullOr`, `either`, `submodule` — and every raw
      # nixpkgs type carries NO `__mint` key at all, which is a different fact from carrying the
      # tagged sum's sealed arm. "Carries no mint" is what is true of them; "has no mintable
      # identity" would suggest a sealed arm that is not there.
      baseIdentity =
        if !(baseType ? __mint) then
          throw "gen-schema: refined: base type `${baseType.name or "?"}' carries no mint at all, so a refinement of it has no base identity to compose from"
        else
          baseType.__mint.minted
            or (throw "gen-schema: refined: base type `${baseType.name or "?"}' has no mintable identity");

      mint =
        identity.hashIdentity "type"
          [
            "ctor"
            "args"
          ]
          (
            l:
            {
              ctor = "refined";
              args = {
                base = baseIdentity;
                refinements = normalized;
              };
            }
            .${l}
          );
      attempt = builtins.tryEval mint;

      functorName = "refined<${baseType.name or "?"}>";

      # THE MERGE RELATION, added BESIDE the functor rather than instead of it, applying the right
      # limb to EACH component. ADR-0034: "The limbs apply PER COMPONENT of distinguishing
      # content, not per thing — otherwise one sealed component drags a whole kind onto the
      # comparison limb." `refined` has two components and they sit on different limbs:
      #
      #   refinements — SEALED. Caller lambdas admit no total preimage, so this is the ruling's
      #                 "where it decides rather than mints, it compares the reified value itself"
      #                 under Nix `==`.
      #   baseType    — NOT sealed. It is a substrate-constructed type that ANSWERS ITS OWN MERGE
      #                 QUESTION, so it is asked: `typeMergeRel`. Taking `==` over the base record
      #                 instead would be "a copy of the relation living here", which this file's
      #                 header already rules out, and would refuse every base rebuilt per
      #                 declaration — `(listOf str) == (listOf str)` is `false` while
      #                 `(listOf str).typeMergeRel (listOf str)` answers `merged`, because the
      #                 base's own relation compares the ELEMENT type rather than the container.
      #
      # The NAME GATE stays this relation's first clause. Stating `typeMerge` replaces the
      # derivation `mkOptionType` would have supplied, so the name comparison `protoTypeMerge` did
      # becomes this relation's to make; it is what keeps a refined type and its BARE base from
      # reconciling, in both directions.
      #
      # ★★ A BASE CARRYING NO `typeMergeRel` FALLS BACK TO THE NAME GATE ALREADY PASSED — it neither
      # aborts nor refuses. The delegation target is gen-merge's SYNTHESISED field, and a RAW NIXPKGS
      # type has none: `examples/demo`'s own network kind declares `refined lib.types.str …` and
      # `refined lib.types.int …`, so the population is live and not hypothetical.
      #
      # Three candidates were measured over that population, and two are wrong.
      #   · a bare `baseType.typeMergeRel` is an evaluator abort about a missing attribute, raised at
      #     whatever forced it — neither a value nor a named refusal.
      #   · REFUSING, or comparing the reified base under Nix `==`, makes two IDENTICAL declarations
      #     over a foreign base REFUSE where the shipped constructor MERGED them. Measured: `refined
      #     lib.types.str [r]` against itself merges today and refuses under either; with `==` the
      #     nullary leaves survive only because nixpkgs shares them, while a foreign PARAMETRIC base
      #     rebuilt per declaration still refuses. That is a REGRESSION, not a tightening.
      #   · falling through to `result` is the FOREIGN PROTOCOL'S OWN DEFAULT for the population the
      #     protocol governs — `protoTypeMerge`'s name equality, which is exactly what this type got
      #     before a relation was stated. The decision stays gen-merge's rather than becoming a copy
      #     of it living here, which is this file's standing position.
      #
      # So for a foreign base the relation is "the names gate AND the refinements agree" — strictly
      # STRONGER than what shipped, never weaker, so it cannot refuse a pair whose content is
      # identical. And `==` is not owed here: ADR-0034 scopes the reified-value comparison to a SEALED
      # component, one whose distinguishing content is a caller-supplied lambda. That is the
      # REFINEMENTS, which do get it above. A foreign base is substrate-constructed and merely mute in
      # gen's protocol; handing it the sealed limb's remedy is the per-component error the ruling names
      # — "one sealed component drags a whole kind onto the comparison limb".
      #
      # RESIDUE, stated rather than hidden: a foreign PARAMETRIC base is still discriminated by NAME
      # alone, so `refined (lib.types.listOf lib.types.str) r` and `refined (lib.types.listOf
      # lib.types.int) r` merge. That is UNCHANGED from what shipped — this construction leaves that
      # population exactly as it found it — and closing it needs a published gen-merge door to adopt a
      # foreign type into the protocol, which does not exist (measured: no `importLeaf`, `importType`
      # or `interface` on gen-merge's public lib). A gen-merge base gets the full element-level
      # discrimination through the delegation below.
      relation =
        f:
        let
          partner = f.type or null;
        in
        if (f.name or null) != functorName then
          null
        else if !(builtins.isAttrs partner && partner ? __schema) then
          null
        else if partner.__schema.refinements != normalized then
          null
        else if !(baseType ? typeMergeRel) then
          result
        else if (baseType.typeMergeRel partner.__schema.baseType) ? merged then
          result
        else
          null;

      result = merge.mkOptionType (
        builtins.removeAttrs baseType [
          "functor"
          "typeMerge"
          "__mint"
          "__id"
        ]
        // {
          __schema = {
            refinements = normalized;
            baseType = baseType;
          };

          # `__mint` is the tagged sum `gen-algebra/lib/intensional.nix` authors, computed through
          # `tryEval`; `__id` is the SAME mint uncaught, so demanding an identity of a sealed
          # refined type IS the named refusal rather than a paraphrase kept in step by hand. A
          # reader dispatches on the TAG, never on the field's presence.
          __mint =
            if attempt.success then
              { minted = attempt.value; }
            else
              {
                unmintable = {
                  ctor = "refined";
                  reason = "the mint refuses this construction's arguments; demand `__id` for its named refusal";
                };
              };
          __id = mint;

          typeMerge = relation;
          # payload null is the honest shape for a metadata decoration: there is nothing to fold
          # when two of these meet, only an identity to agree on. A base whose own functor carries
          # a payload does not lose it — a refined type and its base never merge in the first place.
          functor = {
            name = functorName;
            type = result;
            payload = null;
            binOp = _a: _b: null;
          };
          # A base that carries no module set answers null to a substitution, and so does a
          # refinement of it — refining null would be a type where the base refused to give one.
          substSubModules =
            m:
            let
              substituted = if baseType ? substSubModules then baseType.substSubModules m else null;
            in
            if substituted == null then null else mkRefinedType substituted normalized;
        }
      );
    in
    result;

  getRefinements = type: if type ? __schema then type.__schema.refinements else [ ];

  isRefined = type: type ? __schema && type.__schema ? refinements;

  checkRefinements =
    fieldPath: type: value:
    let
      refs = getRefinements type;
    in
    builtins.filter (r: r != null) (
      builtins.map (
        r:
        if r.check value then
          null
        else
          {
            field = fieldPath;
            message = r.message;
            inherit value;
            lazy = r.lazy or false;
          }
      ) refs
    );

  refinements = {
    tcpPort = {
      check = self: self > 0 && self < 65536;
      message = "must be a valid TCP port (1-65535)";
    };
    nonEmpty = {
      check = self: self != "";
      message = "must not be empty";
    };
    positive = {
      check = self: self > 0;
      message = "must be positive";
    };
  };
in
{
  inherit
    mkRefinedType
    getRefinements
    isRefined
    checkRefinements
    refinements
    ;
  types.refined = mkRefinedType;
}
