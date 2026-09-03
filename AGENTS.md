# gen-schema — agent capability sheet

## Scope

Typed record registry: schema **kinds** (deferred modules carrying collections, ref fields, and a
parent topology), **instances** (submodules with strictness and a content-addressed `id_hash`
injected), and the **registry** option that binds them — driven on gen-merge's `evalModuleTree`, not
nixpkgs `lib.evalModules`.

Also the **reference vocabulary at both levels**: `ref`, the option type declaring that a field points
at an instance, and `fieldRef`, the inert value naming which instance and which field of it. One
library holds both because they are the two halves of one relation, and separating them is how a
reference type and its inhabitants drift apart.

## Not this library's job

Quoted text is the owner's own `flake.nix` `description` field, verbatim.

| Responsibility | Owner |
|---|---|
| The module MERGE engine itself — option merging, priorities, `evalModuleTree`, the `types.*` namespace. gen-schema implements none of it, and no longer re-exports it either: consumers reach it through the hub (`gen.lib.merge`), because the eval is the boundary and re-handing another library's value re-hands its build (ADR-0014, ADR-0015) | `gen-merge` — "gen-merge — pure-Nix byte-mode module MERGE engine (evalModuleTree) for the pure-gen module system" |
| Leaf/structural type CHECKING (`verify : v -> null\|err`). gen-schema declares options with these types and reads `type.name`; it writes no checker | `gen-types` — "gen-types: pure, nixpkgs-lib-free structural type checker for the gen ecosystem" |
| The record algebra (`record.compose` / `mixin` / `combine` / `assertSatisfies`) that `lib/mixin.nix` and `lib/bridge.nix` drive. gen-algebra carries **no** identity primitive: its standalone `name`+`fields` hasher retired into `hashIdentity`, since one substrate has one minting authority | `gen-algebra` — "gen-algebra: pure Nix algebra — search monad, records, intensional functions, either" |
| General utilities (`sort`, `filterAttrs`, `hasPrefix`, `concatMapStringsSep`, …) | `gen-prelude` — "gen-prelude: vendored, nixpkgs-lib-free pure utilities for the gen ecosystem" |
| Matching/selecting instances by attribute or graph position. gen-select *reads* the `id_hash` gen-schema mints and has no hasher of its own | `gen-select` — "gen-select: selector algebra for attributed graph positions" |
| Traversal, condensation, and query combinators over the `_edges` graph gen-schema exposes | `gen-graph` — "gen-graph: accessor-based graph query combinators" |
| Name resolution / demand-driven attribute evaluation. gen-schema exposes the P (parent) and I (ref) edge vocabulary as data and implements no resolution calculus | `gen-scope` — "gen-scope: demand-driven attribute grammar evaluator over algebraic scope graphs" |
| Aspect traits and classification; also the consumer of the `keySemantics` field gen-schema stores opaquely and never reads (`gen-aspects/ci/tests/key-semantics.nix`). gen-aspects mints its aspect id through gen-identity's `hashIdentity` over `[origin, key]` — injected directly (`gen-aspects/flake.nix` declares `gen-identity` as a dependency; `gen-aspects/lib/default.nix`: `inherit (identity) hashIdentity;`), NOT through gen-schema and NOT `mkIdentityModule` (`gen-aspects/ci/tests/aspect-id-hash.nix:3`). This replaces an earlier claim routing it through gen-schema's own `hashIdentity` — true only while gen-schema hosted the mint | `gen-aspects` — "gen-aspects: aspect-oriented composition types (pure-gen, re-hosted on gen-merge)" |
| Choosing a winner among matched rules; ordering and conflict resolution | `gen-dispatch` — "gen-dispatch: relational rule dispatch over ordered groups (the dispatch STEP)" |
| The nixpkgs composition boundary for flake-parts consumers. `flakeModule.nix:19-23` marks itself SUPERSEDED by it | The hub's `lib.compose` / interim `flakeModules.default` (INTERIM, not yet ADR-0027) — **`gen-flake` DISSOLVED rather than moving as one library.** ADR-0031 F2/F3 sent the compose S2 core to the hub, warm/override/trace to `gen-memo`, the projection + `realize` to `gen-delivery`, and inject/terminals to the crossing's Adapter set. The repo orphans as reference; take no new dependency on it |
| Injecting external arguments into modules | `gen-bind` — "gen-bind: module binding with external arguments for Nix" |
| Layered settings precedence with provenance (gen-schema has option defaults and collection merge, no precedence strata) | `gen-settings` — "gen-settings — stratified settings resolution as a pure layered fold, with refs-as-data, structured provenance, and the graduated injection construct" |

## Exports

Entry: `inputs.gen-schema.lib` (flake) or `import ./default.nix { }` (root, self-pinned from
`flake.lock` via `fetchTree`). Both yield the applied value. `import ./lib` is a **function** of
`{ prelude, merge, algebra }`.

**Module-system vocabulary is NOT on this surface** — reach it through the hub. The ergonomic promise
stands unchanged: a consumer declaring gen-schema options never reaches for nixpkgs `lib`. What changed
is the path. `mkOption`, `mkOptionType`, `mkMerge`, `mkDefault`, `mkForce`, `evalModuleTree` and `types`
come from `gen.lib.merge` — one build, gen-merge's own — rather than from a verbatim copy on this
library's surface, which was a second build of the same names and made every gen↔gen pin a type-identity
hazard (ADR-0014: the boundary is the eval, not the repo; ADR-0015: the hub is the sanctioned single
input). `import ./lib` still takes `merge` as an injected parameter exactly as it always has; nothing
gen-merge exports became unreachable.

**Schema kinds** — `lib/entry-type.nix`

| Export | Signature |
|---|---|
| `mkSchemaOption` | `{ strict ? true, baseModule ? null, collections ? {}, computed ? null, mixins ? [], mkType ? null, keySemantics ? {} } -> option` |
| `mkSchemaEntryType` | same argument set `-> type` (the `lazyAttrsOf` element type behind `mkSchemaOption`) |

`baseModule` may be a module or `kindName -> module`. `computed : collections -> defs -> attrset`
(wins over collections of the same name). `mkType : { kindModule, collections, defs, kind } -> attrset`
is the escape hatch — it skips the mixin pipeline, `__functor` wrapping, and refinement extraction.

**Instances and registries** — `lib/instance.nix`

| Export | Signature |
|---|---|
| `mkInstanceType` | `kindValue -> { extraModules ? [], strict ? kindValue.strict } -> type` |
| `mkInstanceRegistry` | `kindValue -> { extraModules ? [], refs ? {}, refinements ? {}, strict ? kindValue.strict, description ? "<kind> instances", derive ? null, deriveEither ? null } -> option` |

The registry's `apply` is the pipeline: deferred-ref coerce → refinements → validators → derive → overlay.
`derive` and `deriveEither` are mutually exclusive (throws).

**Identity** — `lib/id-hash.nix`

| Export | Signature |
|---|---|
| `mkIdentityModule` | `kindName -> module` — injects readOnly/internal `id_hash` and the `_identity.keys` submodule |
| ~~`hashIdentity`~~ | **NOT EXPORTED.** The one minting authority moved to `gen-identity`, a dependency-free leaf. gen-schema INJECTS it (`identity`) and constructs with it; re-exporting would re-export its build, which is the verbatim re-handing ADR-0014 rejects — and this repository is that ADR's own discharged instance |
| `identityHashForKind` | `kindValue -> instanceValue -> identity`, reflecting the **kind's** primitive options — the sole recompute path |

**Strictness** — `lib/strict.nix`

| Export | Signature |
|---|---|
| `mkStrictModule` | `kindName -> module` — sets a `_module.freeformType` whose merge always throws |

**Validators** — `lib/validate.nix`

| Export | Signature |
|---|---|
| `mkValidator` | `name -> pred -> message -> validator` |
| `mkFieldValidator` | `{ fields; name; check; message; } -> validator` (adds `__fields`) |
| `filterValidators` | `[optionName] -> [validator] -> [validator]` |
| `runValidators` | `kindName -> [validator] -> instances -> { right = instances; } \| { left = [failure]; }` |
| `validateInstances` | `kindValue -> instances -> { right; } \| { left; }` (reads `kindValue.validators`) |
| `formatErrors` | `[failure] -> string` |
| `defaultOnError` | `left -> throw` |

**Refinement contracts** — `lib/refined.nix`, `lib/blame.nix`

| Export | Signature |
|---|---|
| `refined` | `baseType -> refinement\|[refinement] -> type` (metadata under `type.__schema`) |
| `refinements` | `{ tcpPort; nonEmpty; positive; }` — prebuilt `{ check; message; }` records |
| `checkRefinements` | `fieldPath -> type -> value -> [failure]` — returns, never throws |
| `blame` | `field -> message -> { __blame = true; field; message; }` |

**Cross-instance references** — `lib/ref.nix`

| Export | Signature |
|---|---|
| `ref` | `kindName -> type` (deferred marker, carries `refKind`) **or** `instances -> type` (direct, coercing) |
| `setOf` | `refType -> type` — `listOf` that dedups by `id_hash`, first-seen order |
| `toSet` | `[instance] -> { member; toList; length; }` |

**Field references, the VALUE level** — `lib/field-ref.nix`

| Export | Signature |
|---|---|
| `fieldRef` | `instance -> [fieldName] -> { __genSchemaFieldRef = true; aspect; path; }` — throws unless the target carries `id_hash` and the path is a non-empty list of strings |
| `isFieldRef` | `v -> bool` |
| `fieldRefsIn` | `v -> [ { at; aspect; path; } ]` — deep structural scan; `at` is the subpath (attr keys and list indices) where the ref sits. **Throws** on a function in a scanned position |
| `fieldRefMarker` | the marker key string, for consumers writing their own predicate |

★ **The refusal is WIDER than the hazard, deliberately, and it is not the end of the road.** A
provably ref-free function refuses; a function at any depth refuses, including one inside a foreign
attrset stapled in from elsewhere; and a raw lambda as a computed value is foreclosed — computed
values route through constructs whose reads stay graph-visible (`fieldRef`, `computed`, a registry
`derive`), which is what the error string names — followed by an unconditional fallback, since the
commonest trigger is a stray function that was never a computed value at all: make the position data,
or keep it outside the scanned structure. **If a concrete need ever exceeds those**, the
sanctioned escape is the shape ADR-0023 sets for the value-injection invariant: by-construction as
the target, a **declared** opt-out as the interim with its price recorded — a schema-level annotation
marking a field *not scanned, its reads declared here*, at which point ADR-0013's written-impossibility
burden attaches to the annotation and is dischargeable, because a concrete case exists to argue from.
**Silently re-opening the scan is not sanctioned**; it converts a stated refusal into an unstated hole.
No such annotation ships today.

★ **`ref` and `fieldRef` are two different things and the library exports both.** They sit on
opposite sides of the type/value axis, so neither is a variant of the other:

| | `ref` (`lib/ref.nix`) | `fieldRef` (`lib/field-ref.nix`) |
|---|---|---|
| what it is | an option **TYPE** on a field | a **VALUE** inhabiting such a field |
| declared where | in the kind's schema | in a default or a contributed value |
| edges it derives | `_refEdges`, **kind → kind**, one per declared ref field | **(instance, field) → (instance, field)**, one per ref a scan finds |
| refuses | an unresolvable key, at merge time | a non-identity target, at application time |

The type declares that a field points at another instance; the value names **which one, and which
field of it**. Neither *declares* the dependence fact — both derive it from structure that is present
for another reason, which is why both can be read statically. The record field is named `aspect`
because gen-settings, the incumbent consumer, addresses aspects; it is the target **instance**.

**Methods** — `lib/methods.nix`

| Export | Signature |
|---|---|
| `schemaFn` | `description -> type -> ({ …configKeys }: value) -> methodDecl` |

**Mixins and the module bridge** — `lib/mixin.nix`, `lib/bridge.nix`

| Export | Signature |
|---|---|
| `mkMixin` | `{ define, requires ? [], provides ? [], kinds ? null, name ? "anonymous" } -> mixin` |
| `composeMixins` | `[mixin] -> mixin` |
| `beta` | `mixin -> mixin` — flips direction so the kind wins |
| `applyMixin` | `mixin -> kindRecord -> kindName -> record` |
| `emitModule` | `[collectionLabel] -> record -> { module; collections; refinements; }` |

**Serialization and docs** — `lib/codec.nix`, `lib/docs.nix`

| Export | Signature |
|---|---|
| `mkCodec` | `kindValue -> { fields ? {}, types ? {}, excludeFields ? [] } -> codec` |
| `renderDocs` | `schema -> markdownString` |

A codec is `{ encode; decode; encodeAll; decodeAll; serialize; deserialize; serializeAll; deserializeAll; json; }`, where `json` is the four `*` functions pre-applied to
`{ encode = toJSON; decode = fromJSON; }`.

**Internal**: `_internal.mkMethodsModule` — the only member.

**Kind value shape** (produced, not exported). Each `config.schema.<name>` is
`{ __functor; kind; options; refs; refinements; strict; keySemantics; mixins; methods; validators; parent; }` plus user collections and computed fields. `__functor` makes the kind directly importable
as a module. Schema-level introspection sits alongside the kinds: `_kindNames`, `_topology`
(`{ parent; children; }` per kind), `_refEdges` (`{ from; field; to; }`), `_edges` (parent edges plus
ref edges, each tagged `type`), `_roots`, `_leaves`, `_collectionKeys` (the collection keys
extracted from kind defs — built-ins plus this schema's declared `collections`).

**Instance value shape**: `{ _identity; id_hash; name; <declared options>; <methods>; }`. `name`
defaults to the registry key.

## Entry points by task

| Task | Reach for |
|---|---|
| Declare a schema surface a consumer extends | `options.schema = mkSchemaOption { }` |
| Add per-kind user data that merges across modules | `mkSchemaOption { collections.<name>.default = [ ] or { }; }` |
| Derive a field from merged collections | `mkSchemaOption { computed = collections: defs: { … }; }` |
| Replace the kind result outright (foreign type system) | `mkSchemaOption { mkType = { kindModule, collections, defs, kind }: …; }` |
| Turn a kind into an instance registry | `mkInstanceRegistry schema.<kind> { }` |
| Get the instance type without the registry wrapper | `mkInstanceType schema.<kind> { }` |
| Let a kind point at another kind's instances | `ref "<kind>"` on the option, `refs.<field> = <registry>` on `mkInstanceRegistry` |
| Resolve a ref against a registry already in scope | `ref config.fleet.hosts` (direct mode, no binding needed) |
| Break a self-referential registry cycle | `refs.<field> = { instances = …; coerce = registry: default: raw: …; deferred = true; }` |
| Dedup a ref list by identity | `setOf (ref "<kind>")` on the option; `toSet` on a plain instance list |
| Compare or dedup instances outside a registry | `id_hash` equality; `toSet` for O(1) membership |
| Recompute a hash to discover which kind a value belongs to | `identityHashForKind`, holding the kind value. There is no value-only form: a value carries no option metadata, so it can honour neither `internal` nor `identity = false` |
| Pin identity keys explicitly | `_identity.keys = [ … ]` on the instance (list-merges across modules) |
| Exclude a primitive option from identity | `identity = false` on the option declaration |
| Attach a predicate contract to a field | `refined <type> refinements.tcpPort`, or your own `{ check; message; lazy ? false; }` |
| Contract-check without throwing | `checkRefinements` |
| Assert across a whole registry | `validators = [ (mkValidator …) ]` on the kind |
| Assert only when a field exists | `mkFieldValidator { fields = [ … ]; … }` |
| Validate outside the registry pipeline | `validateInstances schema.<kind> instances` |
| Add a computed attribute to every instance | `methods.<name> = schemaFn desc type ({ someField }: …)` |
| Post-process a whole registry | `derive` (or `deriveEither` for `{ right; } \| { left; }` recovery) |
| Share fields across kinds by composition | `mkSchemaOption { mixins = [ … ]; baseModule = … }`, or `imports = [ schema.<other> ]` |
| Serialize a registry | `mkCodec schema.<kind> { }` then `.json.serializeAll` |
| Generate reference docs | `renderDocs config.schema` |
| Wire into flake-parts | `flakeModules.default` — but for flake-parts consumers the sanctioned wiring is the hub's `flakeModules.default` (INTERIM, not yet ADR-0027); `gen-flake` DISSOLVED (ADR-0031 F2/F3), so this module is retained for gen-merge / programmatic drivers |

## Measured traps

Each row verified at `6732239` by evaluating against `(builtins.getFlake "…/gen-schema").lib`, **except
the two identity rows** (the method row and the float-domain row), which were re-measured after the
minting change and are anchored to the named test suites rather than to a rev — those two re-verify on
every `nix-unit --flake ./ci#tests` run instead of resting on a one-time eval, **and except the two
kind-value-guard rows** (`validateInstances` and `mkInstanceRegistry`), which describe the fix landed by
`den-hoag-fvxh` and are anchored to that fix, not to `6732239` — the code at that rev still exhibits the
pre-fix (silent) behavior. Shared fixtures: `sc` = a schema built with
`evalModuleTree { modules = [ { options.schema = mkSchemaOption {}; } … ]; }`; `bogus = { no = "kind"; }`; `ok e = (builtins.tryEval (builtins.deepSeq e e)).success` (so `false` ⇒ threw).

| Trap | Evidence |
|---|---|
| `validateInstances`' kind-value guard is asserted directly in the function body (`den-hoag-fvxh`, landed), so it now fires whenever the *result* is forced at all — closing what used to be silence on an empty **and** on an all-passing instance set | `lib/validate.nix:76-84`; `validateInstances bogus { }` ⇒ **threw** (was: no throw), `validateInstances bogus { a = { port = 1; }; }` ⇒ **threw** (was: no throw), `validateInstances { validators = [ (mkValidator "v" (_: false) "m") ]; } { a = { }; }` ⇒ threw (unchanged — this arm already forced `kind` to build its failure record). Positive control, same instrument, real kind value: `left` ⇒ `[ { kind = "h"; message = "too low"; name = "a"; validator = "hi"; } ]`, and a passing set ⇒ `? right` (unchanged). Tests: `test-returns-either`, `test-does-not-throw` (real-kind positive control), `test-bogus-empty-set-throws`, `test-bogus-all-pass-set-throws`, `test-bogus-with-failing-validator-still-throws` (`ci/tests/validate-standalone.nix`) |
| `mkInstanceRegistry`'s guard is **necessarily still deferred at the option-declaration boundary** — eagerly asserting kind-shape as soon as the returned mkOption record is forced to WHNF causes **infinite recursion** for the load-bearing self-referential idiom `options.hosts = mkInstanceRegistry eval.config.schema.host {}` (measured: constructing the option record needs `kindValue`, a config value, before `eval`'s options phase — needed to compute that same config — has run). `den-hoag-fvxh` landed the half that *is* safe: an unconditional assert as the first statement of `applyPipeline` (bound to `apply`, invoked only at config-fixpoint demand time, safely after the options phase) — this closes the real silent-pass class, a genuinely-used registry with no validators and no ref bindings, where nothing previously forced `kind` even once the registry was read | `lib/instance.nix:268-510`; direct construction, bypassing the module system: `(mkInstanceRegistry bogus { }).description` ⇒ threw (unchanged), `(mkInstanceRegistry bogus { description = "d"; }).default` ⇒ **still no throw** — a raw `.default` read never invokes `apply`. **Declared, not fixed, per ADR-0013's form** (argued impossibility written at the site, `lib/instance.nix:489-501`): making `.default` eager recurses infinitely against the same self-referential idiom, and no other path to checkability exists, so the module-system path (`apply`) is the consumer contract for this option and the bypass read sits outside it. Through the module system, the class that matters in practice: `(mkInstanceRegistry bogus { description = "d"; }).apply { a = { }; }` ⇒ **now threw** (was: fell through to whatever `refValidation`/`kindValue.refs` etc. produced without ever checking kind-shape), and the self-referential pattern with a well-formed kindValue and no validators/refs still evaluates fine (measured: `eval.config.hosts.a.addr` resolves unchanged). Tests: `test-control-self-referential-registry-still-resolves`, `test-bogus-kind-apply-throws` (`ci/tests/instance-registry.nix`) |
| A method is **not** an identity key — `mkMethodsModule` marks each generated option `identity = false` at the point of creation, so no method return reaches the preimage and declaring a method does not move an instance's `id_hash`. Before that, a primitive-typed method reading an opted-out field **defeated the opt-out entirely**, because a method is an arbitrary function of config | `lib/methods.nix` (the generated `mkOption`) + `lib/id-hash.nix` (`isPrimitiveOption` reads `opt.identity`); two instances differing only in an `identity = false` field, once a `str`-typed method reads it ⇒ **same** `id_hash`, and declaring the method leaves an unchanged instance's `id_hash` **unmoved**. Live positive control in the same run: the opt-out honoured with no method at all. Tests: `ci/tests/identity-method-optout.nix` |
| A float in an identity position is admissible only for `\|v\| < 2^53`, and the bound is **strict** — `9007199254740992.0` refuses **by name** at mint time. Nix's `==` is not transitive above it: two distinct ints both compare equal to that one float, so no encoding can be neither coarser nor finer there | The bound is the MINT's, not this library's own: `gen-identity/lib/default.nix`, binding `exactBound` (this replaces an earlier citation to a `lib/identity.nix` this library no longer has — the mint moved out to `gen-identity`, `66d080c`); `9007199254740993 == 9007199254740992.0` ⇒ `true` while `9007199254740993 == 9007199254740992` ⇒ `false`. Ints stay unrestricted because the float that could collide with them is the one excluded. Tests: `test-cross-pair-not-both-admissible` and its one-ULP-below control (`ci/tests/identity-encoding.nix`) |
| Non-primitive options are **invisible** to identity — changing a `listOf str` leaves `id_hash` byte-identical | `lib/id-hash.nix`, binding `isPrimitiveOption`; two `listOf str` values ⇒ both `1b0650d3…`. Positive control, same instrument: two `str` values ⇒ different hashes |
| `_identity.keys` naming an undeclared or non-primitive option throws (it does not silently drop) | `lib/id-hash.nix`, binding `mkIdentityModule` (the `validatedExplicitKeys` local); `[ "nope" ]` ⇒ threw, `[ "lst" ]` (a `listOf`) ⇒ threw, `[ "a" ]` ⇒ evaluated. Tests: `test-explicit-overrides-reflection`, `test-merged-keys` (`ci/tests/identity-explicit-keys.nix`) |
| **`lib.types` is not on this surface at all** — the name collision it used to carry moved with it. gen-merge folds gen-types' whole surface into its `types`, so non-type names sit inside that namespace which also exist at gen-schema's top level; reading one and expecting the other's implementation is the trap, and it now spans two libraries rather than one attrset | `lib ? types` ⇒ `false`. Against the hub's copy, `filter (n: elem n (attrNames genSchema)) (attrNames genMerge.types)` ⇒ `[ "defaultOnError" "formatErrors" "mkValidator" "refined" "refinements" "runValidators" ]` — **six**, gen-types' implementations, not gen-schema's. `mkOption`/`mkOptionType` left this list with the re-export deletion (ADR-0014); `gen-merge/lib/default.nix:117` still folds them |
| `types.str` and `types.string` are the **same** gen-types checker — both `.name` ⇒ `"string"`, and both hash identically | `lib/id-hash.nix`, binding `isPrimitiveOption`; `types.str.name` ⇒ `"string"`, `types.string.name` ⇒ `"string"`, hashes both `eefaa98e…`. The `"str"` spelling `isPrimitiveOption` also accepts comes from **nixpkgs** `lib.types`, which this run did not exercise — that path is covered by `test-nixpkgs-str-field-reflected` (`ci/tests/identity-hash.nix`) |
| A kind whose name starts with `_` is a **full kind** but vanishes from every introspection output | `lib/entry-type.nix:322-323`; schema with kinds `visible` and `_hidden` ⇒ `_hidden.kind` is `"_hidden"`, yet `_kindNames` ⇒ `[ "visible" ]` and `attrNames _topology` ⇒ `[ "visible" ]` |
| Collections named `__functor` or `kind` are reserved and throw | `lib/entry-type.nix:57-61`; both ⇒ threw. Control collection `fine` on the same schema ⇒ evaluated. Test: `test-reserved-key-throws` (`ci/tests/collection-functor-guard.nix`) |
| A collection whose `default` is neither list nor attrset needs an explicit `merge`, and the throw is **deferred to first demand of that collection** — a schema carrying one evaluates fine until touched | `lib/entry-type.nix:65-74`; `scalarNoMerge.default = 0` ⇒ threw on access, while a sibling list collection on the same schema ⇒ evaluated. Test: `test-int-default-throws` (`ci/tests/collection-missing-merge-throws.nix`) |
| Merge strategy is inferred from the default's **type**: list ⇒ `++`, attrset ⇒ `//`, anything else needs `merge` | `lib/entry-type.nix:65-74`; `[ "a" ] , [ "b" ]` ⇒ `[ "a" "b" ]`, `{ x = 1; } , { y = 2; }` ⇒ `{ x = 1; y = 2; }`, explicit `acc + v` over `3` and `4` ⇒ `7` |
| Three collections exist on every kind whether declared or not | `lib/entry-type.nix:36-55`; a bare kind ⇒ `methods = { }`, `validators = [ ]`, `parent = null` |
| A `parent` naming an undeclared kind throws, and two conflicting `parent` declarations for one kind throw | `lib/entry-type.nix:47-53,336-340`; both ⇒ threw. Control, `parent = "b"` with `b` declared ⇒ `{ b = { children = [ "c" ]; parent = null; }; c = { children = [ ]; parent = "b"; }; }`. Test: `test-unknown-parent-throws` (`ci/tests/topology-validation.nix`) |
| Strict is the **default** (`kindValue.strict` ⇒ `true`); an undeclared instance key throws, and `strict = false` on the registry lets it through as freeform | `lib/entry-type.nix:29`, `lib/strict.nix:12-31`, `lib/instance.nix:42-48`; `{ addr = …; bogus = 1; }` ⇒ threw, control `.addr` on the same registry ⇒ evaluated, `strict = false` ⇒ `.bogus` ⇒ `1`. Tests: `test-undeclared-key-throws`, `test-declared-key-works` (`ci/tests/strict-module.nix`) |
| Field-gated validators are **silently skipped** when the kind lacks the field — no warning, no error | `lib/validate.nix:58-62`; `filterValidators [ "addr" "port" ] [ <mkFieldValidator fields = ["ghost"]> ]` ⇒ `[ ]`. Controls: a plain `mkValidator` survives the same filter, and the same field validator survives when `"ghost"` **is** in the option names. Tests: `test-filter-empty-kind`, `test-filter-plain-always-passes` (`ci/tests/validator-fields.nix`) |
| All three ref-binding errors throw: a declared ref field with no binding, a binding matching no field, and a string key absent from the target registry | `lib/instance.nix:187-202,86-87`; all three ⇒ threw. Control, correct binding ⇒ `hosts.a.net.cidr` resolves to `"10.0.0.0/8"` and the resolved value carries `id_hash`. Tests: `test-missing-binding-throws`, `test-extra-binding-throws`, `test-invalid-key-throws` |
| `setOf` rejects a non-ref element type at construction time | `lib/ref.nix:99-103`; `setOf types.str` ⇒ threw, `(setOf (ref "net")).name` ⇒ `"setOf(ref(net))"`. Test: `test-bad-ref-throws` (`ci/tests/ref-type-invalid.nix`) |
| `toSet` dedups first-seen, and `member` **throws** on a value without `id_hash` rather than returning false | `lib/ref.nix:119-141`; hashes `A B A` ⇒ `length` `2`, names `[ "A" "B" ]`, `member` on a present hash ⇒ `true`, absent ⇒ `false`, `member { name = "x"; }` ⇒ threw. Tests: `test-dedup-first-seen`, `test-member-true` (`ci/tests/toset.nix`) |
| `fieldRefsIn` **throws** on a function in a scanned position rather than treating it as a leaf — including a function nested under a list, an attrset whose `__functor` member is one, and a function that provably holds no ref. The refusal is wider than the hazard on purpose; the error names the reads-visible constructs to route a computed value through **and** an unconditional fallback for a function that was never one (make the position data, or keep it outside the scanned structure), and the only sanctioned escape beyond those is a declared schema-level annotation, never a quieter scan (README, *If the refusal is in your way*) | `lib/field-ref.nix`, the `isFunction` arm of `fieldRefsIn`'s `go`. A ref in data ⇒ **1** hop; the same ref inside a function body ⇒ threw; ordinary ref-free data ⇒ accepted, `[ ]`. Tests: `test-hazard-control-ref-in-data-is-one-hop`, `test-hazard-ref-in-function-body-is-refused`, `test-hazard-control-plain-data-is-accepted` (`ci/tests/field-ref.nix`). The blame POSITION is goldened separately against the shipped renderer — `listen.bind`, `xs.1.deep`, `(the scanned value itself)`, `k` — because every other arm asserts only that the throw fires, so a rendering regression would otherwise pass: measured, dropping the root case ⇒ **482/483** red on the root cell alone, and changing the separator ⇒ **481/483** red on the two multi-component cells alone, no pre-existing test catching either. ★ **Those three discriminate the shipped scan from the open one**: reverting the `isFunction` arm to `[ ]` and re-running the suite ⇒ `474/477`, red on exactly `test-hazard-ref-in-function-body-is-refused`, `test-refuses-function-nested-under-a-list` and `test-functor-attrset-is-refused`, with every control still green |
| `mkCodec` and `renderDocs` agree about methods: both drop them, on the same `internal = true` marker `mkMethodsModule` sets | `lib/codec.nix`, `mkCodec`'s `!(kindOptions.${n}.internal or false)` vs `lib/docs.nix`, `renderDocs`'s `n != "id_hash" && !(opts.${n}.internal or false)` — one flag, two readers; encoding an instance carrying `name`, `id_hash`, `addr`, `port`, `url` (a method) and `methods` ⇒ `{ addr = "1.1.1.1"; port = 22; }` only, and `renderDocs` on the same kind emits **no** `url` row. `renderDocs` drops `id_hash` and any option marked `internal = true`, nothing else — a user field named with a leading underscore renders like any other. Tests: `test-excludes-method-row`, `test-underscore-field-not-dropped-when-not-internal` (`ci/tests/docs-render.nix`) |
| `mkCodec` guards eagerly, unlike the registry guards above: a non-kind value and a `fields` spec naming an undeclared option both throw | `lib/codec.nix:72-94`; both ⇒ threw |
| `checkRefinements` **returns** a failure list; only the registry pipeline throws | `lib/refined.nix:24-42` vs `lib/instance.nix:421-425`; `checkRefinements "f" (refined types.int refinements.tcpPort) 99999` ⇒ `[ { field = "f"; lazy = false; message = "must be a valid TCP port (1-65535)"; value = 99999; } ]` (no throw), the same refinement on a registry field ⇒ threw, control value `80` ⇒ `80` |
| `lazy = true` refinements let the instance build and throw only at value access | `lib/instance.nix:426-440`; `attrNames instance` ⇒ evaluated, `.lazyF` on a violating value ⇒ threw, control passing value ⇒ `5`. Tests: `test-instance-accessible`, `test-lazy-field-throws-on-access` (`ci/tests/lazy-contract.nix`) |
| A method naming a config key the kind does not declare throws at **method access**, not at declaration | `lib/methods.nix:22-29`; `.bad` ⇒ threw, control `.addr` on the same instance ⇒ evaluated. Test: `test-bad-arg-throws` (`ci/tests/method-bad-arg.nix`) |
| Mixin direction: the default (`"smalltalk"`) mixin overrides the kind; `beta` reverses it | `lib/mixin.nix:27-30,73-94`; same mixin and base ⇒ `"from-mixin"` plain, `"from-kind"` under `beta` |
| Several helpers exist in `lib/` but are **not** on the public surface | `lib/default.nix`'s export attrset (the `in { … }` body); `lib ? isBlame`, `? collectBlame`, `? getRefinements`, `? isRefined`, `? mkRefinedType`, `? getRefKind`, `? dedupByHash`, `? renderAt` ⇒ all `false` (`renderAt` is `lib/field-ref.nix`'s position renderer, returned by that module so the suite can golden the SHIPPED one by importing it directly, and withheld from `lib`; pinned both ways by `test-render-at-is-not-public-surface` and its live control `test-control-public-surface-predicate-fires`). `refined` **is** `mkRefinedType`, re-exported through `refinedLib.types` (`lib/refined.nix:67`) |
| `flakeModule.nix` yields a gen-merge-typed `options.schema` that a nixpkgs `lib.evalModules` consumer cannot drive | `flakeModule.nix:14-17` states it. Read, not exercised in this run |

## Theory

Claimed in `README.md:1465-1484`, which splits its sources into **Implements** and **Informed by**,
and restated in the file-header comments.

**Implements**

- **Findler & Felleisen (2002), *Contracts for Higher-Order Functions*** — `lib/refined.nix` co-locates
  predicate contracts with type declarations; `lib/blame.nix` carries field-level attribution as
  `{ field; message; }`; `lib/instance.nix` runs the strict contract check inside `applyPipeline`.
- **Chitil (2012), *Practical Typed Lazy Contracts*** — `lazy = true` refinements wrap values with
  `builtins.addErrorContext`, deferring validation to access time (`lib/instance.nix:426-440`), which the
  README reads as Chitil's partial-identity semantics: unevaluated parts never trigger violations.
- **Bracha & Cook (1990), *Mixin-Based Inheritance*** — `lib/mixin.nix` implements `M1 * M2 = fun(i) M1(M2(i) + i) + M2(i)`; `beta` reverses the direction so the parent controls; `applyMixin` validates
  structural `requires`.
- **Rondon, Kawaguchi & Jhala (2008), *Liquid Types*** — `refined` attaches predicate refinements to a
  base type via `__schema` metadata, following the `{v:B | e}` base-refinement model.

**Informed by** (README's own label; no result claimed): Leijen (2005) *Extensible Records with Scoped
Labels* — the record algebra itself lives in gen-algebra, gen-schema consumes it; Cardelli (1997)
*Program Fragments, Linking, and Modularization* — `lib/bridge.nix`'s one-directional record→module
emit, without the full linking calculus; Neron, Tolmach, Visser & Wachsmuth (2015) *A Theory of Name
Resolution* — `_edges` borrows the P (parent) and I (import/ref) edge vocabulary, and the README states
gen-schema implements neither scope graphs nor the resolution calculus.

**Checked invariant**: the library is nixpkgs-lib-free — `ci/tests/purity.nix`
(`test-library-source-is-nixpkgs-free`) scans `lib/**.nix` plus the root `flake.nix` and `default.nix`
for `nixpkgs`, `lib.types`, `lib.mkOption`, `lib.mkMerge`, `lib.evalModules`, `evalModules`, `{ lib }`,
`{ lib,`. `ci/` is out of scope — the harness legitimately uses nixpkgs.

## Drift check

```sh
nix eval --json .#lib --apply 'l: { top = builtins.attrNames l; internal = builtins.attrNames l._internal; }'
```

Current output (verbatim):

```json
{"internal":["mkMethodsModule"],"top":["_internal","applyMixin","beta","blame","checkRefinements","composeMixins","defaultOnError","emitModule","fieldRef","fieldRefMarker","fieldRefsIn","filterValidators","formatErrors","identityHashForKind","isFieldRef","mkCodec","mkFieldValidator","mkIdentityModule","mkInstanceRegistry","mkInstanceType","mkMixin","mkSchemaEntryType","mkSchemaOption","mkStrictModule","mkValidator","ref","refined","refinements","renderDocs","runValidators","schemaFn","setOf","toSet","validateInstances"]}
```

**Checks.** Test-runner invocation (from the repo root; CI runs the same command with
`working-directory: ci`, `.github/workflows/ci.yml:13,18`):

```sh
nix flake check ./ci
```
