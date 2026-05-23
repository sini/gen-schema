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
  lib,
  mkStrictModule,
  mkIdentityModule,
  runValidators,
  defaultOnError,
  refsFromOptionsWithTypes,
  dedupByHash,
}:
let
  mkInstanceType =
    schema: kind:
    {
      extraModules ? [ ],
      strict ? schema._strict or true,
    }:
    lib.types.submodule (
      { name, config, ... }:
      {
        imports = [
          schema.${kind}
        ]
        ++ [
          (
            if strict then
              mkStrictModule kind
            else
              { _module.freeformType = lib.types.attrsOf lib.types.anything; }
          )
          (mkIdentityModule kind)
        ]
        ++ extraModules;
        config._module.args.${kind} = config;
        options.name = lib.mkOption {
          type = lib.types.str;
          default = name;
        };
        # Scope-engine node ID: canonical "kind:name" format for graph construction.
        options.nodeId = lib.mkOption {
          type = lib.types.str;
          internal = true;
          readOnly = true;
          default = "${kind}:${name}";
          description = "Scope graph node identifier.";
        };
      }
    );

  findRefFields =
    schema: kind:
    let
      evaled = lib.evalModules { modules = [ schema.${kind} ]; };
    in
    refsFromOptionsWithTypes evaled.options;

  # Build a coercion function matching the nesting structure of a ref type.
  # Walks the type tree at binding time so the runtime dispatch is exact.
  # Supports optional custom coerce hooks for domain-specific resolution.
  mkCoerceChain =
    field: kind: registry: customCoerce: type:
    let
      defaultCoerce =
        v:
        if builtins.isString v then
          if registry ? ${v} then
            registry.${v}
          else
            throw "ref field '${field}' on kind '${kind}': reference '${v}' not found in instance registry (available: ${builtins.concatStringsSep ", " (builtins.attrNames registry)})"
        else
          v;

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
            throw "ref field '${field}' on kind '${kind}': custom coerce returned a list in scalar context (use listOf ref for 1-to-many expansion)"
          else
            result;

      # List-element leaf: custom coerce receives [ defaultResult ] and raw value.
      # Returns a list (1→many expansion supported).
      mkListCoerce =
        v: if customCoerce == null then [ (defaultCoerce v) ] else customCoerce [ (defaultCoerce v) ] v;

      go =
        t:
        if (t.refKind or null) != null then
          mkLeafCoerce
        else
          let
            et = (t.nestedTypes or { }).elemType or null;
            name = t.name or "";
          in
          if et == null then
            mkLeafCoerce
          else
            let
              inner = go et;
            in
            if name == "nullOr" then
              v: if v == null then null else inner v
            else if t.isSetOf or false then
              # setOf: coerce + expand via concatMap, then deduplicate by id_hash
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
        if (t.refKind or null) != null then
          mkListCoerce
        else
          let
            et = (t.nestedTypes or { }).elemType or null;
            name = t.name or "";
          in
          if et == null then
            v: [ (mkLeafCoerce v) ]
          else
            let
              inner = go et;
            in
            if name == "nullOr" then
              v: [ (if v == null then null else inner v) ]
            else if t.isSetOf or false then
              let
                listInner = goList et;
              in
              v: [ (dedupByHash (builtins.concatMap listInner v)) ]
            else
              v: [ (builtins.concatMap (goList et) v) ];
    in
    go type;

  # Build extra modules that override deferred ref fields with resolved types.
  mkRefBindingModules =
    kind: refs: refFields:
    let
      # Validate: every deferred ref field must have a binding.
      # N.B. Missing-binding check is duplicated in applyPipeline.refValidation
      # for the refs == {} case — keep error messages in sync.
      missingBindings = lib.filterAttrs (field: _: !(refs ? ${field})) refFields;
      extraBindings = lib.filterAttrs (field: _: !(refFields ? ${field})) refs;

      _ =
        if missingBindings != { } then
          let
            missing = builtins.head (lib.attrNames missingBindings);
            targetKind = missingBindings.${missing}.refKind;
          in
          throw "mkInstanceRegistry: kind '${kind}' has ref field '${missing}' targeting kind '${targetKind}' but no refs.${missing} binding was provided"
        else if extraBindings != { } then
          let
            extra = builtins.head (lib.attrNames extraBindings);
          in
          throw "mkInstanceRegistry: refs.${extra} does not match any ref field on kind '${kind}'"
        else
          null;
    in
    builtins.seq _ (
      lib.mapAttrsToList (
        field: binding:
        let
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
          coerceChain = mkCoerceChain field kind norm.registry norm.customCoerce fieldInfo.type;
        in
        { ... }:
        {
          options.${field} = lib.mkOption {
            apply = coerceChain;
          };
        }
      ) refs
    );

  mkInstanceRegistry =
    schema: kind:
    {
      extraModules ? [ ],
      refs ? { },
      strict ? schema._strict or true,
      description ? "${kind} instances",
      derive ? null,
      deriveEither ? null,
    }:
    assert
      (derive == null || deriveEither == null)
      || throw "mkInstanceRegistry: derive and deriveEither are mutually exclusive";
    let
      # Resolve deferred refs: scan kind options, validate bindings, build override modules.
      # findRefFields evaluates schema.${kind}, which isn't available at option-declaration
      # time (circular), so only call it when refs are provided.  Binding validation for the
      # missing-refs case is deferred to applyPipeline where schema access is safe.
      refFields = if refs == { } then { } else findRefFields schema kind;
      refModules = if refs == { } then [ ] else mkRefBindingModules kind refs refFields;
      allExtraModules = extraModules ++ refModules;

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
      # Validators are read lazily inside apply — schema.${kind}.validators
      # is only forced when instances are actually evaluated, not at
      # mkInstanceRegistry call time (avoids circular eval in self-referential patterns).
      applyPipeline =
        instances:
        let
          # Ref binding validation — deferred to apply time so schema.${kind} is safe
          # to evaluate (avoids circular eval at option-declaration time).
          # Force ref module validation (extra-binding case) and check for missing
          # bindings (refs == {} but schema declares ref fields).
          # N.B. The missing-binding check here mirrors mkRefBindingModules (line ~72),
          # which can't run when refs == {} — keep error messages in sync.
          refValidation =
            let
              allRefFields = findRefFields schema kind;
              missingBindings = lib.filterAttrs (field: _: !(refs ? ${field})) allRefFields;
            in
            if missingBindings != { } then
              let
                missing = builtins.head (lib.attrNames missingBindings);
                targetKind = missingBindings.${missing}.refKind;
              in
              throw "mkInstanceRegistry: kind '${kind}' has ref field '${missing}' targeting kind '${targetKind}' but no refs.${missing} binding was provided"
            else
              builtins.length refModules; # forces builtins.seq inside mkRefBindingModules

          validators = builtins.seq refValidation (schema.${kind}.validators or [ ]);

          # null = no validation errors (fast path when validators == []).
          # This avoids constructing an Either when there are no validators,
          # which is the common case for registries without validation.
          vResult =
            if validators == [ ] then
              null
            else
              let
                r = runValidators kind validators instances;
              in
              if r ? right then null else r.left;

          validated =
            if vResult == null then
              instances
            else
              let
                recovery = onError vResult;
              in
              lib.mapAttrs (name: instance: instance // (recovery.${name} or { })) instances;

          derived = if deriveFn == null then { } else deriveFn validated;
        in
        if derived == { } then
          validated
        else
          lib.mapAttrs (name: instance: instance // (derived.${name} or { })) validated;
    in
    lib.mkOption {
      inherit description;
      default = { };
      type = lib.types.attrsOf (
        mkInstanceType schema kind {
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
