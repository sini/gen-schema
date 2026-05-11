# den-schema Fleet Demo

A minimal fleet management example using den-schema as a standalone typed record registry. Demonstrates how to define entity kinds, create instance registries, enforce strict validation, and wire cross-instance references — all through flake-parts modules with import-tree.

## What This Showcases

### Schema Kinds

Each kind is a named record type with declared options. Undeclared keys error immediately with fix guidance (strict-by-default).

- **host** — machines in the fleet (`addr`, `system`, `role`)
- **user** — accounts (`userName`, `shell`)
- **service** — services running on hosts (`port`, `protocol`, `host` ref)

Kind definitions live in `modules/schema/` and are plain NixOS-style modules setting `config.schema.<kind>`.

### Instance Registries

`mkInstanceRegistry` creates a typed `attrsOf` option for each kind. Instances are validated against the kind's merged schema. Registries are declared in `modules/fleet/registries.nix`, instances in `modules/fleet/{hosts,users,services}.nix`.

### Features Exercised

| Feature | Where | What to look for |
|---|---|---|
| Strict validation | `modules/schema/host.nix` | Try adding `fleet.hosts.igloo.badKey = "x";` — errors with fix guidance |
| Default propagation | `modules/schema/host.nix` | `system = mkDefault "x86_64-linux"` — igloo inherits it, iceberg overrides |
| Identity hashing | `modules/outputs.nix` | `iglooHash` — deterministic SHA-256 from primitive options + kind prefix |
| Cross-instance refs | `modules/fleet/registries.nix` | `mkRefType config.fleet.hosts` on service's `host` option |
| Ref resolution | `modules/fleet/services.nix` | `host = "igloo"` resolves to the full host instance |
| flake-parts integration | `modules/schema.nix` | Single import of `den-schema.flakeModules.default` |
| import-tree | `flake.nix` | `inputs.import-tree ./modules` auto-imports all module files |

## Layout

```
flake.nix                         — flake-parts + import-tree + den-schema inputs
modules/
  schema.nix                      — imports den-schema flakeModule (provides schema option + schemaLib)
  schema/
    host.nix                      — host kind: addr, system, role
    user.nix                      — user kind: userName, shell
    service.nix                   — service kind: port, protocol
  fleet/
    registries.nix                — mkInstanceRegistry for hosts, users, services (+ mkRefType on service.host)
    hosts.nix                     — host instances: igloo (web), iceberg (db)
    users.nix                     — user instances: tux, yeti
    services.nix                  — service instances: nginx → igloo, postgres → iceberg
  outputs.nix                     — exposes fleet summary as flake.fleet
```

## Running

```bash
# Evaluate the fleet summary (from den-schema repo root):
cd templates/demo
nix eval --override-input den-schema ../.. .#fleet

# Expected output:
# {
#   hostNames = [ "iceberg" "igloo" ];
#   iglooAddr = "10.0.1.1";
#   iglooRole = "web";
#   iglooSystem = "x86_64-linux";
#   icebergSystem = "aarch64-linux";
#   nginxHost = "igloo";
#   nginxHostAddr = "10.0.1.1";
#   postgresHost = "iceberg";
#   ...
# }
```

## Extending

Add a new kind by creating a file in `modules/schema/`:

```nix
# modules/schema/network.nix
{ lib, ... }:
{
  config.schema.network = {
    options.cidr = lib.mkOption { type = lib.types.str; };
    options.gateway = lib.mkOption { type = lib.types.str; };
  };
}
```

Add a registry in `modules/fleet/registries.nix`:

```nix
options.fleet.networks = mkInstanceRegistry config.schema "network" {};
```

Add instances in a new file `modules/fleet/networks.nix`:

```nix
{ ... }:
{
  fleet.networks.lan = { cidr = "10.0.1.0/24"; gateway = "10.0.1.1"; };
}
```

import-tree picks up the new file automatically — no manual wiring needed.
