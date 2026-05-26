{ lib, schemaLib, ... }:
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
          derive = instances: lib.mapAttrs (name: _: { tag = "derived-${name}"; }) instances;
        };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
        };
        config.hosts.igloo.addr = "10.0.1.1";
        config.hosts.iceberg.addr = "10.0.1.2";
      }
    ];
  };
in
{
  "derive-plain" = {
    test-igloo-tag = {
      expr = eval.config.hosts.igloo.tag;
      expected = "derived-igloo";
    };
    test-iceberg-tag = {
      expr = eval.config.hosts.iceberg.tag;
      expected = "derived-iceberg";
    };
    test-addr-preserved = {
      expr = eval.config.hosts.igloo.addr;
      expected = "10.0.1.1";
    };
  };
}
