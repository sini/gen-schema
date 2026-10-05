{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption schemaFn;

  eval = genMerge.evalModuleTree { } [
    {
      options.schema = mkSchemaOption { };
      config.schema.host = {
        options.name = genMerge.mkOption { type = genMerge.types.str; };
        options.addr = genMerge.mkOption { type = genMerge.types.str; };
        methods.ping = schemaFn {
          description = "Ping command";
          type = genMerge.types.str;
          fn = { addr, ... }: "ping ${addr}";
        };
      };
    }
    {
      config.schema.host = {
        methods.ssh = schemaFn {
          description = "SSH command";
          type = genMerge.types.str;
          fn = { name, ... }: "ssh ${name}";
        };
      };
    }
  ];

  hostKind = eval.config.schema.host;

  instance = genMerge.evalModuleTree { } [
    hostKind
    {
      config.name = "igloo";
      config.addr = "10.0.0.1";
    }
  ];
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
