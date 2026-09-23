# A kind built through `mkType` carries the refinement contract its option plane declares
# (den-hoag-mx07b). The `mkType` arm derives `refinements` from the option plane of the value an
# instance imports, through the same `refinementsOfOptions` projection as every other arm, so a refined
# option declared under `mkType` is enforced by the instance registry instead of silently accepted.
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption mkInstanceRegistry;
  rp = genSchema.refined genMerge.types.int genSchema.refinements.tcpPort;

  # gen-aspects' door (`gen-aspects/lib/schema.nix`, binding `schemaOpt`): a module-functor value.
  aspectShaped =
    { defs, kind, ... }:
    {
      __functor = _: _: { imports = map (d: d.value) defs; };
      inherit kind;
    };

  kindOf =
    args: decl:
    (genMerge.evalModuleTree {
      modules = [
        { options.schema = mkSchemaOption args; }
        { config.schema.host = decl; }
      ];
    }).config.schema.host;

  hostsWith =
    k: v:
    (genMerge.evalModuleTree {
      modules = [
        { options.hosts = mkInstanceRegistry k { }; }
        { config.hosts.a.myPort = v; }
      ];
    }).config.hosts.a.myPort;

  refinedDecl = {
    options.myPort = genMerge.mkOption { type = rp; };
  };
  mkKind = kindOf { mkType = aspectShaped; } refinedDecl;
in
{
  flake.tests.mktype-refinements = {
    test-mktype-kind-carries-its-refinement = {
      expr = builtins.attrNames mkKind.refinements;
      expected = [ "myPort" ];
    };
    # Reached through `imports` rather than `options` directly: the refinement plane follows the
    # option plane, not a spelling.
    test-mktype-imports-style-is-enforced = {
      expr =
        (builtins.tryEval (
          hostsWith (kindOf { mkType = aspectShaped; } {
            imports = [ refinedDecl ];
          }) 70000
        )).success;
      expected = false;
    };
    # Controls: an admissible value passes, and an UNREFINED option carries no contract (the
    # projection invents nothing).
    test-mktype-admissible-value-passes = {
      expr = hostsWith mkKind 8080;
      expected = 8080;
    };
    test-mktype-unrefined-option-carries-no-contract = {
      expr =
        builtins.attrNames
          (kindOf { mkType = aspectShaped; } {
            options.myPort = genMerge.mkOption { type = genMerge.types.int; };
          }).refinements;
      expected = [ ];
    };
    # Totality over a caller whose `mkType` result is NOT a module functor (den-hoag-g8lo): the
    # derivation answers { } rather than throwing.
    test-mktype-non-module-result-is-total = {
      expr =
        builtins.attrNames
          (kindOf {
            mkType =
              { kind, ... }:
              {
                inherit kind;
                custom = true;
              };
          } refinedDecl).refinements;
      expected = [ ];
    };
    # The derivation reads the value an instance IMPORTS, not the raw `mkType` result. A non-functor
    # result carrying its own `options.myPort` has that key overwritten by the published `options = { }`,
    # so its instances declare no `myPort` and the kind must publish no contract on it.
    test-mktype-derives-from-the-published-value = {
      expr =
        builtins.attrNames
          (kindOf {
            mkType =
              { kind, ... }:
              {
                inherit kind;
                options.myPort = genMerge.mkOption { type = rp; };
              };
            strict = false;
          } refinedDecl).refinements;
      expected = [ ];
    };
    # The `mkType` arm's mark does not read the option plane: a refined and a bare `mkType` kind mint
    # EQUAL. Whether that plane enters the preimage is an owner ruling not yet made (mx07b §4 Q1); this
    # cell is the one to rewrite deliberately if it is.
    test-mktype-mark-is-blind-to-the-option-plane = {
      expr =
        mkKind.__mint.minted == (kindOf { mkType = aspectShaped; } {
          options.myPort = genMerge.mkOption { type = genMerge.types.int; };
        }).__mint.minted;
      expected = true;
    };
  };

  # WHICH refusal fired is the subject, so it lives on testsError (see ci/tests-error.nix's header).
  # The message is the one a non-`mkType` kind gives for the same declaration.
  flake.testsError.mktype-refinements-refusal = {
    test-mktype-refined-option-refuses-by-name = {
      expr = hostsWith mkKind 70000;
      expectedError = {
        type = "ThrownError";
        msg = "gen-schema: refinement failed at host:a[.]myPort";
      };
    };
  };
}
