{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchema mkInstanceRegistry;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchema { };
        options.hosts = mkInstanceRegistry eval.config.schema "host" {
          extraModules = [
            (
              { ... }:
              {
                options.users = mkInstanceRegistry eval.config.schema "user" { };
              }
            )
          ];
        };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
        };
        config.schema.user = {
          options.shell = lib.mkOption {
            type = lib.types.str;
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
  nesting = {
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
