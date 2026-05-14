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

    # Define a kind
    schema.host = {
      options.addr = lib.mkOption { type = lib.types.str; };
      options.role = lib.mkOption { type = lib.types.str; default = "worker"; };
    };

    # Create a registry and instances
    options.hosts = schemaLib.mkInstanceRegistry config.schema "host" {};
    hosts.igloo = { addr = "10.0.1.1"; role = "web"; };
    hosts.iceberg = { addr = "10.0.2.1"; };  # role defaults to "worker"

    # Use them
    flake.fleet = {
      iglooAddr = config.hosts.igloo.addr;     # → "10.0.1.1"
      iglooHash = config.hosts.igloo.id_hash;  # → deterministic SHA-256
    };
  };
}
```

The flake-parts module provides `schema` and `schemaLib` with default settings (`strict = true`, no `baseModule`). For custom `strict`, `baseModule`, `sidecars`, or `computed` settings, use the programmatic API instead.

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
  schemaLib = import ./path/to/den-schema/nix/lib { inherit lib; };
in
# use schemaLib.mkSchemaOption, schemaLib.mkInstanceRegistry, etc.
```

## Use Cases

### Plugin system — extensible application config

A base application defines its schema. Plugins extend it from external flake inputs without touching the base:

```nix
# Base app — defines the plugin kind
config.schema.plugin = {
  options.enabled = lib.mkOption { type = lib.types.bool; default = true; };
  options.priority = lib.mkOption { type = lib.types.int; default = 50; };
};

# Logging plugin (separate flake input) — extends the kind
config.schema.plugin.options.logLevel = lib.mkOption {
  type = lib.types.enum [ "debug" "info" "warn" "error" ];
  default = "info";
};

# Metrics plugin (another flake input) — extends the same kind
config.schema.plugin.options.metricsEndpoint = lib.mkOption {
  type = lib.types.nullOr lib.types.str;
  default = null;
};

# Instances — validated against the merged schema from all inputs
config.plugins.logging = { logLevel = "debug"; priority = 10; };
config.plugins.metrics = { metricsEndpoint = "/metrics"; };
config.plugins.logging.badOption = "x";  # → STRICT MODE error with fix guidance
```

### Microservice registry — services referencing each other

```nix
config.schema.service = {
  options.port = lib.mkOption { type = lib.types.int; };
  options.protocol = lib.mkOption { type = lib.types.str; default = "http"; };
  options.healthPath = lib.mkOption { type = lib.types.str; default = "/health"; };
};

# Services can reference each other
options.services = schemaLib.mkInstanceRegistry config.schema "service" {
  extraModules = [({ ... }: {
    options.upstream = lib.mkOption {
      type = lib.types.nullOr (schemaLib.mkRefType config.services);
      default = null;
      description = "Upstream service this proxies to";
    };
  })];
};

config.services.api = { port = 8080; };
config.services.gateway = { port = 443; upstream = "api"; };

# Ref resolves to the full instance:
config.services.gateway.upstream.port  # → 8080
```

### Kubernetes resources — typed manifests with cross-references

```nix
config.schema.namespace = {
  options.labels = lib.mkOption { type = lib.types.attrsOf lib.types.str; default = {}; };
};

config.schema.deployment = {
  options.replicas = lib.mkOption { type = lib.types.int; default = 1; };
  options.image = lib.mkOption { type = lib.types.str; };
  options.containerPort = lib.mkOption { type = lib.types.int; };
};

config.schema.service = {
  options.port = lib.mkOption { type = lib.types.int; };
  options.targetPort = lib.mkOption { type = lib.types.int; };
};

# Deployments reference their namespace
options.deployments = schemaLib.mkInstanceRegistry config.schema "deployment" {
  extraModules = [({ ... }: {
    options.namespace = lib.mkOption {
      type = schemaLib.mkRefType config.namespaces;
    };
  })];
};

config.namespaces.production = { labels.env = "prod"; };
config.deployments.api = {
  namespace = "production";  # → resolves to the namespace instance
  image = "myapp:v1.2.3";
  replicas = 3;
  containerPort = 8080;
};

config.deployments.api.namespace.labels.env  # → "prod"
```

### Homelab config — hosts with environment inheritance

```nix
# Shared base for all entity types
options.schema = schemaLib.mkSchemaOption {
  baseModule.options.tags = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
  };
};

config.schema.host = {
  options.ip = lib.mkOption { type = lib.types.str; };
  options.os = lib.mkOption { type = lib.types.str; default = "nixos"; };
  methods.sshCmd = schemaLib.schemaFn
    "SSH command for this host"
    lib.types.str
    ({ name, ip, ... }: "ssh root@${ip} # ${name}");
};

config.schema.network = {
  options.cidr = lib.mkOption { type = lib.types.str; };
  options.gateway = lib.mkOption { type = lib.types.str; };
};

# Hosts reference their network
options.hosts = schemaLib.mkInstanceRegistry config.schema "host" {
  extraModules = [({ ... }: {
    options.network = lib.mkOption {
      type = schemaLib.mkRefType config.networks;
    };
  })];
};
options.networks = schemaLib.mkInstanceRegistry config.schema "network" {};

config.networks.lan = { cidr = "10.0.1.0/24"; gateway = "10.0.1.1"; };
config.hosts.nas = {
  ip = "10.0.1.10";
  network = "lan";
  tags = [ "storage" "backup" ];
};

config.hosts.nas.sshCmd        # → "ssh root@10.0.1.10 # nas"
config.hosts.nas.network.cidr  # → "10.0.1.0/24"
config.hosts.nas.tags          # → [ "storage" "backup" ] (from baseModule)
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

Kind names starting with `_` are reserved for internal use (`_meta`, `_strict`). They are excluded from `_meta.kindNames` and `renderDocs`.

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

### Base Module

A module injected into every kind automatically. Use it for options shared across all kinds without manual `imports`:

```nix
options.schema = schemaLib.mkSchemaOption {
  baseModule = {
    options.description = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Human-readable description.";
    };
  };
};

# Every kind gets `description` for free:
config.fleet.hosts.igloo.description  # → ""
config.fleet.users.tux.description    # → ""
```

`baseModule` is static — set at `mkSchemaOption` call time, not extensible by downstream modules. For extensible shared bases, use the kind mix-in pattern instead (a shared kind imported by others via `imports`).

### Default Propagation

Kind modules can set default config values. These flow through to every instance via deferred module merge:

```nix
config.schema.host = {
  options.system = lib.mkOption { type = lib.types.str; };
  config.system = lib.mkDefault "x86_64-linux";
};

config.fleet.hosts.igloo = {};          # system → "x86_64-linux"
config.fleet.hosts.mac.system = "aarch64-darwin";  # override works
```

This is standard NixOS module system behavior — `lib.mkDefault` sets a low-priority value that any explicit setting overrides.

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

### Nested Registries

Registries can nest inside instances via `extraModules`. This establishes parent-child relationships structurally:

```nix
# Capture the top-level schema before entering extraModules closures
let schema = config.schema;
in {
  options.fleet.hosts = schemaLib.mkInstanceRegistry schema "host" {
    extraModules = [({ config, ... }:
      let hostConfig = config;  # capture the host instance's config
      in {
        options.users = schemaLib.mkInstanceRegistry schema "user" {
          extraModules = [
            # Inject parent host into child user's module args
            ({ ... }: { config._module.args.host = hostConfig; })
          ];
        };
      }
    )];
  };
}

config.fleet.hosts.igloo = {
  addr = "10.0.1.1";
  users.tux.shell = "/bin/zsh";
  users.deploy.shell = "/bin/sh";
};

# Child instances access their parent:
config.fleet.hosts.igloo.users.tux._module.args.host.addr  # → "10.0.1.1"
```

Note the scoping: `schema` is captured at the top level (before the `extraModules` closure), and `hostConfig` captures the host instance's config (before the nested `extraModules` closure). Without these captures, `config` inside the closures would shadow the outer `config`.

Cross-entity bindings (`_module.args.host = hostConfig`) are the consumer's responsibility via `extraModules`. The schema library doesn't impose nesting semantics — different consumers wire cross-entity context differently.

### Per-Kind Strict Override

Individual registries can override the schema-level strict setting:

```nix
# Schema is strict by default
options.schema = schemaLib.mkSchemaOption { strict = true; };

# But this specific registry allows freeform
options.fleet.configs = schemaLib.mkInstanceRegistry config.schema "config" {
  strict = false;
};
```

### Identity Hashing

Nix's `==` on module system values can diverge or infinitely recurse. `id_hash` gives you a cheap, stable string comparison:

```nix
# Safe entity comparison
builtins.filter (h: h.id_hash != host.id_hash) allHosts

# Set membership
lib.elem target.id_hash (map (h: h.id_hash) candidates)
```

The hash is computed from all non-internal primitive options (str, int, bool), prefixed by the kind name. Two hosts with the same values hash identically. A host and a user with the same name hash differently (kind prefix).

`id_hash` is marked `internal = true` and `readOnly = true` — it won't appear in NixOS option documentation generators, but is always accessible via `instance.id_hash`.

**Three-layer precedence for key selection:**

1. **Explicit `_identity.keys`** — list the exact keys. Multiple modules can contribute via `mkMerge`.
2. **`identity = false`** — exclude individual options from reflection.
3. **Auto-reflection** — all non-internal primitives included (default).

```nix
# Layer 1: explicit keys — composable across modules
# Module A:
config.schema.host.config._identity.keys = [ "name" "addr" ];
# Module B (extends the kind):
config.schema.host.config._identity.keys = [ "vpnAlias" ];
# Result: [ "name" "addr" "vpnAlias" ] — list merge via mkMerge

# Layer 2: exclude an option from reflection
options.description = lib.mkOption { type = str; } // { identity = false; };

# Layer 3: automatic (default) — all non-internal str/int/bool options
```

Explicit keys are validated — referencing a nonexistent option or a non-primitive type throws at eval time:

```
_identity.keys: 'nonexistent' is not declared on kind 'host'
_identity.keys: 'tags' on kind 'host' is not a primitive type (str/int/bool)
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

Methods compose across modules — multiple modules can each add methods to the same kind:

```nix
# Module A
config.schema.host.methods.ping = schemaLib.schemaFn
  "Ping command" lib.types.str
  ({ addr, ... }: "ping ${addr}");

# Module B (separate file, separate flake input — doesn't matter)
config.schema.host.methods.ssh = schemaLib.schemaFn
  "SSH command" lib.types.str
  ({ name, ... }: "ssh ${name}");

# Both methods available on every host instance:
config.fleet.hosts.igloo.ping  # → "ping 10.0.1.1"
config.fleet.hosts.igloo.ssh   # → "ssh igloo"
```

If two modules declare the same method name, the later definition wins (attrset `//` semantics).

Methods with arguments that don't match any config key produce a clear error:

```
method 'bad' on host: references config keys 'nonexistent' which are not declared on this kind
```

Methods must be declared via inline attrsets, not path modules. This is a constraint shared with all sidecar fields.

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

**Merge strategy inference:**

| Default type | Inferred merge | Example |
|---|---|---|
| List (`[]`) | `acc ++ val` | `includes`, `excludes` |
| Attrset (`{}`) | `acc // val` | `metadata`, `methods` (built-in) |
| Other | Explicit `merge` required | `priority = { default = 0; merge = _acc: val: val; }` |

Providing a non-list, non-attrset default without an explicit `merge` function throws at evaluation time.

Sidecar keys are stripped before the deferred module merge — they never leak into the module system. Sidecars must be declared via inline attrsets, not path modules (path defs get the sidecar's default value).

`methods` is a built-in sidecar with `{ default = {}; }`. User-declared sidecars are additional. `__functor` is reserved and cannot be used as a sidecar key.

Multiple modules contributing to the same sidecar merge according to the sidecar's strategy:

```nix
# Module A
config.schema.host.includes = [ policy-a ];

# Module B
config.schema.host.includes = [ policy-b policy-c ];

# Result: [ policy-a policy-b policy-c ]
```

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

# Per-kind metadata — evaluates a throwaway instance to reflect on options
meta = config.schema._meta.kindMeta "host";
meta.optionNames   # → [ "addr" "describe" "hasService" "metricsPort" ... ]
meta.options       # → full option declarations (type, description, default, ...)
```

`kindMeta` is lazy — the `lib.evalModules` call only fires when accessed. Querying an undeclared kind throws:

```
kindMeta: 'nonexistent' is not a declared schema kind
```

### Schema Validators

Declare cross-field validation constraints on kinds. Validators are a built-in sidecar — they travel with the kind and run automatically on every registry of that kind.

```nix
config.schema.host.validators = [
  (schemaLib.mkValidator "has-addr"
    ({ addr, ... }: addr != "")
    "host must have a non-empty addr")
  (schemaLib.mkValidator "valid-role"
    ({ role, ... }: lib.elem role [ "web" "db" "worker" ])
    "role must be one of: web, db, worker")
];
```

Validators compose across modules — multiple modules can contribute validators to the same kind via the sidecar `++` merge:

```nix
# Module A
config.schema.host.validators = [ (schemaLib.mkValidator "a" ...) ];
# Module B
config.schema.host.validators = [ (schemaLib.mkValidator "b" ...) ];
# Both fire on every host registry
```

When validation fails, errors accumulate (not short-circuit) and include the instance name, validator name, and message:

```
schema validation failed:
  host 'igloo': has-addr — host must have a non-empty addr
  host 'iceberg': valid-role — role must be one of: web, db, worker
```

For standalone validation without throwing, use `validateInstances`:

```nix
result = schemaLib.validateInstances config.schema "host" config.fleet.hosts;
# → { right = instances; } or { left = [ { name; validator; message; } ]; }
```

### Derive Hooks

`derive` and `deriveEither` on `mkInstanceRegistry` compute values from the full evaluated registry and merge them back at high priority. The pipeline is: **validate → derive → apply**.

**Plain derive** — attrset in, attrset out:

```nix
options.fleet.users = schemaLib.mkInstanceRegistry config.schema "user" {
  derive = users:
    let uids = assignIds { min = 1000; max = 60000; } users;
    in lib.mapAttrs (name: _: { uid = uids.${name}; }) users;
  extraModules = [({ ... }: {
    options.uid = lib.mkOption { type = lib.types.int; readOnly = true; internal = true; };
  })];
};

config.fleet.users.tux.uid  # → 34213 (deterministic from id_hash)
```

Derive can read `id_hash` and all instance config — it runs after full module system evaluation. Derived fields must be `internal = true` (excluded from `id_hash` to avoid cycles) and `readOnly = true` (the derive hook is the only writer).

**`deriveEither`** — returns Either with configurable error handling:

```nix
options.fleet.services = schemaLib.mkInstanceRegistry config.schema "service" {
  deriveEither = {
    derive = services: someEitherPipeline services;
    onError = left: lib.warn "enrichment failed" {};  # optional, default throws
  };
};
```

`derive` and `deriveEither` are mutually exclusive. `onError` receives the `left` value — throw, warn, or return a fallback attrset. The default `onError` throws with a formatted message.

Validator errors flow through the same `onError` handler — a custom `onError` on `deriveEither` handles both validator failures and derive failures.

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

`mkSchemaEntryType` is also exported for advanced use — it returns the raw `deferredModule` type used for schema kind values, without wrapping in `mkOption` or adding `_meta`/`_strict`. Most consumers should use `mkSchemaOption`.

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
  derive ? null,         # { name → instance } → { name → attrset } — plain enrichment
  deriveEither ? null,   # { derive; onError? } — Either-based enrichment
}
```

Returns `lib.mkOption` with `type = attrsOf (mkInstanceType ...)` and an `apply` pipeline that runs validators then derive.

`derive` and `deriveEither` are mutually exclusive.

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

### `mkValidator`

```nix
mkValidator name pred message
```

Creates a validator record. `pred` receives the instance config and returns bool. Declare via `schema.<kind>.validators = [ (mkValidator ...) ]`.

### `validateInstances`

```nix
validateInstances schema kind instances
```

Runs the kind's validators against instances. Returns `{ right = instances; }` on success or `{ left = [ { name; validator; message; } ]; }` on failure. Does not throw — returns Either for consumer-controlled handling.

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
schemaLib._internal.runValidators     # validator execution (used by apply pipeline)
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
  validate.nix       — mkValidator, runValidators, validateInstances
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

149 tests using nix-unit in `templates/ci/`:

```bash
cd templates/ci
nix develop --override-input den-schema ../.. -c nix-unit \
  --override-input den-schema ../.. --flake .#.tests
```

## License

MIT
