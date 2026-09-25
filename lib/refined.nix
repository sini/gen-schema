# Refinement contracts (§ Findler 2002, co-location from § Rondon 2008).
# Predicate metadata stored in __schema attr on gen-merge/gen-types types.
#
# `identity` is threaded in for the MINT (ADR-0034). It is taken as an injected leaf and
# CONSTRUCTED with — gen-schema does not re-export `hashIdentity`, which is the discipline
# `./id-hash.nix` and `./entry-type.nix` are already under and the reason ADR-0034's "no second
# minting authority" holds with the count of authorities still at one.
{
  merge,
  identity,
  preimageTagOf,
}:
let
  normalizeRefinements = r: if builtins.isList r then r else [ r ];

  # A refinement whose `check` is a REGISTERED construction (gen-algebra `mkIntensional`) enters
  # the preimage by its minted identity, read through gen-algebra's one reader of the tagged sum;
  # any other `check` enters as itself, so a caller lambda still reaches the encoder and is refused
  # there (ADR-0034's migration: minted once it is a term, a refusal until then).
  refinementPreimage =
    r:
    let
      tag = preimageTagOf identity.hashIdentity (r.check or null);
    in
    if tag ? minted then r // { check = tag; } else r;

  # A refined type is DERIVED from its base rather than described from scratch: it keeps the
  # base's value behaviour and adds the predicate metadata. That derivation still has to go
  # through the completion path. `baseType // { __schema = …; }` is an override over an already
  # completed type, and every field the override does not name still answers for the BASE —
  # including the two that rebuild it, `functor.type` (what typeMerge returns when an option is
  # declared twice) and `substSubModules`. Either path hands back the bare base with __schema
  # gone and the refinements silently unenforced, which is the fail-open answer this construction
  # exists to prevent. Re-completing WITHOUT the base's functor and typeMerge is what breaks the
  # inheritance. The relation stated below then answers the base's half by asking gen-merge's one
  # merge relation (`mergeTypes`), so the part of the decision that is gen-merge's stays gen-merge's
  # rather than becoming a copy of it living here.
  #
  # The FUNCTOR carries the distinguishing name; the type keeps the base's. They are separate
  # axes: `name` is the value vocabulary a refined int still speaks in its error messages, while
  # the functor name `refined<…>` is what a FOREIGN relation sees: a bare base asked to reconcile
  # with a refined partner compares that name and refuses, so from that side a refined type never
  # silently drops to its unrefined base. The relation below is NOT gated on the name; it decides
  # both components structurally (see its comment).
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
      # identity is a fixed width whatever it stands for — and onto gen-types' type-identity bound,
      # which `guard` below steps.
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
                refinements = map refinementPreimage normalized;
              };
            }
            .${l}
          );
      # ★ THIS CONSTRUCTOR MINTS OVER ITS BASE'S MINT, SO IT STEPS gen-types' TYPE-IDENTITY INDEX
      # ITSELF (`identityGuard`, reached through gen-merge's injected leaf vocabulary so the bound and
      # its refusal stay single-sourced). Passing the base's `__okAt` through unstepped is sound for a
      # cycle, which always crosses a gen-types composite, and unsound for depth: a chain of
      # refinements never meets a guarded node and overflows the stack about 830 deep, uncatchably.
      # A leaf vocabulary without the guard refuses by name here rather than as a missing attribute.
      guard =
        (merge.types.identityGuard
          or (throw "gen-schema: refined: the leaf vocabulary behind this gen-merge exports no `identityGuard`, so a refinement cannot bound its type nesting; wire a gen-types that exports it")
        )
          [ baseType ];
      attempt = if guard.ok then builtins.tryEval mint else { success = false; };

      functorName = "refined<${baseType.name or "?"}>";

      # THE MERGE RELATION, added BESIDE the functor rather than instead of it, applying the right
      # limb to EACH component. ADR-0034: "The limbs apply PER COMPONENT of distinguishing
      # content, not per thing — otherwise one sealed component drags a whole kind onto the
      # comparison limb." `refined` has two components and they sit on different limbs:
      #
      #   refinements — SEALED. Caller lambdas admit no total preimage, so this is the ruling's
      #                 "where it decides rather than mints, it compares the reified value itself"
      #                 under Nix `==`.
      #   baseType    — NOT sealed. It is a type that STATES ITS OWN MERGE RELATION, so the
      #                 relation is asked, through `merge.mergeTypes`. Taking `==` over the base
      #                 record instead would be "a copy of the relation living here", which this
      #                 file's header already rules out, and would refuse every base rebuilt per
      #                 declaration — `(listOf str) == (listOf str)` is `false` while
      #                 `mergeTypes (listOf str) (listOf str)` merges, because the base's own
      #                 relation compares the ELEMENT type rather than the container.
      #
      # THERE IS NO NAME GATE. `functorName` carries only the base's NAME, so gating on it would be
      # a second, name-keyed answer to the base question `mergeTypes` already answers structurally —
      # gen-merge README `### typeMergeRel` clause (b): keeping a copy of the relation "would answer
      # the question twice with two answers that could disagree". They do disagree wherever the
      # base's join legitimately RENAMES: a gen-native relation is free to answer a type keeping
      # neither operand's name, and a gated fold then refuses a third declaration the ungated one
      # still closes over (`ci/tests/refined-union.nix`'s `renameA`/`renameB`/`renameC` fixture).
      # nixpkgs' own check family no longer supplies a live example of that disagreement: gen-merge's
      # witness (`lib/interface.nix`) now refuses a foreign join that drops an operand's own name —
      # `ints.between` included — rather than silently renaming past it, so a name gate and the
      # witness would agree on every check-family pair, not disagree. What still keeps a refined type
      # and its BARE base apart: here, the `partner ? __schema` clause; in the foreign direction, the
      # published `functor.name` above, which the bare type's own relation compares and refuses.
      #
      # ★ THE MERGED TYPE IS THE BASE RELATION'S JOIN, REFINED AGAIN — never this declaration's own
      # `result`. A base relation that JOINS (two `submodule`s to one carrying both option sets, two
      # `enum`s to their union) would otherwise have its answer used only as a yes/no and the
      # partner's base dropped: silently in one presentation order, as an unrelated error in the
      # other (gen-merge README `### typeMergeRel` clause (a), "the type-level form of a dropped
      # definition"). The rebuilt type is itself a `mkRefinedType`, so the fold stays closed.
      #
      # ★ NO NAME GATE, AND NONE NEEDED FOR THE CHECK FAMILY: an addCheck-family base pair answers
      # what its BARE pair answers. gen-merge's foreign relation refuses a join that drops a name an
      # operand states, so `refined port ∥ refined int`, `refined ints.u8 ∥ refined ints.u16`,
      # `refined (between 0 1) ∥ refined int` and `refined (between 0 10) ∥ refined (between 100
      # 200)` all refuse as their bare pairs do, and one shared `between` value redeclared keeps
      # `intBetween`. A name gate here never guarded that class — the two `between` ranges share a
      # name — and the loss is fixed where it lives, in the bare relation, which repairs both
      # surfaces at once.
      #
      # ★★ THE BASE'S HALF IS `merge.mergeTypes`, the binding gen-merge's declaration and element
      # strata both answer through: the base's own `typeMergeRel` where it has one, and otherwise the
      # foreign protocol's own `a.typeMerge b.functor`, behind gen-merge's type-walk fuel guard. A RAW
      # NIXPKGS base is therefore discriminated at its PARAMETER — `refined (lib.types.listOf
      # lib.types.str) r` and `refined (lib.types.listOf lib.types.int) r` do not merge — exactly as
      # the same pair declared bare is refused. `examples/demo`'s network kind declares `refined
      # lib.types.str …` and `refined lib.types.int …`, so the foreign population is live.
      #
      # The property is PARITY: a refined pair whose refinements agree answers what its bare bases
      # answer under `mergeTypes`, so a refinement is never more mergeable than its base. Two
      # IDENTICAL foreign bases are refused where the base's own relation refuses them — a
      # `coercedTo` twin (its coercion is a caller lambda, and ADR-0034's sealed-component clause
      # replaces that component's collapse with a refusal), a `json` or `attrListOf` twin, and a
      # nest deeper than the fuel — because the bare pair is refused the same way. Copying the
      # foreign relation here instead would drop the fuel guard and answer the question twice.
      #
      # RESIDUE, stated rather than hidden: this relation can only answer `null`, so a refused
      # refined twin is reported with gen-merge's generic "functor does not reconcile" wording
      # even where the bare pair would name the exhausted fuel. The reason channel is gen-merge's
      # wording door, not this constructor's.
      relation =
        f:
        let
          partner = f.type or null;
        in
        if !(builtins.isAttrs partner && partner ? __schema) then
          null
        else if partner.__schema.refinements != normalized then
          null
        else
          let
            joined = merge.mergeTypes baseType partner.__schema.baseType;
          in
          if joined == null then null else mkRefinedType joined normalized;

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
          __id = if guard.ok then mint else guard.refusal;
          __okAt = guard.okAt;

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
