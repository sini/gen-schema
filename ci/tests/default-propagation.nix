{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption mkInstanceRegistry;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry eval.config.schema.host { };
        config.schema.host = {
          options.system = lib.mkOption { type = lib.types.str; };
          options.addr = lib.mkOption { type = lib.types.str; };
          config.system = lib.mkDefault "x86_64-linux";
        };
        config.hosts.igloo.addr = "10.0.1.1";
        config.hosts.yurt = {
          addr = "10.0.1.2";
          system = "aarch64-linux";
        };
      }
    ];
  };
in
{
  flake.tests.defaults = {
    test-default-propagates = {
      expr = eval.config.hosts.igloo.system;
      expected = "x86_64-linux";
    };
    test-override-works = {
      expr = eval.config.hosts.yurt.system;
      expected = "aarch64-linux";
    };
  };
}
