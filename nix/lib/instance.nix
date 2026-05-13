# Instance type and registry constructors.
#
# Instances add the infrastructure that bare schema kinds don't have:
# strict validation, identity hashing, and the `name` option. This means
# kind-level composition (imports between kinds) is pure schema merging,
# while instance-level evaluation gets strict + id_hash injected once.
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

      validators = schema.${kind}.validators or [ ];

      hasPipeline = derive != null || deriveEither != null;

      applyPipeline =
        instances:
        let
          validationResult =
            if validators == [ ] then { right = instances; } else runValidators kind validators instances;

          # When validation fails and onError doesn't throw, use original
          # instances with onError's return as the derived overlay.
          validated = if validationResult ? right then validationResult.right else instances;

          derived =
            if !(validationResult ? right) then
              onError validationResult.left
            else if deriveFn == null then
              { }
            else
              deriveFn validated;
        in
        lib.mapAttrs (name: instance: instance // (derived.${name} or { })) validated;
    in
    lib.mkOption (
      {
        inherit description;
        default = { };
        type = lib.types.attrsOf (mkInstanceType schema kind { inherit extraModules strict; });
      }
      // lib.optionalAttrs hasPipeline { apply = applyPipeline; }
    );
in
{
  inherit mkInstanceType mkInstanceRegistry;
}
