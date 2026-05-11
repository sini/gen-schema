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

## Why den-schema Over Bare Submodules

The NixOS module system gives you `lib.types.submodule` — a typed record with options, defaults, and merge semantics. You can build entity registries with `attrsOf submodule` directly. den-schema is built on top of this, not instead of it. The question is what you get for the extra layer.

### Bare submodule approach

```nix
# Define the type inline:
hostType = lib.types.submodule ({ name, config, ... }: {
  options.name = lib.mkOption { type = str; default = name; };
  options.addr = lib.mkOption { type = str; };
  options.system = lib.mkOption { type = str; };
  options.role = lib.mkOption { type = str; };
  config.system = lib.mkDefault "x86_64-linux";
});

# Use it:
options.hosts = lib.mkOption {
  type = lib.types.attrsOf hostType;
  default = {};
};
```

This works. You get typed fields, defaults, and merge. For a single file or a small project, it's the right choice.

### Where it breaks down

**Extension from other modules.** With bare submodules, `hostType` is a closed value — defined in one place, consumed everywhere. If a second flake input wants to add a `vpnAlias` field to every host, it can't. It would need to wrap `hostType` in another submodule and hope the merge works. With den-schema, any module can extend any kind:

```nix
# In your flake:
config.schema.host.options.addr = lib.mkOption { type = str; };

# In an external input's module:
config.schema.host.options.vpnAlias = lib.mkOption { type = str; default = config.name; };
```

Both contributions merge through `deferredModule` — the kind type is open, not closed.

**Typo detection.** Bare `attrsOf submodule` is freeform by default. Setting `hosts.igloo.addrr = "10.0.1.1"` (typo) silently creates an untyped attribute. You find out at deploy time, or never. den-schema is strict by default — undeclared keys error immediately with a message telling you how to declare them.

**Identity comparison.** Nix's `==` on module system values does deep structural comparison that can diverge or infinitely recurse across different thunks of the same entity. With bare submodules, comparing two references to the same host requires careful workarounds. den-schema auto-computes `id_hash` from primitive options — a cheap string comparison that's safe across module system boundaries.

**Cross-instance references.** Bare submodules have no notion of references between registries. If a service needs to point at a host, you'd use a string and manually look it up. den-schema's `mkRefType` validates the reference at eval time and resolves it to the target instance — `config.services.nginx.host.addr` works directly.

**Introspection.** With bare submodules, there's no way to ask "what kinds exist?" or "what options does a host have?" without evaluating an instance. den-schema's `_meta.kindNames` and `_meta.kindMeta` provide this at the schema level — the foundation for documentation generation, tooling, and diag.

### Comparison

| Concern | Bare `attrsOf submodule` | den-schema |
|---|---|---|
| Type definition | Closed value in one file | Open — any module can extend via `config.schema.<kind>` |
| Undeclared keys | Silently accepted (freeform default) | Error with fix guidance (strict default) |
| Entity comparison | `==` (fragile, can diverge) | `id_hash` (cheap, deterministic) |
| Cross-references | Manual string lookup | `mkRefType` — validated, resolves to instance |
| Defaults | `config.x = mkDefault val` (same) | Same — deferred module merge preserves this |
| Introspection | None without evaluating instances | `_meta.kindNames`, `_meta.kindMeta` |
| Declarative methods | Manual `functionTo` options + config wiring | `schemaFn` — auto-resolves config args |
| Documentation | Write it yourself | `renderDocs` generates from schema metadata |
| Dependencies | None | nixpkgs only |
| Overhead | None | Thin layer (~330 lines) over `deferredModule` + `submodule` |

### When to use which

**Bare submodule:** single-file projects, internal types that won't be extended, types where freeform is intentional (e.g., arbitrary user-defined metadata).

**den-schema:** multi-module projects, types extended across flake inputs, entity registries where typos matter, anything where you need safe cross-instance references or introspection.

den-schema doesn't replace the module system — it's a pattern library on top of it. Every `mkSchemaOption`, `mkInstanceType`, and `mkRefType` produces standard module system types. You can mix den-schema kinds with bare submodules in the same project.

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
