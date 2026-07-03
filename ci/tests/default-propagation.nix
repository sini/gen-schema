{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption mkInstanceRegistry;

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry eval.config.schema.host { };
        config.schema.host = {
          options.system = genMerge.mkOption { type = genMerge.types.str; };
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
          config.system = genMerge.mkDefault "x86_64-linux";
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
