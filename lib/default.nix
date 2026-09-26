{
  prelude,
  merge,
  algebra,
  identity,
}:
let
  inherit (algebra) record;

  methods = import ./methods.nix { inherit prelude merge; };
  validate = import ./validate.nix {
    inherit prelude;
    inherit (entryType) isSchemaKind;
  };
  # Named for the field it produces, and for the one thing both its bindings agree on. It was
  # `identity.nix` while it contained the mint; it does not, and a file called that beside a
  # LIBRARY called gen-identity is a reader's trap rather than a tidy-up.
  idHashLib = import ./id-hash.nix {
    inherit prelude merge identity;
    inherit (entryType) isSchemaKind;
  };
  # THE MERGE RELATION OF A TYPE BUILT PER CONSTRUCTION (den-hoag-bfc0k). `schemaKindEntry`,
  # `ref(<kind>)` and `strict` are built fresh on every call — the entry type and `strict` on every
  # EVALUATION of the module function declaring them — so a redeclared option meets two records of
  # one name, and gen-merge refuses a same-named pair that is not one value unless the type states
  # its own relation (`functor.binOp`). This is that statement: two such types are one type exactly
  # when their constructions are one construction, and every other same-named pair is refused.
  #
  # "One construction" is ADR-0034's, per component, through the machinery the kind mark already
  # uses (`entry-type.nix` `markOf`/`kindEq`). The constructor declares its components by regime:
  # `minted` ones enter one mark through `componentsPreimage`, and each `compared` one is held as
  # its reified value for `sealedCollisionEq`'s one `==` — one mark with `==` compared values
  # merges, answering with this operand since the two denote one type. Anything else answers
  # `null`, the protocol's "these do not merge", and gen-merge refuses the pair by name at the
  # option. A `binOp` has no reason channel (gen-merge's to publish), and throwing
  # `sealedCollisionEq`'s own named refusal from here would abort a caller that asks a type whether
  # it merges rather than declaring it twice. Lazy: nothing is minted or compared until a
  # same-named partner asks.
  #
  # ★ A COMPARED COMPONENT STATES `records`, AND HAS NO DEFAULT FOR IT. Its value can hold option
  # types, whose exported records are cyclic, so a bare `==` between two constructions can recurse
  # until the evaluator aborts — uncatchably, past the `tryEval` below. `records` are the type records
  # the constructor's own grammar places in the value (a `keySemantics` entry's `option.type`), and
  # the value is compared through gen-merge's `closuresFirst`, which decides on their closures before
  # it can reach a back-edge. The value sits inside that subject's list, which also keeps a function's
  # slot identity (den-hoag-jzatq). An entry without `records` is refused by name, so the FIELD
  # cannot be omitted silently. Its CONTENT is not checked: `records = [ ]` is an unchecked assertion
  # that the grammar fixes no type-record position in that component, and stating it over a value
  # that does hold a record is the silent spelling of an omission (it aborts on two knotted
  # constructions). A record at a position the grammar does not fix is outside `records` and keeps
  # `closuresFirst`'s enumerated exception — and that is ORDINARY MODULE CONTENT, not a contrived
  # position: a module in a `records = [ ]` component (`mixins`, `baseModule`, `specialArgs`), or a
  # facet's `module`, declaring an option typed by a per-call `mkOptionType` aborts in the order
  # that interns `functor` first, and in every order when that type has a `description` back-edge.
  constructionRelation =
    name:
    {
      minted ? { },
      compared ? { },
    }:
    self:
    let
      malformed = builtins.filter (
        k:
        !(
          builtins.isAttrs compared.${k}
          &&
            builtins.attrNames compared.${k} == [
              "records"
              "value"
            ]
          && builtins.isList compared.${k}.records
        )
      ) (builtins.attrNames compared);
      components =
        if malformed != [ ] then
          throw "gen-schema: ${name}: compared component(s) ${
            builtins.concatStringsSep ", " (map (k: "'${k}'") malformed)
          } must be exactly { records = [ <the type records its value holds> ]; value; }"
        else
          map (k: {
            path = [ k ];
            value = minted.${k};
          }) (builtins.attrNames minted)
          # Destructured by a formal, never selected: the formal binds the entry's own `value`, so a
          # function keeps the slot the constructor handed over. A selection is a fresh thunk per
          # construction, and upstream Nix `==` then refuses one shared function (den-hoag-jzatq).
          ++ builtins.attrValues (
            builtins.mapAttrs (
              k:
              { records, value }:
              {
                path = [ k ];
                value = merge.closuresFirst records value;
                sealed = true;
              }
            ) compared
          );
      pre = algebra.componentsPreimage identity.hashIdentity components;
    in
    {
      inherit name;
      payload = {
        inherit name;
        mark = identity.hashIdentity "gen-schema-type" [ "components" ] (_: pre.tags);
        inherit (pre) sealed;
      };
      # The marks are forced OUTSIDE the `tryEval`: a construction that cannot be minted (a
      # component list that has drifted from its constructor's formals, a compared component
      # stating no `records`, a minted component the mint refuses) is a defect in the type and is
      # refused as itself, not answered as "do not merge".
      binOp =
        a: b:
        let
          same = builtins.tryEval (algebra.sealedCollisionEq "gen-schema: ${name}" a b);
        in
        builtins.seq a.mark (
          builtins.seq (b.mark or null) (if same.success && same.value then a else null)
        );
      type = _: self;
    };

  # The type records a `keySemantics` value holds at the one position its grammar fixes, an entry's
  # `option.type` (`{ <key> = { category; option?; }; }`). Shared with gen-aspects, whose cnf carries
  # the same grammar.
  keySemanticsRecords =
    ks:
    prelude.concatMap (
      e:
      if builtins.isAttrs e && builtins.isAttrs (e.option or null) && e.option ? type then
        [ e.option.type ]
      else
        [ ]
    ) (builtins.attrValues ks);

  strictLib = import ./strict.nix { inherit prelude merge constructionRelation; };
  refinedLib = import ./refined.nix {
    inherit merge identity;
    inherit (algebra) preimageTagOf;
  };
  blameLib = import ./blame.nix;
  mixinLib = import ./mixin.nix { inherit record; };
  bridgeLib = import ./bridge.nix {
    inherit prelude record;
    inherit (refinedLib) isRefined getRefinements;
  };
  refLib = import ./ref.nix { inherit prelude merge constructionRelation; };
  # The VALUE-level reference vocabulary, kin to refLib's type-level one — see field-ref.nix's
  # header for the axis that separates them.
  fieldRefLib = import ./field-ref.nix { inherit prelude; };
  # `identity` is threaded in for the PROVENANCE MARK (ADR-0034) this file's entry-type mints on
  # every kind value. It takes the mint as an injected leaf and constructs with it — the same
  # discipline `id-hash.nix` is under, and the reason `hashIdentity` is still absent from the
  # published surface below.
  entryType = import ./entry-type.nix {
    inherit
      prelude
      merge
      record
      identity
      constructionRelation
      keySemanticsRecords
      ;
    inherit (methods) mkMethodsModule;
    inherit (refLib) refsFromOptionsWithTypes;
    inherit (mixinLib) applyMixin;
    inherit (bridgeLib) emitModule isOptionDecl;
    inherit (refinedLib) getRefinements;
    inherit (algebra) componentsPreimage sealedCollisionEq identityOf;
  };
  evalSchemaLib = import ./eval-schema.nix {
    inherit prelude merge;
    inherit (entryType) mkSchemaOption;
  };
  instance = import ./instance.nix {
    inherit prelude merge;
    inherit (entryType) isSchemaKind;
    inherit (strictLib) mkStrictModule;
    inherit (idHashLib) mkIdentityModule identityKeysForKind;
    inherit (validate)
      runValidators
      defaultOnError
      filterValidators
      ;
    inherit (refLib) dedupByHash;
  };
  docs = import ./docs.nix { inherit prelude; };
  codecLib = import ./codec.nix {
    inherit prelude;
    inherit (entryType) isSchemaKind;
  };
in
{
  # Identity / strict / validation module surface (gen-schema-owned).
  # ★ `hashIdentity` IS NOT HERE, and its absence is the point. The mint lives in
  # `gen-identity`; re-exporting it under gen-schema's name would re-export its BUILD, which is
  # the verbatim re-handing ADR-0014 rejects — and gen-schema's own discharged instance of that
  # ADR was doing exactly this with gen-merge's seven bindings. A consumer that wants the mint
  # takes the leaf, which it can, because the leaf has no inputs to conflict with anything.
  inherit (idHashLib)
    mkIdentityModule
    identityHashForKind
    # The key-set half of the recompute, published for the same reason the hash half is: a consumer
    # holding a kind value can ask WHICH options an instance of it is identified by without minting
    # anything. It is the one derivation both the stamp and the recompute read, so a consumer that
    # pins it is pinning the thing that moves rather than a copy of it.
    identityKeysForKind
    ;
  inherit (strictLib) mkStrictModule;
  inherit (validate)
    mkValidator
    runValidators
    formatErrors
    defaultOnError
    ;
  inherit (methods) schemaFn;
  inherit (entryType) mkSchemaOption mkSchemaEntryType kindEq;
  inherit (evalSchemaLib) evalSchema;
  inherit (instance) mkInstanceType mkInstanceRegistry;
  inherit (validate) validateInstances mkFieldValidator filterValidators;
  inherit (refLib) ref setOf toSet;
  inherit (fieldRefLib)
    fieldRef
    isFieldRef
    fieldRefsIn
    fieldRefMarker
    ;
  inherit (refinedLib) refinements checkRefinements;
  inherit (refinedLib.types) refined;
  inherit (blameLib) blame;
  inherit (mixinLib)
    mkMixin
    composeMixins
    beta
    applyMixin
    ;
  inherit (bridgeLib) emitModule;
  inherit (docs) renderDocs;
  inherit (codecLib) mkCodec;

  # A type built per construction states its merge relation through this: one construction merges,
  # two are refused (den-hoag-bfc0k). gen-aspects' per-cnf types use it with the same grammar.
  inherit constructionRelation keySemanticsRecords;

  _internal = {
    inherit (methods) mkMethodsModule;
  };
}
