{
  lib,
}:
let
  # `name` is a reserved option on all instance types — it defaults to the
  # attrset key and is always `types.str`. If a schema kind declares its own
  # `options.name` with the same type, the declarations merge harmlessly.
  mkInstanceType =
    schema: kind:
    {
      extraModules ? [ ],
    }:
    lib.types.submodule (
      { name, config, ... }:
      {
        imports = [ schema.${kind} ] ++ extraModules;
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
      description ? "${kind} instances",
    }:
    lib.mkOption {
      inherit description;
      default = { };
      type = lib.types.attrsOf (mkInstanceType schema kind { inherit extraModules; });
    };
in
{
  inherit mkInstanceType mkInstanceRegistry;
}
