# gen-schema

A typed record registry for Nix with extension points, strict validation, refinement contracts, identity hashing, cross-instance references, first-class mixins, introspection, and declarative methods. Built on the NixOS module system.

gen-schema gives you what `lib.types.submodule` doesn't: open kind definitions that any module can extend, strict-by-default validation that catches typos immediately, refinement contracts co-located with type declarations, stable identity comparison via `id_hash`, cross-registry references that resolve to instances, reusable mixins with structural compatibility, and auto-generated documentation from your schema.

## Table of Contents

- [Terminology](#terminology)
- [Gen Ecosystem](#gen-ecosystem)
- [Quick Start](#quick-start)
- [Use Cases](#use-cases)
- [Core Concepts](#core-concepts)
  - [Kinds](#kinds)
  - [Extension](#extension)
  - [Base Module](#base-module)
  - [Default Propagation](#default-propagation)
  - [Strict Validation](#strict-validation)
  - [Instances](#instances)
  - [Nested Registries](#nested-registries)
  - [Per-Kind Strict Override](#per-kind-strict-override)
  - [Identity Hashing](#identity-hashing)
  - [Cross-Instance References](#cross-instance-references)
  - [Refs in Collections](#refs-in-collections)
  - [Custom Ref Coercion](#custom-ref-coercion)
  - [Deferred Coerce](#deferred-coerce-self-referential-registries)
  - [Deduplicated Sets](#deduplicated-sets)
  - [Parent-Child Topology](#parent-child-topology)
  - [Schema Introspection](#schema-introspection)
  - [Scope Graph Bridge](#scope-graph-bridge-consumer-side)
  - [Kind Mix-ins](#kind-mix-ins)
  - [Declarative Methods](#declarative-methods)
  - [Collection Fields](#collection-fields)
  - [Computed Fields](#computed-fields)
  - [Introspection API](#introspection-api)
  - [Schema Validators](#schema-validators)
  - [Derive Hooks](#derive-hooks)
  - [Documentation Generation](#documentation-generation)
  - [Refinement Contracts](#schematypesrefined)
  - [Blame](#schemablame)
  - [Field Validators](#schemamkfieldvalidator)
  - [Mixins](#schemamkmixin)
- [API Reference](#api-reference)
- [Architecture](#architecture)
- [Demo](#demo)
- [Testing](#testing)
- [Theoretical Foundations](#theoretical-foundations)
- [License](#license)

## Terminology

| Term | Definition |
|------|-----------|
| Kinds | Schema-level type declarations (deferred modules defining options and config) |
| Instances | Concrete values of a kind, evaluated through registries |
| Collections | Named multi-contributor aggregation points with a merge strategy |
| Refs | Cross-registry references between kinds (deferred or direct) |
| Edges | Parent (P) nesting and ref (I) import relationships, exposed via `_edges` introspection |

## Gen Ecosystem

| Library | Role |
|---------|------|
| [gen-algebra](https://github.com/sini/gen-algebra) | Pure primitives (search, record, identity) |
| [gen-schema](https://github.com/sini/gen-schema) | Typed registries (kinds, instances, collections, refs) |
| [gen-aspects](https://github.com/sini/gen-aspects) | Aspect types (traits, classification, dispatch) |
| [gen-graph](https://github.com/sini/gen-graph) | Graph queries (combinators, traversals, fixpoint) |
| [gen-scope](https://github.com/sini/gen-scope) | Scope graphs (construction, evaluation, resolution) |
| [gen-select](https://github.com/sini/gen-select) | Selector algebra (pattern matching over graph positions) |
| [gen-bind](https://github.com/sini/gen-bind) | Module binding (inject args into NixOS modules) |
| [gen-derive](https://github.com/sini/gen-derive) | Rule dispatch (stratified phases, fixpoint, conflict resolution) |

## Quick Start

### As a flake-parts module

```nix
# flake.nix
{
  inputs.gen-schema.url = "github:sini/gen-schema";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [ inputs.gen-schema.flakeModules.default ];

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

The flake-parts module provides `schema` and `schemaLib` with default settings (`strict = true`, no `baseModule`). For custom `strict`, `baseModule`, `collections`, or `computed` settings, use the programmatic API instead.

### Programmatic use

```nix
# Without flake-parts — call the library directly
let
  schemaLib = gen-schema.lib;
  # or: schemaLib = import ./path/to/gen-schema/nix/lib { inherit lib; };
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
  schemaLib = import ./path/to/gen-schema/nix/lib { inherit lib; };
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

# Services can reference each other (direct ref — registry in scope)
options.services = schemaLib.mkInstanceRegistry config.schema "service" {
  extraModules = [({ ... }: {
    options.upstream = lib.mkOption {
      type = lib.types.nullOr (schemaLib.ref config.services);
      default = null;
      description = "Upstream service this proxies to";
    };
  })];
};

config.services.api = { port = 8080; };
config.services.gateway = { port = 443; upstream = "api"; };

# Ref resolves to the full instance — accepts string keys or instance values:
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

# Deployments reference their namespace (deferred ref on kind + binding)
config.schema.deployment.options.namespace = lib.mkOption {
  type = schemaLib.ref "namespace";
};
options.deployments = schemaLib.mkInstanceRegistry config.schema "deployment" {
  refs.namespace = config.namespaces;
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

# Hosts reference their network (deferred ref)
config.schema.host.options.network = lib.mkOption {
  type = schemaLib.ref "network";
};
options.hosts = schemaLib.mkInstanceRegistry config.schema "host" {
  refs.network = config.networks;
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

Kind names starting with `_` are reserved for internal use (`_kindNames`, `_strict`). They are excluded from `_kindNames` and `renderDocs`.

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

`schema.ref` declares a reference to another kind's instances. Two modes:

**Deferred ref** — declare on the kind, bind at registry time:

```nix
# Kind declares referential intent
config.schema.service.options.host = lib.mkOption {
  type = schemaLib.ref "host";
};

# Registry binds the ref to a concrete registry
options.fleet.services = schemaLib.mkInstanceRegistry config.schema "service" {
  refs.host = config.fleet.hosts;
};
```

**Direct ref** — resolve immediately when the registry is in scope:

```nix
options.fleet.services = schemaLib.mkInstanceRegistry config.schema "service" {
  extraModules = [({ ... }: {
    options.upstream = lib.mkOption {
      type = lib.types.nullOr (schemaLib.ref config.fleet.services);
      default = null;
    };
  })];
};
```

Both modes accept string keys or instance values:

```nix
config.fleet.services.nginx.host = "igloo";                    # string key → lookup
config.fleet.services.gateway.upstream = config.fleet.services.nginx;  # instance → passthrough

config.fleet.services.nginx.host.addr  # → "10.0.1.1"
config.fleet.services.gateway.upstream.port  # → 80
```

Invalid references throw at eval time:

```
ref field 'host' on kind 'service': reference 'nonexistent' not found in instance registry
```

### Refs in Collections

`ref` works inside `listOf` and `nullOr` wrappers at any nesting depth:

```nix
config.schema.service.options.replicas = lib.mkOption {
  type = lib.types.listOf (schemaLib.ref "host");
  default = [];
};

# String keys and instance values both work:
config.fleet.services.nginx.replicas = [ "igloo" "iceberg" ];
config.fleet.services.nginx.replicas = [ config.fleet.hosts.igloo "iceberg" ];

# Nullable and nested wrappers:
type = lib.types.nullOr (lib.types.listOf (schemaLib.ref "host"));
```

### Custom Ref Coercion

For domain-specific resolution, pass an extended binding with a `coerce` function:

```nix
options.fleet.services = schemaLib.mkInstanceRegistry config.schema "service" {
  refs.host = {
    instances = config.fleet.hosts;
    coerce = default: val:
      if val == "primary" then config.fleet.hosts.igloo
      else default;
  };
};
```

`default` is a lazy thunk of the standard coercion result — only forced if you select it. In `listOf` context, `default` is a single-element list and the hook can return multiple instances (1->many expansion).

### Deferred Coerce (Self-Referential Registries)

When a registry's ref field points back to itself (e.g., a trait's `needs` referencing other traits in the same registry), standard coerce hooks cause infinite recursion — the coerce chain accesses the registry, which triggers `apply`, which runs the coerce chain again.

Set `deferred = true` to defer coercion to the `applyPipeline` (after all instances are evaluated). The coerce hook receives the raw materialized instances as its first argument, breaking the cycle:

```nix
options.traits = schemaLib.mkInstanceRegistry config.schema "trait" {
  refs.needs = {
    instances = config.traits;
    deferred = true;
    # 3-arg signature: registry is the raw instances (not config.traits)
    coerce = registry: default: val:
      if isSelector val then resolveAgainst registry val
      else default;
  };
};
```

**Signature difference:** Non-deferred hooks take 2 args (`default: val:`). Deferred hooks take 3 args (`registry: default: val:`), where `registry` is the pre-apply instance attrset. gen-schema pre-applies the registry, so `mkCoerceChain` sees a standard 2-arg function internally.

Deferred coerce runs before validators in `applyPipeline`, so validators see resolved instances and can check properties like `.name` on referenced entries.

### Deduplicated Sets

`setOf` deduplicates by `id_hash`, preserving first-seen order:

```nix
config.schema.group.options.members = lib.mkOption {
  type = schemaLib.setOf (schemaLib.ref "host");
  default = [];
};

config.fleet.groups.web.members = [ "igloo" "iceberg" "igloo" ];
# → [ igloo iceberg ] — duplicate removed by identity hash
```

Composes with custom coerce hooks — expansion produces duplicates, `setOf` removes them.

### Parent-Child Topology

Kinds can declare their parent kind via the `parent` collection. This establishes a schema-level nesting relationship:

```nix
config.schema.host = {
  options.addr = lib.mkOption { type = lib.types.str; };
};

config.schema.user = {
  parent = "host";  # users nest inside hosts
  options.shell = lib.mkOption { type = lib.types.str; };
};
```

The `parent` collection is optional — kinds without it are root kinds. The schema derives both directions:

```nix
config.schema._topology.host   # → { parent = null; children = [ "user" ]; }
config.schema._topology.user   # → { parent = "host"; children = []; }
```

Declaring a parent that doesn't exist as a schema kind throws at eval time.

### Schema Introspection

Every schema has flat `_`-prefixed options for programmatic access:

```nix
config.schema._kindNames    # → [ "host" "service" "user" ]
config.schema._roots        # → [ "host" ]  — kinds with no parent
config.schema._leaves       # → [ "user" ]  — kinds with no children

# Per-kind metadata
meta = config.schema._kindMeta "host";
meta.optionNames   # → [ "addr" "role" ... ]
meta.options       # → full option declarations
meta.refs          # → { }  (ref fields on this kind)

# Unified edge view (§ Neron 2015 scope graph P + I edges)
config.schema._edges
# → [
#   { from = "user"; to = "host"; type = "parent"; field = null; }
#   { from = "service"; to = "host"; type = "ref"; field = "host"; }
# ]

# Ref edges only
config.schema._refEdges
# → [ { from = "service"; field = "host"; to = "host"; } ]
```

`_edges` combines parent edges (from topology) and ref edges (from `schema.ref` declarations) into a single typed list. Every edge has `{ from, to, type, field }` — `field` is `null` for parent edges and the option name for ref edges.

### Scope Graph Bridge (Consumer-Side)

gen-schema provides generic introspection options (`_topology`, `_edges`, `_kindNames`, etc.) that consumers use to build whatever graph format their evaluator needs. The bridge logic lives in consumers (e.g., den's `buildScopeGraphs`), not in gen-schema.

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

Methods must be declared via inline attrsets, not path modules. This is a constraint shared with all collection fields.

### Collection Fields

Declare custom collection fields on kinds — data extracted from definitions before module merge and exposed on the merged result:

```nix
options.schema = schemaLib.mkSchemaOption {
  collections = {
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

# Read collection values directly:
config.schema.host.includes  # → [ policy-a policy-b ]
```

**Merge strategy inference:**

| Default type | Inferred merge | Example |
|---|---|---|
| List (`[]`) | `acc ++ val` | `includes`, `excludes` |
| Attrset (`{}`) | `acc // val` | `metadata`, `methods` (built-in) |
| Other | Explicit `merge` required | `priority = { default = 0; merge = _acc: val: val; }` |

Providing a non-list, non-attrset default without an explicit `merge` function throws at evaluation time.

Collection keys are stripped before the deferred module merge — they never leak into the module system. Collections must be declared via inline attrsets, not path modules (path defs get the collection's default value).

`methods` is a built-in collection with `{ default = {}; }`. User-declared collections are additional. `__functor` is reserved and cannot be used as a collection key.

Multiple modules contributing to the same collection merge according to the collection's strategy:

```nix
# Module A
config.schema.host.includes = [ policy-a ];

# Module B
config.schema.host.includes = [ policy-b policy-c ];

# Result: [ policy-a policy-b policy-c ]
```

### Computed Fields

Derived values computed from collection content and raw definitions:

```nix
options.schema = schemaLib.mkSchemaOption {
  collections = {
    includes = { default = []; };
    excludes = { default = []; };
  };
  computed = collections: defs: {
    isEntity =
      let
        collectionKeys = lib.attrNames collections;
        hasStructuralContent = lib.any (d:
          let v = d.value;
              stripped = if builtins.isAttrs v
                then builtins.removeAttrs v collectionKeys else v;
          in !builtins.isAttrs stripped || stripped != {}
        ) defs;
      in
      collections.includes != []
      || collections.excludes != []
      || hasStructuralContent;
  };
};

config.schema.host.isEntity   # → true (has includes)
config.schema.conf.isEntity   # → false (empty — shared base only)
```

### Introspection API

Every schema has flat `_`-prefixed options for programmatic access:

```nix
config.schema._kindNames                # → [ "host" "service" "user" ]

# Per-kind metadata — evaluates a throwaway instance to reflect on options
meta = config.schema._kindMeta "host";
meta.optionNames   # → [ "addr" "describe" "hasService" "metricsPort" ... ]
meta.options       # → full option declarations (type, description, default, ...)
```

`_kindMeta` is lazy — the `lib.evalModules` call only fires when accessed. Querying an undeclared kind throws:

```
kindMeta: 'nonexistent' is not a declared schema kind
```

### Schema Validators

Declare cross-field validation constraints on kinds. Validators are a built-in collection — they travel with the kind and run automatically on every registry of that kind.

```nix
config.schema.host.validators = [
  (gen.mkValidator "has-addr"
    ({ addr, ... }: addr != "")
    "host must have a non-empty addr")
  (gen.mkValidator "valid-role"
    ({ role, ... }: lib.elem role [ "web" "db" "worker" ])
    "role must be one of: web, db, worker")
];
```

Validators compose across modules — multiple modules can contribute validators to the same kind via the collection `++` merge:

```nix
# Module A
config.schema.host.validators = [ (gen.mkValidator "a" ...) ];
# Module B
config.schema.host.validators = [ (gen.mkValidator "b" ...) ];
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

`derive` and `deriveEither` on `mkInstanceRegistry` compute values from the full evaluated registry and merge them back at high priority. The pipeline is: **validate -> derive -> apply**.

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
  collections ? {},      # { name = { default; merge? }; } — user-defined collection fields
  computed ? null,       # (collections -> defs -> attrset) — derived fields on merged result
}
```

Returns `lib.mkOption` — use as `options.schema = mkSchemaOption { ... }`.

`mkSchemaEntryType` is also exported for advanced use — it returns the raw `deferredModule` type used for schema kind values, without wrapping in `mkOption` or adding introspection options/`_strict`. Most consumers should use `mkSchemaOption`.

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
  refs ? {},             # bindings for deferred refs (see below)
  strict ? schema._strict or true,
  description ? "${kind} instances",
  derive ? null,         # { name → instance } → { name → attrset } — plain enrichment
  deriveEither ? null,   # { derive; onError? } — Either-based enrichment
}
```

Returns `lib.mkOption` with `type = attrsOf (mkInstanceType ...)` and an `apply` pipeline that runs validators then derive.

`derive` and `deriveEither` are mutually exclusive.

`refs` binds deferred `ref` fields to concrete registries. Three forms:

```nix
# Simple — registry directly:
refs.host = config.fleet.hosts;

# Extended — with custom coercion (2-arg):
refs.host = {
  instances = config.fleet.hosts;
  coerce = default: val: ...;  # default is lazy thunk of standard result
};

# Deferred — for self-referential registries (3-arg):
refs.needs = {
  instances = config.traits;
  deferred = true;
  coerce = registry: default: val: ...;  # registry = raw pre-apply instances
};
```

`deferred = true` runs coercion inside `applyPipeline` (after instances are materialized) instead of at option-apply time. The custom hook receives the raw instances as `registry` — use this instead of capturing the config value in the closure. Required when the ref field points back to the same registry being defined.

### `ref`

```nix
ref target
```

`target` is a string -> deferred ref (kind name, bound via `refs` on `mkInstanceRegistry`). `target` is an attrset -> direct ref (resolved immediately). Both modes accept string keys or instance values.

### `setOf`

```nix
setOf elemType
```

A list type that deduplicates by `id_hash`, preserving first-seen order. Only meaningful with `ref` element types — `setOf` requires instance refs. Composes with custom coerce hooks: expansion produces duplicates, `setOf` removes them. Uses `nestedTypes.elemType` so `getRefKind` traverses through it like `listOf`.

### `toSet`

```nix
toSet instances
```

Converts a list of instances to a set with O(1) membership lookup via attrset backing. Deduplicates by `id_hash` (first-seen wins), so safe to call on any instance list. Returns:

```nix
{
  member = x: ...;  # O(1) membership test
  toList = [ ... ];  # deduplicated list, first-seen order
  length = n;        # number of unique instances
}
```

### `schemaFn`

```nix
schemaFn description type fn
```

Declares a method on a kind. `fn` receives an attrset of config values matching its named arguments. Declare via `schema.<kind>.methods.<name> = schemaFn ...`.

### `mkValidator` (from gen-algebra)

```nix
gen.mkValidator name pred message
```

Creates a validator record. `pred` receives the instance config and returns bool. Declare via `schema.<kind>.validators = [ (gen.mkValidator ...) ]`. Provided by [gen-algebra](https://github.com/sini/gen-algebra), not gen-schema.

### `validateInstances`

```nix
validateInstances schema kind instances
```

Runs the kind's validators against instances. Returns `{ right = instances; }` on success or `{ left = [ { name; validator; message; } ]; }` on failure. Does not throw — returns Either for consumer-controlled handling.

### `mkFieldValidator`

```nix
mkFieldValidator {
  name = "validator-name";
  fields = [ "field1" "field2" ];  # optional — auto-skip kinds missing these fields
  check = inst: ...;               # predicate over instance config
  message = "error description";
}
```

Row-polymorphic validators with automatic field filtering. Validators with `fields` are automatically skipped for kinds that don't have all required fields. Validators without `fields` run unconditionally (backwards compatible).

### `filterValidators`

```nix
filterValidators validators kindOptionNames
```

Filters a list of validators to only those whose `fields` (if declared) are all present in `kindOptionNames`. Used internally by `mkInstanceRegistry` to skip inapplicable field validators. Exported for consumers building custom validation pipelines.

### `renderDocs`

```nix
renderDocs schema
```

Returns a markdown string with a table per kind.

### `schema.types.refined`

Refinement contracts co-located with type declarations (§ Findler 2002, § Rondon 2008). Predicates validate during `applyPipeline` (strict by default).

```nix
# Single refinement
port = mkOption {
  type = schema.types.refined lib.types.int {
    check = self: self > 0 && self < 65536;
    message = "must be valid TCP port";
  };
};

# Composed refinements (all must pass)
port = mkOption {
  type = schema.types.refined lib.types.int [
    { check = self: self > 0; message = "must be positive"; }
    { check = self: self < 65536; message = "must be < 65536"; }
  ];
};

# Reusable
port = mkOption { type = schema.types.refined lib.types.int schema.refinements.tcpPort; };
```

Set `lazy = true` on a refinement to defer validation to access time via `builtins.addErrorContext` (§ Chitil 2012):

```nix
{ check = self: self > 0; message = "must be positive"; lazy = true; }
```

### `schema.refinements.*`

Built-in reusable refinements: `tcpPort`, `nonEmpty`, `positive`. Use with `schema.types.refined` to avoid repeating common predicates.

### `schema.blame`

Field-level error attribution for structured contract violations (§ Findler 2002).

```nix
schema.blame "fieldName" "error message"
# → { __blame = true; field = "fieldName"; message = "error message"; }
```

### `schema.mkMixin`

First-class reusable schema fragments with structural compatibility (§ Bracha 1990). `define` receives a record-algebra record and returns a plain attrset.

```nix
monitorable = schema.mkMixin {
  requires = [ "port" "hostname" ];
  provides = [ "metrics_port" ];
  # kinds = [ "service" ];  # optional kind constraint
  define = parent: {
    metrics_port = (record.select parent "port") + 1000;
  };
};
```

### `schema.composeMixins`

Compose multiple mixins into one. Requires propagation: earlier mixins' `provides` satisfy later mixins' `requires`.

```nix
enhanced = schema.composeMixins [ monitorable loggable healthcheck ];

# Mixed direction: beta mixin is overridden by what came before
combined = schema.composeMixins [
  monitorable
  (schema.beta tlsBase)  # Beta: existing fields win over tlsBase's
  loggable
];
```

### `schema.beta`

Annotates a mixin for Beta direction (§ Bracha 1990) — parent controls, meaning existing fields take precedence over the mixin's contributions.

### `schema.applyMixin`

```nix
applyMixin mixin kindRecord kindName
```

Applies a single mixin to a record-algebra record. Validates structural compatibility (`requires`) and optional kind constraint (`kinds`). Respects Smalltalk/Beta direction.

### `schema.emitModule`

Bridges record-algebra records to NixOS modules (§ Cardelli 1997). Strips refinement metadata from types. Extracts collections with full shadow stacks.

```nix
emitted = schema.emitModule [ "validators" "methods" ] recordAlgebraRecord;
# → { module = <NixOS module>; collections = { ... }; refinements = { ... }; }
```

### `mkSchemaEntryType` `mixins` parameter

Mixins are auto-applied when `baseModule` is an inline attrset:

```nix
mkSchemaEntryType {
  mixins = [ monitorable loggable ];
  baseModule = {
    port = mkOption { type = types.int; };
    hostname = mkOption { type = types.str; };
  };
}
```

### `_internal`

```nix
schemaLib._internal.mkMethodsModule   # methods option/config wiring
```

Not part of the public API contract. Available for testing and advanced use.

Identity, strict, validation, and ref primitives are in [gen-algebra](https://github.com/sini/gen-algebra) — import gen-algebra directly if you need them outside of gen-schema.

## Architecture

```
Schema kinds (deferred modules, parent collection, ref types)
  ↓ imported by
Instance types (submodules with strict + identity injected)
  ↓ collected into
Instance registries (attrsOf instance type, ref binding via apply)
  ↓ referenced by             ↓ introspected by
Cross-instance refs        _topology, _edges, _roots, _leaves
  (schema.ref)
```

**Kinds are pure schema** — options, config, defaults, methods, collections. No strict validation or identity hashing at the kind level.

**Instances add infrastructure** — `mkInstanceType` injects `mkStrictModule` and `mkIdentityModule`. This separation means kind-level composition via `imports` works without duplicate module conflicts.

**Collections are extracted before merge** — collection keys on kind definitions are folded, merged, and exposed on the result. They never enter the deferred module merge.

### File Layout

```
nix/lib/
  default.nix       — public API surface, wiring (imports gen-algebra for primitives)
  entry-type.nix     — mkSchemaEntryType, mkSchemaOption (collection extraction, introspection, topology)
  instance.nix       — mkInstanceType, mkInstanceRegistry (strict + identity injection, refs)
  ref.nix            — schema.ref (dual-mode cross-instance references, getRefKind)
  methods.nix        — schemaFn, mkMethodsModule (method option/config generation)
  validate.nix       — validateInstances, mkFieldValidator, filterValidators (schema-specific validation)
  refined.nix        — schema.types.refined (refinement contracts, § Findler 2002 / § Rondon 2008)
  blame.nix          — schema.blame (field-level error attribution)
  mixin.nix          — mkMixin, composeMixins, beta, applyMixin (§ Bracha 1990)
  bridge.nix         — emitModule (record-algebra → NixOS module bridge, § Cardelli 1997)
  docs.nix           — renderDocs (markdown generation)
nix/flakeModule.nix  — flake-parts integration (provides schema option + schemaLib)
```

Identity hashing (`mkIdentityModule`), strict validation (`mkStrictModule`), validators (`mkValidator`, `runValidators`), and cross-instance references (`mkRefType`) are provided by [gen-algebra](https://github.com/sini/gen-algebra) and consumed internally.

## Demo

See [`templates/demo/`](templates/demo/) for a complete fleet management example using flake-parts + import-tree. The demo exercises all features: kinds, instances, strict validation, identity hashing, cross-instance references, schema composition, kind mix-ins, declarative methods, and documentation generation.

```bash
cd templates/demo
nix eval --override-input gen-schema ../.. .#fleet
nix eval --override-input gen-schema ../.. .#docs --raw
```

## Testing

Tests use nix-unit in `templates/ci/`:

```bash
cd templates/ci
nix develop --override-input gen-schema ../.. -c nix-unit \
  --override-input gen-schema ../.. --flake .#.tests
```

## Theoretical Foundations

gen-schema draws on seven papers. Four are directly implemented in the codebase; three inform the design without direct implementation.

### Implements

| Feature | Paper | Where |
|---------|-------|-------|
| Refinement contracts with blame tracking | § Findler & Felleisen -- *Contracts for Higher-Order Functions* (ICFP 2002) | `refined.nix`: predicate contracts co-located with NixOS type declarations; `blame.nix`: field-level error attribution with `{ field, message }` blame records; `instance.nix`: strict contract checking in `applyPipeline` |
| Lazy contracts with deferred validation | § Chitil -- *Practical Typed Lazy Contracts* (ICFP 2012) | `instance.nix`: `lazy = true` refinements wrap values with `builtins.addErrorContext`, deferring validation to access time -- matching Chitil's partial-identity semantics where unevaluated parts never trigger violations |
| Mixin composition | § Bracha & Cook -- *Mixin-Based Inheritance* (OOPSLA 1990) | `mixin.nix`: `mkMixin`/`composeMixins` implement Bracha's `M1 * M2 = fun(i) M1(M2(i) + i) + M2(i)` formula; `beta` reverses direction so parent controls; `applyMixin` validates structural requires |
| Refinement types | § Rondon, Kawaguchi & Jhala -- *Liquid Types* (PLDI 2008) | `refined.nix`: `schema.types.refined` attaches predicate refinements to base NixOS types via `__schema` metadata, following Rondon's model of `{v:B \| e}` base refinements co-located with type declarations |

### Informed by

| Concept | Paper | Influence |
|---------|-------|-----------|
| Record algebra | § Leijen -- *Extensible Records with Scoped Labels* (TFP 2005) | gen-schema consumes gen-algebra's `record.compose`, `record.select`, `record.mixin` etc. The record algebra itself lives in gen-algebra; gen-schema uses it for mixin application and module bridging |
| Module linking | § Cardelli -- *Program Fragments, Linking, and Modularization* (POPL 1997) | `bridge.nix`: `emitModule` translates record-algebra records into NixOS modules (one-directional). Cardelli's linkset model -- separately compiled fragments linked via type-compatible substitution -- informs the design, though gen-schema doesn't implement the full linking calculus |
| Scope graph edge model | § Neron, Tolmach, Visser & Wachsmuth -- *A Theory of Name Resolution* (ESOP 2015) | `entry-type.nix`: `_edges` introspection uses Neron's P (parent) and I (import/ref) edge vocabulary to expose schema topology. gen-schema doesn't implement scope graphs or the resolution calculus -- that lives in gen-scope |

## License

MIT
