# Refinement contracts (§ Findler 2002, co-location from § Rondon 2008).
# Predicate metadata stored in __schema attr on gen-merge/gen-types types.
#
# The type's IDENTITY is built through gen-types' exported identity half (`mkIdentity`, reached
# through gen-merge's injected leaf vocabulary), so a refined type here is identified by the same
# per-component construction as gen-types' own `refined` and decided by the same `typeEq`; this file
# mints nothing itself and ADR-0034's count of minting authorities stays at one.
{
  merge,
  hasDeclaredSubject,
  sealedMarker,
}:
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
  # IDENTITY. A refinement's `check` is a caller-supplied lambda or a registered construction, so
  # ADR-0034's per-component clause makes it a SEALED COMPONENT: the type mints over the rest and
  # carries the check in `__sealed`. The construction is gen-types' own (`mkIdentity`, below), shared
  # rather than re-authored, so the two `refined` implementations cannot drift apart on the regime.
  # The base's identity fields join the removal list below: the inherited ones are never present to
  # be overwritten, so there is no shadowing order for a later reader to get wrong — the shape
  # `./id-hash.nix` argues for as "an expression with nowhere to attach".
  mkRefinedType =
    baseType: refinements:
    let
      normalized = normalizeRefinements refinements;

      # ★ THE IDENTITY, PER COMPONENT (ADR-0034's per-component clause; den-hoag-6orb8 U1.5): the
      # constructor, the base and each refinement, built by gen-types' `mkIdentity`. The base enters
      # by its mark where it carries one, and SEALED where it does not or where a wrapper rewrote its
      # `check` (gen-types' check-witness protocol), never by its base's mint: `refined int` and
      # `refined (addCheck int odd)` then mint apart, where reading the base's `__mint.minted` gave
      # them one mark while they admit different values. Each refinement enters with its `check` as a
      # sealed component — a caller lambda in its own slot, a registered construction (gen-algebra
      # `mkIntensional`) by its declared subject — and its `message` inert. So a registered digest
      # never enters the mark (it is a decision predicate, never a key), and two constructions of one
      # registered term decide `true` under `typeEq` and `kindEq`.
      #
      # `mkIdentity` steps gen-types' type-identity index over the base (`identityGuard`), so a chain
      # of refinements meets the bound and refuses by name rather than overflowing.
      identityFields =
        (merge.types.mkIdentity
          or (throw "gen-schema: refined: the leaf vocabulary behind this gen-merge exports no `mkIdentity`, so a refinement has no identity to build; wire a gen-types that exports it")
        )
          "refined"
          [ baseType ]
          (tags: {
            base = builtins.head tags;
            # a refinement's `check` is sealed; one with no `check` is inert and enters whole, and
            # one that is not a record is sealed whole
            refinements = map (
              r:
              if !(builtins.isAttrs r) then
                sealedMarker
              else if r ? check then
                r // { check = sealedMarker; }
              else
                r
            ) normalized;
          })
          (builtins.concatLists (
            builtins.genList (
              i:
              let
                r = builtins.elemAt normalized i;
                path = [
                  "refinements"
                  (toString i)
                ];
              in
              if !(builtins.isAttrs r) then
                [
                  {
                    inherit path;
                    value = r;
                  }
                ]
              else if !(r ? check) then
                [ ]
              else
                [
                  {
                    inherit path;
                    # a slice keeps the check's slot, where a selection would be a fresh thunk
                    value = if hasDeclaredSubject r.check then r.check else builtins.intersectAttrs { check = null; } r;
                  }
                ]
            ) (builtins.length normalized)
          ))
          functorName;

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
          "__okAt"
          "__payload"
          "__sealed"
        ]
        // identityFields
        // {
          # THE REFINEMENT IS PART OF THE TYPE'S MEMBERSHIP, wherever the type is used (§ Rondon 2008:
          # `{v:B | e}` has no member failing `e`). The base answers first, then the first failing
          # refinement by its own message, evaluated in order and stopping there — gen-types' `refined`
          # (`firstFailingRefinement`) matched, through the `verify` reason channel gen-merge reads, so
          # an earlier refinement guards a later one. Every refinement is included, `lazy` ones too:
          # gen-merge runs `verify` when the value is demanded, which is a lazy refinement's access. A
          # refinement's `check` is a caller lambda; one ill-typed over the base aborts uncatchably, so
          # each application carries the refinement's message as error context.
          verify =
            v:
            let
              baseReason =
                if baseType ? verify then
                  baseType.verify v
                else if baseType.check v then
                  null
                else
                  "not of type `${baseType.name or "?"}'";
              firstFailing =
                i:
                let
                  r = builtins.elemAt normalized i;
                in
                if i == builtins.length normalized then
                  null
                else if
                  builtins.addErrorContext "gen-schema: refined: while checking the refinement \"${r.message or "?"}\"" (
                    r.check v
                  )
                then
                  firstFailing (i + 1)
                else
                  r.message;
            in
            if baseReason != null then baseReason else firstFailing 0;
          # No `check` is stated: gen-merge derives the published `check` and its witness from
          # `verify` (`exportType`, "check <- verify"), so the domain is stated once.
          __schema = {
            refinements = normalized;
            baseType = baseType;
          };

          # `__mint`, `__id`, `__payload`, `__sealed` and `__okAt` are gen-types' identity fields for
          # this construction (`identityFields` above), so a reader dispatches on the TAG and `typeEq`
          # decides over the mark and the sealed subjects, as for every gen-types type.

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
