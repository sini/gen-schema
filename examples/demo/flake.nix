{
  description = "gen-schema demo: typed fleet management via gen-flake value-injection (schema, refs, strict validation)";

  # Value-injection migration (gen-flake). The gen definition tree (./gen-modules) is composed PURELY
  # by gen-flake's `flakeModules.default` — gen-merge's byte-mode `evalModuleTree`, NOT flake-parts'
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
        ...
      }:
      {
        # gen-flake v1 injects `genValues` into the top-level flake args only; `perSystem` injection is
        # opt-in (`gen.injectPerSystem`, default off) and emits no `perSystem` definition otherwise.
        # This demo reads `genValues` from a top-level reader module and produces no per-system outputs,
        # so no `systems` declaration is required.

        imports = [
          inputs.gen-flake.flakeModules.default
          ./modules/outputs.nix
        ];

        # PURE composition of the gen definition tree. gen-flake threads its own
        # gen-merge/gen-schema/gen-aspects into every tree module; the demo adds the two extra module
        # args the relocated definitions reach for: `lib` (their kind definitions use nixpkgs
        # `lib.mkOption`/`lib.types`) and `genAlgebra` (record algebra + the Either pipeline). Passed
        # via `gen.specialArgs` so the pure `evalModuleTree` sees them (it auto-provides only
        # `config`/`options`).
        gen.tree = ./gen-modules;
        gen.specialArgs = {
          inherit lib;
          genAlgebra = inputs.gen-algebra.lib;
        };

        # READER-side gen LIBRARIES (distinct from the injected VALUES). `outputs.nix` renders over the
        # injected `genValues` with these: `renderDocs`/`mkCodec`/`blame`/`applyMixin`. Injected into
        # the flake's top-level module args alongside gen-flake's `genValues`.
        _module.args = {
          genSchema = inputs.gen-schema.lib;
          genAlgebra = inputs.gen-algebra.lib;
        };
      }
    );

  inputs = {
    # gen-flake — the pure composition boundary (v1). Pinned via its published github rev. It threads
    # the published pure stack (gen-schema / gen-aspects / gen-merge / …) into the tree, so relocated
    # definition modules receive `{ genSchema, genMerge, ... }` as today.
    gen-flake.url = "github:sini/gen-flake";

    # Reuse the EXACT gen-schema / gen-algebra instances gen-flake threads into the pure tree, so the
    # reader-side renderDocs/mkCodec/applyMixin operate on type + record objects structurally identical
    # to the injected `genValues` (and no duplicate fetch). gen-algebra rides gen-schema's own pin.
    gen-schema.follows = "gen-flake/gen-schema";
    gen-algebra.follows = "gen-flake/gen-schema/gen-algebra";

    # The terminal / output side keeps the demo's own nixpkgs + flake-parts (the flake-parts eval that
    # hosts the reader + emits outputs). nixpkgs-lib follows nixpkgs so the tree's injected `lib` and
    # the reader's `lib` are one instance.
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
}
