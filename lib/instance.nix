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
  mkStrictModule,
  mkIdentityModule,
  runValidators,
  defaultOnError,
  dedupByHash,
  filterValidators,
}:
let
  mkInstanceType =
    kindValue:
    {
      extraModules ? [ ],
      strict ? kindValue.strict,
    }:
    let
      _ =
        assert
          (kindValue ? kind && kindValue ? options)
          || throw "gen-schema: mkInstanceType: expected a kind value with 'kind' and 'options' attributes";
        null;
      kind = kindValue.kind;
    in
    merge.types.submodule (
      { name, config, ... }:
      {
        imports = [
          (builtins.seq _ kindValue)
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
          (mkIdentityModule kind)
        ]
        ++ extraModules;
        config._module.args.${kind} = config;
        options.name = merge.mkOption {
          type = merge.types.str;
          default = name;
        };
      }
    );

  # Type-tree predicates for coercion chain dispatch.
  isRefLeaf = t: (t.refKind or null) != null;
  elemTypeOf = t: (t.nestedTypes or { }).elemType or null;
  isNullOr = t: (t.name or "") == "nullOr";
  isSetOf = t: t.isSetOf or false;

  # Build a coercion function matching the nesting structure of a ref type.
  # Walks the type tree at binding time so the runtime dispatch is exact.
  # Supports optional custom coerce hooks for domain-specific resolution.
  mkCoerceChain =
    field: kind: registry: customCoerce: type:
    let
      # Validate that a coercion result is a plausible instance (has name + id_hash).
      assertInstance =
        v:
        if builtins.isAttrs v && v ? name && v ? id_hash then
          v
        else
          throw "gen-schema: ref field '${field}' on kind '${kind}': expected an instance (with name and id_hash), got ${builtins.typeOf v}";

      defaultCoerce =
        v:
        if builtins.isString v then
          if registry ? ${v} then
            registry.${v}
          else
            throw "gen-schema: ref field '${field}' on kind '${kind}': reference '${v}' not found in instance registry (available: ${builtins.concatStringsSep ", " (builtins.attrNames registry)})"
        else
          assertInstance v;

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
            throw "gen-schema: ref field '${field}' on kind '${kind}': custom coerce returned a list in scalar context (use listOf ref for 1-to-many expansion)"
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
            else
              # listOf: use concatMap with list-producing coerce for 1→many expansion
              let
                listInner = goList et;
              in
              v: builtins.concatMap listInner v;

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
            else
              v: [ (builtins.concatMap (goList et) v) ];
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
            apply = b.coerceChain;
          };
        }
      ) immediateBindings;
    in
    {
      modules = immediateModules;
      deferredCoerce = deferredBindings;
    };

  mkInstanceRegistry =
    kindValue:
    let
      # Deferred guard — forced when kind is accessed, avoids infinite recursion
      # at option-declaration time when kindValue = eval.config.schema.host
      _guard =
        assert
          (kindValue ? kind && kindValue ? options)
          || throw "gen-schema: mkInstanceRegistry: expected a kind value (e.g., schema.host), got an attrset without 'kind' or 'options'";
        null;
      kind = builtins.seq _guard kindValue.kind;
    in
    {
      extraModules ? [ ],
      refs ? { },
      refinements ? { },
      strict ? kindValue.strict,
      description ? "${kind} instances",
      derive ? null,
      deriveEither ? null,
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
              in
              prelude.mapAttrs (
                _name: instance:
                builtins.foldl' (
                  inst: field:
                  let
                    binding = refResult.deferredCoerce.${field};
                    # Rebuild coerce chain with raw instances as registry —
                    # NOT the captured binding.instances (which may be config.X, causing cycles).
                    # Wrap custom coerce to inject registry as first arg when deferred:
                    # consumer writes: coerce = registry: default: val: ...
                    # gen-schema calls: wrappedCoerce default val (pre-applies registry)
                    wrappedCoerce = if binding.rawCustomCoerce != null then binding.rawCustomCoerce instances else null;
                    coerceChain = mkCoerceChain field kind instances wrappedCoerce binding.type;
                    rawValue = inst.${field} or null;
                  in
                  inst // { ${field} = coerceChain rawValue; }
                ) instance deferredFields
              ) instances;

          # Refinement pass: strict refinements throw immediately, lazy refinements
          # wrap values with addErrorContext for deferred checking at access time.
          effectiveRefinements = if refinements != { } then refinements else kindValue.refinements or { };

          refinementChecked =
            if effectiveRefinements == { } then
              coerced
            else
              prelude.mapAttrs (
                instanceName: instance:
                builtins.foldl' (
                  inst: fieldName:
                  let
                    refs' = effectiveRefinements.${fieldName};
                    value = inst.${fieldName} or null;
                  in
                  if value == null then
                    inst
                  else
                    let
                      failures = builtins.concatMap (
                        r:
                        if r.check value then
                          [ ]
                        else
                          [
                            {
                              inherit (r) message;
                              lazy = r.lazy or false;
                              field = "${kind}:${instanceName}.${fieldName}";
                              inherit value;
                            }
                          ]
                      ) refs';
                      strictFailures = builtins.filter (f: !f.lazy) failures;
                      lazyRefs = builtins.filter (r: r.lazy or false) refs';
                    in
                    if strictFailures != [ ] then
                      let
                        f = builtins.head strictFailures;
                      in
                      throw "gen-schema: refinement failed at ${f.field}\n  check: \"${f.message}\"\n  value: ${builtins.toJSON f.value}"
                    else if lazyRefs != [ ] then
                      let
                        wrapped = builtins.foldl' (
                          v: r:
                          builtins.addErrorContext
                            "gen-schema: lazy contract at ${kind}:${instanceName}.${fieldName}: \"${r.message}\""
                            (
                              if r.check v then
                                v
                              else
                                throw "gen-schema: lazy contract violated at ${kind}:${instanceName}.${fieldName}: ${r.message}"
                            )
                        ) value lazyRefs;
                      in
                      inst // { ${fieldName} = wrapped; }
                    else
                      inst
                ) instance (builtins.attrNames effectiveRefinements)
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
      default = { };
      type = merge.types.attrsOf (
        mkInstanceType kindValue {
          extraModules = allExtraModules;
          inherit strict;
        }
      );
      apply = applyPipeline;
    };
in
{
  inherit mkInstanceType mkInstanceRegistry;
}
