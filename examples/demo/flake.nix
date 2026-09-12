{
  description = "gen-schema demo: typed fleet management via gen value-injection (schema, refs, strict validation)";

  # Value-injection. The gen definition tree (./gen-modules) is composed PURELY by the hub's
  # `flakeModules.default` — gen-merge's byte-mode `evalModuleTree`, NOT flake-parts'
  # nixpkgs `lib.evalModules`. The resolved config VALUES are injected as the `genValues` module arg;
  # NO gen TYPE enters the flake-parts options tree (the old `options.schema = mkSchemaOption {}` embed
  # made flake-parts walk a gen type via `substSubModules`/`getSubOptions` and throw under the pure
  # re-host). `modules/outputs.nix` is the READER: it renders over `genValues`, never over a gen type.
  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      {
        lib,
        inputs,
        options,
        ...
      }:
      {
        # The module injects `genValues` into the top-level flake args only; `perSystem` injection is
        # opt-in (`gen.injectPerSystem`, default off) and emits no `perSystem` definition otherwise.
        # This demo reads `genValues` from a top-level reader module and produces no per-system outputs,
        # so no `systems` declaration is required.

        imports = [
          inputs.gen.flakeModules.default
          ./modules/outputs.nix
        ];

        # `config`, not a plain top-level attrset, because one of the values below (`gen.aspectCnf`)
        # is conditioned on `options` (den-hoag-xork6, next comment down) — and `options` is the
        # merged declaration tree from every imported module, so reading it to decide the module's
        # own TOP-LEVEL SHAPE (rather than a value nested inside `config`) is circular: the module
        # system needs this module's declarations to finish computing `options`, before it can call
        # this module to get that shape. Nested inside `config`, the read happens only once `options`
        # is already settled, which is the ordinary, safe place for it.
        config = lib.mkMerge [
          {
            # PURE composition of the gen definition tree. The composition surface threads its own
            # gen-merge/gen-schema/gen-aspects into every tree module; the demo adds the two extra
            # module args the relocated definitions reach for: `lib` (their kind definitions use
            # nixpkgs `lib.mkOption`/`lib.types`) and `genAlgebra` (record algebra + the Either
            # pipeline). Passed via `gen.specialArgs` so the pure `evalModuleTree` sees them (it
            # auto-provides only `config`/`options`).
            gen.tree = ./gen-modules;
            gen.specialArgs = {
              inherit lib;
              genAlgebra = inputs.gen-algebra.lib;
            };

            # READER-side gen LIBRARIES (distinct from the injected VALUES). `outputs.nix` renders
            # over the injected `genValues` with these: `renderDocs`/`mkCodec`/`blame`/`applyMixin`.
            # Injected into the flake's top-level module args alongside the module's `genValues`.
            _module.args = {
              genSchema = inputs.gen-schema.lib;
              genAlgebra = inputs.gen-algebra.lib;
            };
          }
          (
            # THE DECLARATION INPUT for the hub's delivery-class projection (ADR-0028's Rider;
            # den-hoag-xork6). `null` (the option's own default) is the ABSENT state, not "no
            # aspects": with no category source gen-delivery's `requireCnf` refuses BY NAME rather
            # than degrading to a shape test. This tree declares no aspect keys at all, so the
            # truthful value is the empty declaration in `./aspect-cnf.nix` — the shared home a
            # future aspect-schema module in this tree would import too, so the two cannot drift
            # (see that file's header). Guarded on `options.gen ? aspectCnf` because the option is
            # undeclared at a gen pin before `a3e9436` — DEFINING it there, even as `null`, is
            # itself "the option `gen.aspectCnf' does not exist" (measured: the committed pin
            # `9acf8bb` predates that commit) — so the key is omitted outright, not just
            # conditioned false, until the hub relock lands.
            lib.optionalAttrs (options.gen ? aspectCnf) {
              gen.aspectCnf = import ./aspect-cnf.nix;
            }
          )
          (
            # THE NODE REGISTRY (ADR-0035, den-hoag-hub-hardcodes-hosts-mxpd5). The hub used to take
            # gen-delivery's `values.hosts or { }` default, so a registry spelled anything else
            # projected `{ }` with no diagnostic — and THIS tree's registries are nested at
            # `fleet.hosts`, which that default could not express at all. The option is an ATTRIBUTE
            # PATH and it must name the REGISTRY, never the container: `[ "fleet" ]` resolves to an
            # attrset of six registries and would project their KEYS as node names.
            #
            # Guarded for the same reason `gen.aspectCnf` above is, and measured the same way: the
            # option is undeclared at this demo's committed pin, and DEFINING it there — even as
            # `null` — is itself "the option `gen.nodeRegistryPath' does not exist". Omitted
            # outright, not conditioned false, until the relock lands.
            lib.optionalAttrs (options.gen ? nodeRegistryPath) {
              gen.nodeRegistryPath = [
                "fleet"
                "hosts"
              ];
            }
          )
        ];
      }
    );

  inputs = {
    # The hub — ADR-0015's single sanctioned input, carrying `flakeModules.default` (ADR-0031 F1:
    # rehomed from gen-flake, marked INTERIM). It threads the published pure stack (gen-schema /
    # gen-aspects / gen-merge / …) into the tree, so definition modules receive
    # `{ genSchema, genMerge, ... }` as before. The hub evaluates no nixpkgs of its own, so its
    # nixpkgs slot follows ours rather than locking a second one.
    gen.url = "github:sini/gen";
    gen.inputs.nixpkgs.follows = "nixpkgs";

    # Reuse the EXACT gen-schema / gen-algebra instances the composition threads into the pure tree, so
    # the reader-side renderDocs/mkCodec/applyMixin operate on type + record objects structurally
    # identical to the injected `genValues` (and no duplicate fetch). gen-algebra rides gen-schema's own
    # pin. The path is the hub's own top-level gen-schema, which IS the instance
    # `flakeModules.default` threads: ADR-0031 dissolved gen-flake, so there is no `flake` roster
    # member self-resolving a second gen-schema and no second build of the same names to avoid.
    # ── The superseded ground, recorded rather than dropped ── this read
    # `follows = "gen/gen-flake/gen-schema"` because `flakeModules.default` bound the roster's `flake`
    # member, which was `gen-flake.lib` self-resolving ITS gen-schema — a different node from
    # `gen/gen-schema`, so the short path would then have handed the reader a second build. That
    # reason is falsified by ADR-0031, and the long path now names an input the hub no longer has.
    gen-schema.follows = "gen/gen-schema";
    gen-algebra.follows = "gen/gen-schema/gen-algebra";

    # The terminal / output side keeps the demo's own nixpkgs + flake-parts (the flake-parts eval that
    # hosts the reader + emits outputs). nixpkgs-lib follows nixpkgs so the tree's injected `lib` and
    # the reader's `lib` are one instance.
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
}
