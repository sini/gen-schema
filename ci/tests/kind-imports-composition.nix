# Kind-to-kind inheritance: the motivating case for moving strict/identity to instance level.
# Multiple kinds inheriting a shared base kind should not cause duplicate module conflicts when
# instantiated. The relation travels as a NAME through `inherits`, resolved by `evalSchema` against
# the frozen output of a strictly earlier pass.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkInstanceRegistry;

  schema = evalSchema {
    modules = [
      {
        # Shared base kind
        config.schema.conf = {
          options.description = genMerge.mkOption {
            type = genMerge.types.str;
            default = "";
          };
        };

        # Host and user both inherit conf
        config.schema.host = {
          inherits = [ "conf" ];
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.schema.user = {
          inherits = [ "conf" ];
          options.shell = genMerge.mkOption {
            type = genMerge.types.str;
            default = "/bin/bash";
          };
        };
      }
    ];
  };

  eval = genMerge.evalModuleTree {
    modules = [
      {
        # Instantiate both — should not conflict
        options.hosts = mkInstanceRegistry schema.host { };
        options.users = mkInstanceRegistry schema.user { };

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
