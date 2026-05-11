# den-schema

A typed record registry for Nix with extension points, strict validation, identity hashing, cross-instance references, introspection, and declarative methods. Built on the NixOS module system.

den-schema gives you what `lib.types.submodule` doesn't: open kind definitions that any module can extend, strict-by-default validation that catches typos immediately, stable identity comparison via `id_hash`, cross-registry references that resolve to instances, and auto-generated documentation from your schema.

## Quick Start

### As a flake-parts module

```nix
# flake.nix
{
  inputs.den-schema.url = "github:denful/den-schema";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [ inputs.den-schema.flakeModules.default ];

    # Define kinds
    schema.host = {
      options.addr = lib.mkOption { type = lib.types.str; };
      options.role = lib.mkOption { type = lib.types.str; default = "worker"; };
    };
  };
}
```

### Programmatic use

```nix
# Without flake-parts — call the library directly
let
  schemaLib = den-schema.lib;
  # or: schemaLib = import ./path/to/den-schema/nix/lib { inherit lib; };
in
lib.evalModules {
  modules = [{
    options.schema = schemaLib.mkSchemaOption {};
    config.schema.host.options.addr = lib.mkOption { type = lib.types.str; };
  }];
}
```

### Without flakes

```nix
let
  schemaLib = import ./path/to/den-schema { inherit lib; };
in
# use schemaLib.mkSchemaOption, schemaLib.mkInstanceRegistry, etc.
```

## Core Concepts

### Kinds

A **kind** is a named record type. Declare one by setting `config.schema.<name>`:

```nix
config.schema.host = {
  options.addr = lib.mkOption { type = lib.types.str; };
  options.system = lib.mkOption { type = lib.types.str; };
  options.role = lib.mkOption { type = lib.types.str; };
  config.system = lib.mkDefault "x86_64-linux";
};
```

Kinds are deferred modules — they define options and config but aren't evaluated until imported by an instance.

### Extension

Any module can extend any kind. Extensions merge through deferred module merge:

```nix
# Module A declares base host options
config.schema.host.options.addr = lib.mkOption { type = str; };

# Module B (maybe from another flake input) adds monitoring fields
config.schema.host.options.metricsPort = lib.mkOption { type = int; default = 9100; };
config.schema.host.options.monitored = lib.mkOption { type = bool; default = true; };
```

Both contributions merge cleanly. Neither module needs to know about the other.

### Strict Validation

Kinds are **strict by default** — undeclared keys error immediately with a fix suggestion:

```
STRICT MODE: "addrr" is not declared on host.
Fix: schema.host.options.addrr = lib.mkOption { ... };
```

Opt out per-kind:

```nix
config.schema.host._module.freeformType = lib.types.attrsOf lib.types.anything;
```

Or globally:

```nix
options.schema = schemaLib.mkSchemaOption { strict = false; };
```

### Instances

**Instances** are concrete values of a kind. Create them with `mkInstanceRegistry`:

```nix
options.fleet.hosts = schemaLib.mkInstanceRegistry config.schema "host" {};

config.fleet.hosts.igloo = {
  addr = "10.0.1.1";
  role = "web";
  # system defaults to "x86_64-linux"
};

config.fleet.hosts.iceberg = {
  addr = "10.0.2.1";
  system = "aarch64-linux";
};
```

Each instance:
- Gets a `name` option defaulting to the attrset key
- Gets `_module.args.<kind> = config` for self-reference
- Gets `id_hash` — a stable SHA-256 for safe comparison
- Inherits the kind's strict/freeform setting

### Identity Hashing

Nix's `==` on module system values can diverge or infinitely recurse. `id_hash` gives you a cheap, stable string comparison:

```nix
# Safe entity comparison
builtins.filter (h: h.id_hash != host.id_hash) allHosts

# Set membership
lib.elem target.id_hash (map (h: h.id_hash) candidates)
```

The hash is computed from all non-internal primitive options (str, int, bool), prefixed by the kind name. Two hosts with the same values hash identically. A host and a user with the same name hash differently (kind prefix).

**Three-layer precedence for key selection:**

1. **Explicit `_identity.keys`** — list the exact keys. Multiple modules can contribute via `mkMerge`.
2. **`identity = false`** — exclude individual options from reflection.
3. **Auto-reflection** — all non-internal primitives included (default).

```nix
# Layer 1: explicit keys
config.schema.host.config._identity.keys = [ "name" "addr" ];

# Layer 2: exclude an option
options.description = lib.mkOption { type = str; } // { identity = false; };

# Layer 3: automatic (default) — all non-internal str/int/bool options
```

### Cross-Instance References

`mkRefType` creates a type that validates a string key against a registry and resolves to the target instance:

```nix
options.fleet.services = schemaLib.mkInstanceRegistry config.schema "service" {
  extraModules = [({ ... }: {
    options.host = lib.mkOption {
      type = schemaLib.mkRefType config.fleet.hosts;
      description = "Host this service runs on";
    };
  })];
};

config.fleet.services.nginx = {
  host = "igloo";  # string in, instance out
  port = 80;
};

# Resolves to the full host instance:
config.fleet.services.nginx.host.addr  # → "10.0.1.1"
config.fleet.services.nginx.host.id_hash  # → "b3e6bb..."
```

Invalid references throw at eval time:

```
services.nginx.host: reference 'nonexistent' not found in instance registry
```

### Kind Mix-ins

A kind can import another kind's schema, inheriting all options:

```nix
config.schema.user = {
  options.userName = lib.mkOption { type = str; };
  options.shell = lib.mkOption { type = str; default = "/bin/bash"; };
};

config.schema.admin-user = {
  imports = [ config.schema.user ];  # inherits userName, shell
  options.sudoPrivileges = lib.mkOption { type = bool; default = true; };
  options.sshKeys = lib.mkOption { type = listOf str; default = []; };
};
```

Each gets its own registry. Identity hashes include the kind prefix — a user "root" and an admin "root" hash differently.

Multiple mix-ins compose cleanly:

```nix
config.schema.deploy-user = {
  imports = [
    config.schema.user
    config.schema.ssh-access
    config.schema.sudo-access
  ];
};
```

### Declarative Methods

`schemaFn` declares functions on entity instances. Named arguments are automatically resolved from the instance's config:

```nix
config.schema.host.methods.describe = schemaLib.schemaFn
  "Human-readable summary"
  lib.types.str
  ({ name, role, addr, ... }: "${name} (${role}) at ${addr}");

# On instances:
config.fleet.hosts.igloo.describe  # → "igloo (web) at 10.0.1.1"
```

Methods can close over values from the declaring module's scope:

```nix
# hasService captures config.fleet.services from the module;
# name comes from the host instance's config
config.schema.host.methods.hasService = schemaLib.schemaFn
  "Check if a service targets this host"
  (lib.types.functionTo lib.types.bool)
  ({ name, ... }:
    serviceName:
    let services = config.fleet.services;
    in services ? ${serviceName}
       && services.${serviceName}.host.name == name);

config.fleet.hosts.igloo.hasService "nginx"     # → true
config.fleet.hosts.igloo.hasService "postgres"   # → false
```

Methods with arguments that don't match any config key produce a clear error:

```
method 'bad' on host: references config keys 'nonexistent' which are not declared on this kind
```

### Sidecar Fields

Declare custom sidecar fields on kinds — data extracted from definitions before module merge and exposed on the merged result:

```nix
options.schema = schemaLib.mkSchemaOption {
  sidecars = {
    includes = { default = []; };           # list → merged via ++
    excludes = { default = []; };           # list → merged via ++
    metadata = { default = {}; };           # attrset → merged via //
    priority = { default = 0; merge = _acc: val: val; };  # explicit: last-wins
  };
};

config.schema.host = {
  includes = [ policy-a policy-b ];
  options.addr = lib.mkOption { type = str; };
};

# Read sidecar values directly:
config.schema.host.includes  # → [ policy-a policy-b ]
```

Merge strategy is inferred from the default type (list → `++`, attrset → `//`) or set explicitly. Sidecar keys are stripped before the deferred module merge — they never leak into the module system.

`methods` is a built-in sidecar. User-declared sidecars are additional.

### Computed Fields

Derived values computed from sidecar content and raw definitions:

```nix
options.schema = schemaLib.mkSchemaOption {
  sidecars = {
    includes = { default = []; };
    excludes = { default = []; };
  };
  computed = sidecars: defs: {
    isEntity =
      let
        sidecarKeys = lib.attrNames sidecars;
        hasStructuralContent = lib.any (d:
          let v = d.value;
              stripped = if builtins.isAttrs v
                then builtins.removeAttrs v sidecarKeys else v;
          in !builtins.isAttrs stripped || stripped != {}
        ) defs;
      in
      sidecars.includes != []
      || sidecars.excludes != []
      || hasStructuralContent;
  };
};

config.schema.host.isEntity   # → true (has includes)
config.schema.conf.isEntity   # → false (empty — shared base only)
```

### Introspection

Every schema has `_meta` for programmatic access:

```nix
config.schema._meta.kindNames                # → [ "host" "service" "user" ]
config.schema._meta.kindMeta "host"          # → { optionNames, options, ... }
```

### Documentation Generation

`renderDocs` produces markdown reference from schema metadata:

```nix
schemaLib.renderDocs config.schema
```

Outputs a table per kind with option name, type, default, and description — including extensions from composition and methods.

## API Reference

### `mkSchemaOption`

```nix
mkSchemaOption {
  strict ? true,        # strict-by-default validation on instances
  baseModule ? null,     # module imported into every kind
  sidecars ? {},         # { name = { default; merge? }; } — user-defined sidecar fields
  computed ? null,       # (sidecars -> defs -> attrset) — derived fields on merged result
}
```

Returns `lib.mkOption` — use as `options.schema = mkSchemaOption { ... }`.

### `mkInstanceType`

```nix
mkInstanceType schema kind {
  extraModules ? [],     # additional modules (cross-entity bindings, den-specific options)
  strict ? schema._strict or true,
}
```

Returns `lib.types.submodule` — the type for a single instance of a kind.

### `mkInstanceRegistry`

```nix
mkInstanceRegistry schema kind {
  extraModules ? [],
  strict ? schema._strict or true,
  description ? "${kind} instances",
}
```

Returns `lib.mkOption` with `type = attrsOf (mkInstanceType ...)`.

### `mkRefType`

```nix
mkRefType instances
```

Returns a type. Input: string key. Output: resolved instance. Throws on missing key.

### `schemaFn`

```nix
schemaFn description type fn
```

Declares a method on a kind. `fn` receives an attrset of config values matching its named arguments. Declare via `schema.<kind>.methods.<name> = schemaFn ...`.

### `renderDocs`

```nix
renderDocs schema
```

Returns a markdown string with a table per kind.

### `_internal`

```nix
schemaLib._internal.mkStrictModule    # strict freeform type module
schemaLib._internal.mkIdentityModule  # id_hash + _identity.keys module
schemaLib._internal.mkMethodsModule   # methods option/config wiring
```

Not part of the public API contract. Available for testing and advanced use.

## Architecture

```
Schema kinds (deferred modules)
  ↓ imported by
Instance types (submodules with strict + identity injected)
  ↓ collected into
Instance registries (attrsOf instance type)
  ↓ referenced by
Cross-instance refs (mkRefType)
```

**Kinds are pure schema** — options, config, defaults, methods, sidecars. No strict validation or identity hashing at the kind level.

**Instances add infrastructure** — `mkInstanceType` injects `mkStrictModule` and `mkIdentityModule`. This separation means kind-level composition via `imports` works without duplicate module conflicts.

**Sidecars are extracted before merge** — sidecar keys on kind definitions are folded, merged, and exposed on the result. They never enter the deferred module merge.

### File Layout

```
nix/lib/
  default.nix       — public API surface, wiring
  entry-type.nix     — mkSchemaEntryType, mkSchemaOption (sidecar extraction, _meta)
  instance.nix       — mkInstanceType, mkInstanceRegistry (strict + identity injection)
  identity.nix       — mkIdentityModule (id_hash, _identity.keys)
  strict.nix         — mkStrictModule (strict freeform type)
  methods.nix        — schemaFn, mkMethodsModule (method option/config generation)
  ref-type.nix       — mkRefType (cross-instance references)
  docs.nix           — renderDocs (markdown generation)
nix/flakeModule.nix  — flake-parts integration (provides schema option + schemaLib)
```

## Demo

See [`templates/demo/`](templates/demo/) for a complete fleet management example using flake-parts + import-tree. The demo exercises all features: kinds, instances, strict validation, identity hashing, cross-instance references, schema composition, kind mix-ins, declarative methods, and documentation generation.

```bash
cd templates/demo
nix eval --override-input den-schema ../.. .#fleet
nix eval --override-input den-schema ../.. .#docs --raw
```

## Testing

113 tests using nix-unit in `templates/ci/`:

```bash
cd templates/ci
nix develop --override-input den-schema ../.. -c nix-unit \
  --override-input den-schema ../.. --flake .#.tests
```

## License

MIT
