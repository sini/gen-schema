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
  refsFromOptions,
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
      }
    );

  findRefFields =
    schema: kind:
    let
      evaled = lib.evalModules { modules = [ schema.${kind} ]; };
    in
    refsFromOptions evaled.options;

  # Build extra modules that override deferred ref fields with resolved types.
  mkRefBindingModules =
    kind: refs: refFields:
    let
      # Validate: every deferred ref field must have a binding
      missingBindings = lib.filterAttrs (field: _: !(refs ? ${field})) refFields;
      extraBindings = lib.filterAttrs (field: _: !(refFields ? ${field})) refs;

      _ =
        if missingBindings != { } then
          let
            missing = builtins.head (lib.attrNames missingBindings);
            targetKind = missingBindings.${missing};
          in
          throw "mkInstanceRegistry: kind '${kind}' has ref field '${missing}' targeting kind '${targetKind}' but no refs.${missing} binding was provided"
        else if extraBindings != { } then
          let extra = builtins.head (lib.attrNames extraBindings);
          in throw "mkInstanceRegistry: refs.${extra} does not match any ref field on kind '${kind}'"
        else
          null;
    in
    builtins.seq _ (
      lib.mapAttrsToList (
        field: registry:
        { ... }:
        {
          options.${field} = lib.mkOption {
            apply = val:
              if builtins.isString val then
                if registry ? ${val} then
                  registry.${val}
                else
                  throw "ref field '${field}' on kind '${kind}': reference '${val}' not found in instance registry"
              else
                val;
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
    assert (derive == null || deriveEither == null)
      || throw "mkInstanceRegistry: derive and deriveEither are mutually exclusive";
    let
      # Resolve deferred refs: scan kind options, validate bindings, build override modules.
      refFields = if refs == { } then { } else findRefFields schema kind;
      refModules = if refs == { } then [ ] else mkRefBindingModules kind refs refFields;
      allExtraModules = extraModules ++ refModules;

      onError =
        if deriveEither != null then
          deriveEither.onError or defaultOnError
        else
          defaultOnError;

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
          validators = schema.${kind}.validators or [ ];

          # null = no validation errors (fast path when validators == []).
          # This avoids constructing an Either when there are no validators,
          # which is the common case for registries without validation.
          vResult =
            if validators == [ ] then null
            else
              let r = runValidators kind validators instances;
              in if r ? right then null else r.left;

          validated =
            if vResult == null then instances
            else
              let recovery = onError vResult;
              in lib.mapAttrs (name: instance:
                instance // (recovery.${name} or { })
              ) instances;

          derived =
            if deriveFn == null then { }
            else deriveFn validated;
        in
        if derived == { } then validated
        else lib.mapAttrs (name: instance: instance // (derived.${name} or { })) validated;
    in
    lib.mkOption {
      inherit description;
      default = { };
      type = lib.types.attrsOf (mkInstanceType schema kind { extraModules = allExtraModules; inherit strict; });
      apply = applyPipeline;
    };
in
{
  inherit mkInstanceType mkInstanceRegistry;
}
