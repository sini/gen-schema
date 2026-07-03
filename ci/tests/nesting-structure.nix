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
        options.hosts = mkInstanceRegistry eval.config.schema.host {
          extraModules = [
            (
              { ... }:
              {
                options.users = mkInstanceRegistry eval.config.schema.user { };
              }
            )
          ];
        };
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.schema.user = {
          options.shell = genMerge.mkOption {
            type = genMerge.types.str;
            default = "/bin/bash";
          };
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
          users.tux = {
            shell = "/bin/zsh";
          };
        };
      }
    ];
  };
in
{
  flake.tests.nesting = {
    test-nested-user-name = {
      expr = eval.config.hosts.igloo.users.tux.name;
      expected = "tux";
    };
    test-nested-user-shell = {
      expr = eval.config.hosts.igloo.users.tux.shell;
      expected = "/bin/zsh";
    };
    test-host-still-works = {
      expr = eval.config.hosts.igloo.addr;
      expected = "10.0.1.1";
    };
    test-nested-user-has-id-hash = {
      expr = builtins.isString eval.config.hosts.igloo.users.tux.id_hash;
      expected = true;
    };
  };
}
