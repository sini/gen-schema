{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkInstanceRegistry;

  schema = evalSchema { } [
    {
      config.schema.host = {
        options.addr = genMerge.mkOption { type = genMerge.types.str; };
      };
      config.schema.user = {
        options.shell = genMerge.mkOption {
          type = genMerge.types.str;
          default = "/bin/bash";
        };
      };
    }
  ];

  eval = genMerge.evalModuleTree { } [
    {
      options.hosts = mkInstanceRegistry {
        extraModules = [
          (
            { ... }:
            {
              options.users = mkInstanceRegistry { } schema.user;
            }
          )
        ];
      } schema.host;
      config.hosts.igloo = {
        addr = "10.0.1.1";
        users.tux = {
          shell = "/bin/zsh";
        };
      };
    }
  ];
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
