{ lib, genSchema, ... }:
let
  inherit (genSchema) mkSchemaOption schemaFn;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
          options.addr = lib.mkOption { type = lib.types.str; };
          methods.ping = schemaFn "Ping command" lib.types.str ({ addr, ... }: "ping ${addr}");
        };
      }
      {
        config.schema.host = {
          methods.ssh = schemaFn "SSH command" lib.types.str ({ name, ... }: "ssh ${name}");
        };
      }
    ];
  };

  hostKind = eval.config.schema.host;

  instance = lib.evalModules {
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
