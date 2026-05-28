# Kind-to-kind imports composition: the motivating case for moving
# strict/identity to instance level. Multiple kinds importing a shared
# base kind should not cause duplicate module conflicts when instantiated.
{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption mkInstanceRegistry;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };

        # Shared base kind
        config.schema.conf = {
          options.description = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
        };

        # Host and user both import conf
        config.schema.host = {
          imports = [ eval.config.schema.conf ];
          options.addr = lib.mkOption { type = lib.types.str; };
        };
        config.schema.user = {
          imports = [ eval.config.schema.conf ];
          options.shell = lib.mkOption {
            type = lib.types.str;
            default = "/bin/bash";
          };
        };

        # Instantiate both — should not conflict
        options.hosts = mkInstanceRegistry eval.config.schema "host" { };
        options.users = mkInstanceRegistry eval.config.schema "user" { };

        config.hosts.igloo = {
          addr = "10.0.1.1";
          description = "main server";
        };
        config.users.tux = {
          shell = "/bin/zsh";
        };
      }
    ];
  };
in
{
  flake.tests."kind-imports".test-host-gets-base-option = {
    expr = eval.config.hosts.igloo.description;
    expected = "main server";
  };
  flake.tests."kind-imports".test-user-gets-base-default = {
    expr = eval.config.users.tux.description;
    expected = "";
  };
  flake.tests."kind-imports".test-host-own-option = {
    expr = eval.config.hosts.igloo.addr;
    expected = "10.0.1.1";
  };
  flake.tests."kind-imports".test-user-own-option = {
    expr = eval.config.users.tux.shell;
    expected = "/bin/zsh";
  };
  flake.tests."kind-imports".test-both-have-id-hash = {
    expr =
      (builtins.isString eval.config.hosts.igloo.id_hash)
      && (builtins.isString eval.config.users.tux.id_hash);
    expected = true;
  };
  flake.tests."kind-imports".test-cross-kind-hashes-differ = {
    expr = eval.config.hosts.igloo.id_hash != eval.config.users.tux.id_hash;
    expected = true;
  };
}
