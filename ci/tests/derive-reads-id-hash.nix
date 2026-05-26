{ lib, schemaLib, ... }:
let
  eval = lib.evalModules {
    modules = [
      {
        options.schema = schemaLib.mkSchemaOption { };
        options.hosts = schemaLib.mkInstanceRegistry eval.config.schema "host" {
          extraModules = [
            {
              options.hashPrefix = lib.mkOption {
                type = lib.types.str;
                readOnly = true;
                internal = true;
              };
            }
          ];
          derive =
            instances: lib.mapAttrs (_: inst: { hashPrefix = builtins.substring 0 8 inst.id_hash; }) instances;
        };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
        };
        config.hosts.igloo.addr = "10.0.1.1";
      }
    ];
  };
in
{
  "derive-hash" = {
    test-hash-prefix-length = {
      expr = builtins.stringLength eval.config.hosts.igloo.hashPrefix;
      expected = 8;
    };
    test-hash-prefix-matches = {
      expr = eval.config.hosts.igloo.hashPrefix;
      expected = builtins.substring 0 8 eval.config.hosts.igloo.id_hash;
    };
  };
}
