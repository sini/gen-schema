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

  mkInstanceRegistry =
    schema: kind:
    {
      extraModules ? [ ],
      strict ? schema._strict or true,
      description ? "${kind} instances",
      derive ? null,
      deriveEither ? null,
    }:
    assert
      !(derive != null && deriveEither != null)
      || throw "mkInstanceRegistry: derive and deriveEither are mutually exclusive";
    let
      formatErrors =
        failures:
        lib.concatMapStringsSep "\n" (f: "  ${kind} '${f.name}': ${f.validator} — ${f.message}") failures;

      defaultOnError =
        left:
        if builtins.isList left then
          throw "schema validation failed:\n${formatErrors left}"
        else
          throw "derive: ${builtins.toJSON left}";

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
          validators = schema.${kind}.validators or [ ];

          # Step 1: validate. onError either throws (terminating) or returns
          # a recovery overlay applied to the original instances.
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

          # Step 2: derive enrichment from the validated set.
          derived =
            if deriveFn == null then { }
            else deriveFn validated;
        in
        # Step 3: overlay derived config at high priority.
        lib.mapAttrs (name: instance: instance // (derived.${name} or { })) validated;
    in
    lib.mkOption {
      inherit description;
      default = { };
      type = lib.types.attrsOf (mkInstanceType schema kind { inherit extraModules strict; });
      apply = applyPipeline;
    };
in
{
  inherit mkInstanceType mkInstanceRegistry;
}
