{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption mkInstanceRegistry;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry eval.config.schema "host" { };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
          options.role = lib.mkOption { type = lib.types.str; };
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
          role = "server";
        };
        config.hosts.yurt = {
          addr = "10.0.1.2";
          role = "desktop";
        };
      }
    ];
  };
in
{
  instance-registry = {
    test-registry-keys = {
      expr = builtins.attrNames eval.config.hosts;
      expected = [
        "igloo"
        "yurt"
      ];
    };
    test-igloo-addr = {
      expr = eval.config.hosts.igloo.addr;
      expected = "10.0.1.1";
    };
    test-yurt-role = {
      expr = eval.config.hosts.yurt.role;
      expected = "desktop";
    };
    test-names-match-keys = {
      expr = lib.mapAttrsToList (_: v: v.name) eval.config.hosts;
      expected = [
        "igloo"
        "yurt"
      ];
    };
  };
}
