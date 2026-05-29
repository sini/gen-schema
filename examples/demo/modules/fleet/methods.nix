# Declarative methods on host instances.
#
# Methods are declared as collections on schema kinds. The function's named
# arguments are automatically resolved from the instance's config. The
# function body can also close over values from the module scope — here
# we capture config.fleet.services to implement cross-registry queries.
{
  lib,
  config,
  genSchema,
  ...
}:
let
  inherit (genSchema) schemaFn;
in
{
  config.schema.host.methods = {
    # Check if a named service targets this host.
    # Closes over fleet.services; receives `name` from the host instance.
    hasService =
      schemaFn "Check whether a named service targets this host." (lib.types.functionTo lib.types.bool)
        (
          { name, ... }:
          serviceName:
          let
            inherit (config.fleet) services;
          in
          services ? ${serviceName} && services.${serviceName}.host.name == name
        );

    # Return a description string for this host.
    # All named args (name, role, addr) resolved from instance config.
    describe = schemaFn "Human-readable summary of this host." lib.types.str (
      {
        name,
        role,
        addr,
        ...
      }:
      "${name} (${role}) at ${addr}"
    );
  };
}
