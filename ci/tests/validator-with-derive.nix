{
  lib,
  schemaLib,
  genLib,
  ...
}:
let
  eval = lib.evalModules {
    modules = [
      {
        options.schema = schemaLib.mkSchemaOption { };
        options.hosts = schemaLib.mkInstanceRegistry eval.config.schema "host" {
          extraModules = [
            {
              options.tag = lib.mkOption {
                type = lib.types.str;
                readOnly = true;
                internal = true;
              };
            }
          ];
          derive = instances: lib.mapAttrs (name: _: { tag = "valid-${name}"; }) instances;
        };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
          validators = [
            (genLib.mkValidator "has-addr" ({ addr, ... }: addr != "") "addr must not be empty")
          ];
        };
        config.hosts.igloo.addr = "10.0.1.1";
      }
    ];
  };
in
{
  flake.tests."validator-derive" = {
    test-tag-applied = {
      expr = eval.config.hosts.igloo.tag;
      expected = "valid-igloo";
    };
    test-addr-preserved = {
      expr = eval.config.hosts.igloo.addr;
      expected = "10.0.1.1";
    };
  };
}
