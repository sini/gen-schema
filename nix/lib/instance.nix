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
}:
let
  # `name` is a reserved option on all instance types — it defaults to the
  # attrset key and is always `types.str`. If a schema kind declares its own
  # `options.name` with the same type, the declarations merge harmlessly.
  mkInstanceType =
    schema: kind:
    {
      extraModules ? [ ],
      strict ? schema._strict or true,
    }:
    lib.types.submodule (
      { name, config, ... }:
      {
        imports =
          [ schema.${kind} ]
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
    }:
    lib.mkOption {
      inherit description;
      default = { };
      type = lib.types.attrsOf (mkInstanceType schema kind { inherit extraModules strict; });
    };
in
{
  inherit mkInstanceType mkInstanceRegistry;
}
