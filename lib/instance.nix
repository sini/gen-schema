# Instance type and registry constructors.
#
# Instances add the infrastructure that bare schema kinds don't have:
# strict validation, identity hashing, and the `name` option. This means
# kind-level composition (imports between kinds) is pure schema merging,
# while instance-level evaluation gets strict + id_hash injected once.
#
# The validate → derive → apply pipeline runs in `apply` on the option,
# after module system evaluation. Validators and derive hooks are optional.
{
  prelude,
  merge,
  isSchemaKind,
  stampOk,
  stampRefusal,
  mkStrictModule,
  mkIdentityModule,
  identityKeysForKind,
  runValidators,
  defaultOnError,
  dedupByHash,
  bindRefType,
  unwalkedContainer,
  isCanonicalOf,
  declarationForm,
  filterValidators,
  getRefinements,
}:
let
  # OPTIONS FIRST, then the kind (den-hoag-7gp66 P2, rules 2 and 4): `mkInstanceType { extraModules?;
  # strict?; specialArgs?; } kind`. The options are one closed set, a `prelude.door` refused by name
  # and catchably at `mkInstanceType opts`'s own WHNF; the kind value is the subject, last. The core
  # below keeps its native defaulted formals (`strict` defaults from the kind), now reached only
  # through the checked door or from this file.
  mkInstanceType = prelude.door {
    name = "gen-schema.mkInstanceType";
    optional = [
      "extraModules"
      "strict"
      "specialArgs"
    ];
  } (o: kindValue: mkInstanceTypeCore kindValue o);
  mkInstanceTypeCore =
    kindValue:
    {
      extraModules ? [ ],
      strict ? kindValue.strict,
      # BASE MODULE ARGS for the instance fixpoint, handed to gen-merge's type-level inlet below.
      # A module that forces an argument at its OWN WHNF — `{ lib, ... }: { options.x = mkOption {
      # default = lib.foo; }; }` — cannot be served from `_module.args`: reading that forces the
      # config fixpoint the module is part of, and the result is an UNCATCHABLE infinite recursion
      # naming neither the module nor the argument. A base arg is the admissible channel, and
      # ADR-0033 rules the declaration-plane `_module.args` read inadmissible precisely so this one
      # is used instead. Empty by default: a kind whose modules declare no extra formal is
      # unaffected, because a function module binds only the formals it declares.
      specialArgs ? { },
    }:
    let
      _ =
        assert
          isSchemaKind kindValue
          || throw "gen-schema: mkInstanceType: expected a kind value carrying a mint-backed mark (`__mint.minted`); got an attrset with no mark";
        null;
      kind = kindValue.kind;

      # ★ THE KIND BOUNDARY. The identity-key set closes HERE, one stratum above the instance
      # fixpoint, and is carried into that fixpoint as data. Everything below this line — the strict
      # or freeform module, the identity module, `extraModules`, and every module a ref binding or a
      # refinement adds — is seen AFTER the set is a value, so none of them can enter it. Lazy on
      # purpose: forcing it here would force `kindValue` at option-DECLARATION time, which is the
      # recursion `mkInstanceRegistry`'s deferred guard exists to avoid on the self-referential
      # `mkInstanceRegistry { } config.schema.host` idiom. It is forced at config-demand time, by
      # `id_hash` or by a read of `_identityKeys`, which is late enough.
      #
      # ★ IT TAKES THE SAME `specialArgs` THE INLET BELOW DOES, and that is not a duplicate of the
      # thread. The inlet serves the INSTANCE fixpoint; this is a SECOND application of the kind's
      # modules, one stratum up, and a module forcing its argument to produce its own WHNF refuses
      # under ADR-0033 here while evaluating perfectly through the inlet. That is why an instance
      # could read every declared option and still not be stampable.
      identityKeys = identityKeysForKind { inherit specialArgs; } kindValue;
      # Once per TYPE, not once per instance: the operand check and the module value are shared.
      identityModule = mkIdentityModule kindValue identityKeys;
      # THE COMPLETION STAMP (den-hoag-1a4f6), read where the kind's module is imported: the import
      # is the kind's `__functor`, the original module, so a `//` copy of the kind would otherwise
      # build instances of the original and drop the caller's change. Lazy and once per TYPE, forced
      # at the first instance's import, at config-demand time; never at the guard above, which runs
      # at option-DECLARATION time and must not force the kind's slots.
      importedKind =
        if kindValue ? __kindSelf && !(stampOk kindValue) then
          stampRefusal "gen-schema: mkInstanceType" kindValue
        else
          kindValue;
    in
    # ★ THE INLET IS ON THE TYPE, NOT THE CONSTRUCTOR, and it is applied UNCONDITIONALLY rather than
    # behind an `if specialArgs == { }` — one path, so every instance gen-schema builds goes through
    # the same construction and the empty case is not a second, untested one.
    (merge.types.submodule (
      { name, config, ... }:
      {
        imports = [
          (builtins.seq _ importedKind)
        ]
        ++ [
          (
            if strict then
              mkStrictModule kind
            # gen-merge reads `_module` only from `config`, so the non-strict freeform
            # must live under `config` (a top-level `_module` is dropped).
            else
              { config._module.freeformType = merge.types.attrsOf merge.types.anything; }
          )
          identityModule
        ]
        ++ extraModules;
        config._module.args.${kind} = config;
        options.name = merge.mkOption {
          type = merge.types.str;
          default = name;
        };
        # The closed key set, published beside `id_hash` as a readable datum.
        #
        # WHY A DATUM AND NOT A CHECK. Two COLD evaluations a week apart is the one region of this
        # class the substrate cannot close: nothing here holds the earlier evaluation, and no party
        # can compare against what it does not have. Inventing a comparison that cannot see the
        # second evaluation would be worse than the gap, so what is offered instead is the set
        # itself — a caller pins it, diffs it across runs, or hashes it into its own acceptance
        # corpus, and the caller is then the party that holds both. That is the whole of what is
        # available, and a caller whose pinned set goes stale hears NOTHING from this library.
        options._identityKeys = merge.mkOption {
          readOnly = true;
          internal = true;
          type = merge.types.listOf merge.types.str;
          default = identityKeys;
          description = "The closed identity-key set this kind's instances are minted over.";
        };
      }
    )).withArgs
      specialArgs;

  # Type-tree predicates for coercion chain dispatch.
  isRefLeaf = t: (t.refKind or null) != null;
  elemTypeOf = t: (t.nestedTypes or { }).elemType or null;
  isNullOr = t: (t.name or "") == "nullOr";
  isSetOf = t: t.isSetOf or false;
  isAttrsOf =
    t:
    builtins.elem (t.name or "") [
      "attrsOf"
      "lazyAttrsOf"
    ];
  isListOf = t: (t.name or "") == "listOf";

  # Build a coercion function matching the nesting structure of a ref type.
  # Walks the type tree at binding time so the runtime dispatch is exact.
  # Supports optional custom coerce hooks for domain-specific resolution.
  mkCoerceChain =
    field: kind: registry: customCoerce: type:
    let
      resolve =
        prelude.resolve
          {
            hint = "name";
            form = declarationForm;
          }
          {
            entries = registry;
            isCanonical = isCanonicalOf registry;
          }
          "gen-schema: ref field '${field}' on kind '${kind}'";

      defaultCoerce =
        v:
        if builtins.isString v then
          if registry ? ${v} then
            registry.${v}
          else
            throw "gen-schema: ref field '${field}' on kind '${kind}': reference '${v}' not found in instance registry (available: ${builtins.concatStringsSep ", " (builtins.attrNames registry)})"
        else
          registry.${resolve v};

      # Scalar leaf: custom coerce receives the default result (lazy) and raw value.
      # Throws if custom coerce returns a list in scalar context.
      mkLeafCoerce =
        v:
        if customCoerce == null then
          defaultCoerce v
        else
          let
            result = customCoerce (defaultCoerce v) v;
          in
          if builtins.isList result then
            throw "gen-schema: ref field '${field}' on kind '${kind}': custom coerce returned a list in scalar context (use listOf declarationOf for 1-to-many expansion)"
          else
            result;

      # List-element leaf: custom coerce receives [ defaultResult ] and raw value.
      # Returns a list (1→many expansion supported).
      mkListCoerce =
        v:
        if customCoerce == null then
          [ (defaultCoerce v) ]
        else
          let
            result = customCoerce [ (defaultCoerce v) ] v;
          in
          if builtins.isList result then
            result
          else
            throw "gen-schema: ref field '${field}' on kind '${kind}': custom coerce must return a list in listOf/setOf context";

      go =
        t:
        if isRefLeaf t then
          mkLeafCoerce
        else
          let
            et = elemTypeOf t;
          in
          if et == null then
            mkLeafCoerce
          else
            let
              inner = go et;
            in
            if isNullOr t then
              v: if v == null then null else inner v
            else if isSetOf t then
              let
                listInner = goList et;
              in
              v: dedupByHash (builtins.concatMap listInner v)
            else if isAttrsOf t then
              # attrsOf: each value is a scalar position of its own, so it takes `go`, not the 1→many `goList`
              v: builtins.mapAttrs (_: inner) v
            else if isListOf t then
              # listOf: use concatMap with list-producing coerce for 1→many expansion
              let
                listInner = goList et;
              in
              v: builtins.concatMap listInner v
            else
              unwalkedContainer field kind t;

      # List-context walker: produces a list per element for concatMap.
      goList =
        t:
        if isRefLeaf t then
          mkListCoerce
        else
          let
            et = elemTypeOf t;
          in
          if et == null then
            v: [ (mkLeafCoerce v) ]
          else
            let
              inner = go et;
            in
            if isNullOr t then
              v: [ (if v == null then null else inner v) ]
            else if isSetOf t then
              let
                listInner = goList et;
              in
              v: [ (dedupByHash (builtins.concatMap listInner v)) ]
            else if isAttrsOf t then
              v: [ (builtins.mapAttrs (_: inner) v) ]
            else if isListOf t then
              v: [ (builtins.concatMap (goList et) v) ]
            else
              unwalkedContainer field kind t;
    in
    go type;

  # Build extra modules that override deferred ref fields with resolved types.
  # Returns { modules; deferredCoerce; } — immediate modules get the apply-time
  # coerce chain, deferred bindings (deferred = true) skip option-level apply and
  # run their coerce in applyPipeline instead. This avoids infinite recursion when
  # a registry's ref field points back to itself with a custom coerce hook.
  mkRefBindingModules =
    kind: refs: refFields: kindOptions:
    let
      # Validate: every deferred ref field must have a binding.
      # N.B. Missing-binding check is duplicated in applyPipeline.refValidation
      # for the refs == {} case — keep error messages in sync.
      missingBindings = prelude.filterAttrs (field: _: !(refs ? ${field})) refFields;
      extraBindings = prelude.filterAttrs (field: _: !(refFields ? ${field})) refs;

      _ =
        if missingBindings != { } then
          let
            missing = builtins.head (prelude.attrNames missingBindings);
            targetKind = missingBindings.${missing}.refKind;
          in
          throw "gen-schema: mkInstanceRegistry: kind '${kind}' has ref field '${missing}' targeting kind '${targetKind}' but no refs.${missing} binding was provided"
        else if extraBindings != { } then
          let
            extra = builtins.head (prelude.attrNames extraBindings);
          in
          throw "gen-schema: mkInstanceRegistry: refs.${extra} does not match any ref field on kind '${kind}'"
        else
          null;

      bindings = builtins.seq _ (
        prelude.mapAttrs (
          field: binding:
          let
            isDeferred = builtins.isAttrs binding && (binding.deferred or false);
            norm =
              if builtins.isAttrs binding && binding ? coerce then
                {
                  registry = binding.instances;
                  customCoerce = binding.coerce;
                }
              else
                {
                  registry = binding;
                  customCoerce = null;
                };
            fieldInfo = refFields.${field};
          in
          if isDeferred then
            # Deferred: store raw materials, NOT a pre-built coerceChain.
            # The chain is rebuilt inside applyPipeline with the raw instances
            # as registry, breaking self-referential cycles where
            # binding.instances = config.traits (the post-apply value).
            # The custom coerce hook receives `registry` as first arg when deferred,
            # so it can resolve against raw instances instead of capturing config.X.
            assert
              (builtins.isAttrs binding && binding ? instances)
              || throw "gen-schema: deferred ref binding for '${field}' on kind '${kind}' requires 'instances' (got: ${builtins.toJSON (builtins.attrNames binding)})";
            {
              inherit isDeferred;
              rawCustomCoerce = norm.customCoerce;
              type = fieldInfo.type;
            }
          else
            {
              inherit isDeferred;
              coerceChain = mkCoerceChain field kind norm.registry norm.customCoerce fieldInfo.type;
            }
        ) refs
      );

      immediateBindings = prelude.filterAttrs (_: b: !b.isDeferred) bindings;
      deferredBindings = prelude.filterAttrs (_: b: b.isDeferred) bindings;

      # Re-declare the ref field's FULL option (type + default + …) with the coerce
      # `apply` layered on. gen-merge merges option DECLARATIONS with a shallow `//`
      # (unlike nixpkgs' deep decl-merge), so a bare `{ apply = … }` here would wipe the
      # kind's `type`/`default` and break default-valued ref fields ([]/null).
      immediateModules = prelude.mapAttrsToList (
        field: b:
        { ... }:
        {
          options.${field} = (kindOptions.${field} or { }) // {
            type = bindRefType field kind refFields.${field}.type;
            apply = b.coerceChain;
          };
        }
      ) immediateBindings;
      # A deferred binding coerces in applyPipeline, so its module only binds the type.
      deferredModules = prelude.mapAttrsToList (
        field: _:
        { ... }:
        {
          options.${field} = (kindOptions.${field} or { }) // {
            type = bindRefType field kind refFields.${field}.type;
          };
        }
      ) deferredBindings;
    in
    {
      modules = immediateModules ++ deferredModules;
      deferredCoerce = deferredBindings;
    };

  # OPTIONS FIRST, then the kind (den-hoag-7gp66 P2, rules 2 and 4): `mkInstanceRegistry { … } kind`,
  # the self-referential idiom reading `mkInstanceRegistry { } config.schema.host`. The options are one
  # closed set, a `prelude.door` refused by name and catchably at `mkInstanceRegistry opts`'s own WHNF,
  # which never reads the kind, so the deferred guard below keeps its timing.
  #
  # The kind-first call `mkInstanceRegistry kindValue { … }` is refused by name when the kind comes
  # through the module's own `config` (gen-merge's declaration guard) or from a closed evaluation
  # (this door). Through a `let` knot over the SAME evaluation, `eval.config.schema.host`, it aborts
  # uncatchably (den-hoag-ht5ar). Argued impossibility (ADR-0013 form): the option record's WHNF is in
  # the declaration spine `eval.config` waits on, and telling a kind from an options set needs a read
  # of an operand at that WHNF, so the knot on whichever operand is read is the cycle. Reading the
  # first operand (this door) puts the abort on the kind-first order. Reading the second puts it on the
  # options-first order and refuses the supported module-`config` spelling above. Reading neither
  # admits a misspelt option silently on a registry nothing reads. What would have to change: an
  # operand on no knot in either order, which no attrset-valued kind operand can be. Pinned by
  # `pre-l4-registry-call` in `ci/tests-error.nix`.
  mkInstanceRegistry = prelude.door {
    name = "gen-schema.mkInstanceRegistry";
    optional = [
      "extraModules"
      "refs"
      "refinements"
      "strict"
      "description"
      "derive"
      "deriveEither"
      "specialArgs"
    ];
  } (o: kindValue: mkInstanceRegistryCore kindValue o);
  mkInstanceRegistryCore =
    kindValue:
    let
      _guardMsg = "gen-schema: mkInstanceRegistry: expected a kind value carrying a mint-backed mark (`__mint.minted`); got an attrset with no mark";
      # Deferred guard — forced when `kind` is accessed, avoids infinite
      # recursion at option-declaration time when kindValue = eval.config.schema.host.
      # This alone is not enough (a registry with no validators/refs never
      # forces `kind` even once genuinely read) — applyPipeline below carries
      # the unconditional half, forced only at config-fixpoint demand time,
      # which is late enough to read kindValue safely.
      #
      # ★ THE DEFERRAL IS THE CONSTRAINT, NOT THE PREDICATE'S DEPTH, and `isSchemaKind` is written
      # so it costs the staging nothing: its four reads stop at the mark RECORD and never force
      # `minted`, so the preimage's `introspect.options` — a full `evalModuleTree` of the merged
      # kind module — is not run here.
      kind =
        assert isSchemaKind kindValue || throw _guardMsg;
        kindValue.kind;
    in
    {
      extraModules ? [ ],
      refs ? { },
      refinements ? { },
      strict ? kindValue.strict,
      description ? "${kind} instances",
      derive ? null,
      deriveEither ? null,
      # Forwarded VERBATIM to `mkInstanceType` below — the registry builds its element with that
      # constructor, so this is the same thread reaching the same inlet, not a second one. Stated
      # here because a registry is how a consumer declares instances in practice; without it the
      # channel would be published on a constructor most callers never name.
      specialArgs ? { },
    }:
    assert
      (derive == null || deriveEither == null)
      || throw "gen-schema: mkInstanceRegistry: derive and deriveEither are mutually exclusive";
    let
      # Resolve refs from kindValue — no need to evaluate schema options,
      # the kind value carries pre-computed ref field metadata.
      refFields = if refs == { } then { } else kindValue.refs;
      refResult =
        if refs == { } then
          {
            modules = [ ];
            deferredCoerce = { };
          }
        else
          mkRefBindingModules kind refs refFields kindValue.options;
      allExtraModules = extraModules ++ refResult.modules;

      onError = if deriveEither != null then deriveEither.onError or defaultOnError else defaultOnError;

      deriveFn =
        if derive != null then
          derive
        else if deriveEither != null then
          instances:
          let
            result = deriveEither.derive instances;
          in
          if result ? right then result.right else onError result.left
        else
          null;

      # The apply pipeline: validate → derive → overlay.
      applyPipeline =
        instances:
        # Unconditional half of the kind-value guard: `apply` runs only at
        # config-fixpoint demand time (safely after the options phase), so
        # asserting here — rather than relying on `kind` being referenced by
        # some conditional branch below — catches a bogus kindValue even for
        # a registry with no validators and no ref bindings, where nothing
        # else in this pipeline would ever force `kindValue.kind`.
        assert isSchemaKind kindValue || throw _guardMsg;
        let
          # Ref binding validation — check for missing bindings (refs == {} but
          # kind declares ref fields). Mirrors mkRefBindingModules error messages.
          refValidation =
            let
              allRefFields = kindValue.refs;
              missingBindings = prelude.filterAttrs (field: _: !(refs ? ${field})) allRefFields;
            in
            if missingBindings != { } then
              let
                missing = builtins.head (prelude.attrNames missingBindings);
                targetKind = missingBindings.${missing}.refKind;
              in
              throw "gen-schema: mkInstanceRegistry: kind '${kind}' has ref field '${missing}' targeting kind '${targetKind}' but no refs.${missing} binding was provided"
            else
              builtins.length refResult.modules; # forces builtins.seq inside mkRefBindingModules

          validators = builtins.seq refValidation (
            let
              raw = kindValue.validators or [ ];
              # Derive option names from any instance — all share the same kind schema.
              optionNames =
                if instances == { } then
                  [ ]
                else
                  builtins.attrNames (builtins.head (builtins.attrValues instances));
            in
            filterValidators optionNames raw
          );

          # Deferred coerce: rebuild coerce chains using raw instances as registry.
          # This breaks self-referential cycles: the coerce hook accesses `instances`
          # (the pre-apply value, already materialized) instead of `config.traits`
          # (the post-apply value, which would re-enter applyPipeline).
          # Runs BEFORE validators so validators see resolved instances, not raw strings.
          coerced =
            if refResult.deferredCoerce == { } then
              instances
            else
              let
                deferredFields = builtins.attrNames refResult.deferredCoerce;
                # One chain per FIELD: its inputs are the field and the raw registry, never the
                # instance, so building it per instance rebuilt the resolver's index n times.
                # The registry is the raw instances, NOT the captured binding.instances (which may
                # be config.X, causing cycles). A custom coerce is wrapped to take that registry
                # first: the consumer writes `coerce = registry: default: val: ...` and gen-schema
                # calls `wrappedCoerce default val`.
                chains = builtins.mapAttrs (
                  field: binding:
                  mkCoerceChain field kind instances (
                    if binding.rawCustomCoerce != null then binding.rawCustomCoerce instances else null
                  ) binding.type
                ) refResult.deferredCoerce;
              in
              prelude.mapAttrs (
                _name: instance:
                builtins.foldl' (
                  inst: field:
                  let
                    rawValue = inst.${field} or null;
                  in
                  inst // { ${field} = chains.${field} rawValue; }
                ) instance deferredFields
              ) instances;

          # Refinement pass. A refined TYPE enforces its own refinements whenever its value is demanded
          # (`lib/refined.nix`, `verify`), so this pass checks only the refinements no type carries (the
          # `refinements` argument, or a kind refinement on a field whose type is not refined), and
          # decides WHEN a field is demanded. A field whose every top-level refinement is `lazy`, its
          # type's and the pass's alike, is left unforced and checked at access (§ Chitil 2012). One
          # strict refinement makes construction demand the field, and its whole conjunction is decided
          # then: on a flat value a demanded field has nothing left to defer (Chitil §7.3).
          typeRefinements = prelude.filterAttrs (_: rs: rs != [ ]) (
            prelude.mapAttrs (
              _: o: if (o._type or null) == "option" && o ? type then getRefinements o.type else [ ]
            ) (kindValue.options or { })
          );
          passRefinements =
            if refinements != { } then
              refinements
            else
              prelude.filterAttrs (f: _: !(typeRefinements ? ${f})) (kindValue.refinements or { });
          refinedFields = builtins.attrNames (typeRefinements // passRefinements);

          refinementChecked =
            if refinedFields == [ ] then
              coerced
            else
              prelude.mapAttrs (
                instanceName: instance:
                builtins.foldl' (
                  inst: fieldName:
                  let
                    refs' = passRefinements.${fieldName} or [ ];
                    at = "${kind}:${instanceName}.${fieldName}";
                    deferred = builtins.all (r: r.lazy or false) ((typeRefinements.${fieldName} or [ ]) ++ refs');
                    value = inst.${fieldName} or null;
                    failing = builtins.filter (r: !(r.check value)) refs';
                  in
                  if deferred && inst ? ${fieldName} then
                    inst
                    // {
                      ${fieldName} = builtins.foldl' (
                        v: r:
                        if v == null then
                          v
                        else
                          builtins.addErrorContext "gen-schema: lazy contract at ${at}: \"${r.message}\"" (
                            if r.check v then v else throw "gen-schema: lazy contract violated at ${at}: ${r.message}"
                          )
                      ) inst.${fieldName} refs';
                    }
                  else if value == null || failing == [ ] then
                    inst
                  else
                    throw "gen-schema: refinement failed at ${at}\n  check: \"${(builtins.head failing).message}\"\n  value: ${builtins.toJSON value}"
                ) instance refinedFields
              ) coerced;

          # Validators run on refinement-checked instances — deferred ref fields are resolved,
          # so validators can inspect .name, .id_hash etc. on referenced instances.
          vResult =
            if validators == [ ] then
              null
            else
              let
                r = runValidators kind validators refinementChecked;
              in
              if r ? right then null else r.left;

          validated =
            if vResult == null then
              refinementChecked
            else
              let
                recovery = onError vResult;
              in
              prelude.mapAttrs (name: instance: instance // (recovery.${name} or { })) refinementChecked;

          derived = if deriveFn == null then { } else deriveFn validated;

          result =
            if derived == { } then
              validated
            else
              prelude.mapAttrs (name: instance: instance // (derived.${name} or { })) validated;
        in
        # Force refValidation explicitly — ensures missing-binding errors throw
        # even when no validators or deferred coerce are present.
        builtins.seq refValidation result;
    in
    merge.mkOption {
      inherit description;
      # `default` is LAZY in `kind`: `builtins.seq kind { }` is a thunk the option record's WHNF never
      # forces, so building the record against the self-referential idiom
      # `options.hosts = mkInstanceRegistry {} eval.config.schema.host` still needs no `kindValue`
      # (constructing the record reads a config value before `eval`'s options phase has run; an
      # eager guard here recurses infinitely, den-hoag-fvxh measured it). A raw `.default` read
      # that bypasses `apply` forces the thunk, so it refuses by name on a non-kind, where it once
      # returned `{ }` (den-hoag-cxlc0). A registry nothing reads costs nothing new, and a registry
      # over a genuine kind still defaults to `{ }`. Every other in-contract read goes through
      # `apply` (below): a name-set read there answers the definitions' names and reads no kind, and
      # an element read carries the unconditional guard.
      default = builtins.seq kind { };
      type = merge.types.attrsOf (
        mkInstanceTypeCore kindValue {
          extraModules = allExtraModules;
          inherit strict specialArgs;
        }
      );
      # ★ THE NAME SET IS THE DEFINITIONS', as the `mkInstanceType` sibling's is (den-hoag-2vo1m).
      # Every stage of the pipeline maps over `instances` and adds or drops no name, so its output's
      # key set is stated here as the input's rather than read off the pipeline, which reads the kind.
      # A kind decided by the registry's own names (`config.reg ? h1`) therefore composes; every
      # registry-level check still runs, at the first ELEMENT read, where the sibling refuses too.
      # Five refusals fire there and not at a name read: the kind guard, a missing and an extra ref
      # binding, a `deriveEither` left under the default `onError`, and a throwing `derive`.
      # ★ THE OBLIGATION ON EVERY FUTURE STAGE: preserve the name set. A stage that DROPS a name
      # turns that element's read into an `attribute '…' missing` that `tryEval` does not catch;
      # a stage that ADDS one is dropped here silently, as it was before.
      apply =
        instances:
        let
          out = applyPipeline instances;
        in
        prelude.mapAttrs (name: _: out.${name}) instances;
    };
in
{
  inherit mkInstanceType mkInstanceRegistry;
}
