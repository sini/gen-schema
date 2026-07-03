{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption schemaFn;

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.name = genMerge.mkOption { type = genMerge.types.str; };
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
          methods.ping = schemaFn "Ping command" genMerge.types.str ({ addr, ... }: "ping ${addr}");
        };
      }
      {
        config.schema.host = {
          methods.ssh = schemaFn "SSH command" genMerge.types.str ({ name, ... }: "ssh ${name}");
        };
      }
    ];
  };

  hostKind = eval.config.schema.host;

  instance = genMerge.evalModuleTree {
    modules = [
      hostKind
      {
        config.name = "igloo";
        config.addr = "10.0.0.1";
      }
    ];
  };
in
{
  flake.tests.method-compose.test-ping-from-module-a = {
    expr = instance.config.ping;
    expected = "ping 10.0.0.1";
  };
  flake.tests.method-compose.test-ssh-from-module-b = {
    expr = instance.config.ssh;
    expected = "ssh igloo";
  };
}
