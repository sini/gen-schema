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
    # ONE plane: the `mkType` arm publishes as `options` and `refs` the option plane an instance
    # imports, which is the plane its `refinements` and its mark read. The standard arm, same
    # declaration, is the control.
    test-mktype-arm-publishes-the-plane-it-reads = {
      expr =
        let
          decl = {
            options.myPort = genMerge.mkOption { type = rp; };
            options.owner = genMerge.mkOption { type = genSchema.ref "user"; };
          };
          k = kindOf { mkType = aspectShaped; } decl;
          std = kindOf { } decl;
          names = kv: builtins.attrNames kv.options;
          imported = builtins.filter (n: builtins.substring 0 7 n != "_module") (
            builtins.attrNames (genMerge.evalModuleTree { modules = [ k ]; }).options
          );
        in
        {
          published = names k;
          inherit imported;
          refinementsWithinOptions = builtins.all (n: k.options ? ${n}) (builtins.attrNames k.refinements);
          refs = builtins.mapAttrs (_: r: r.refKind) k.refs;
          sameAsStandardArm =
            names k == names std && builtins.attrNames k.refs == builtins.attrNames std.refs;
        };
      expected = {
        published = [
          "myPort"
          "owner"
        ];
        imported = [
          "myPort"
          "owner"
        ];
        refinementsWithinOptions = true;
        refs.owner = "user";
        sameAsStandardArm = true;
      };
    };
    # A functor that READS its `self` declares from what the kind value publishes: here one `x`,
    # plus an `<n>_mirror` for every option `self.options` names. The tree the arm's plane is read
    # from and an instance must hand it the same `self`, or the instance declares `x_mirror` outside
    # the published plane, the mark and `refinements`, and the identity keys read the instance's.
    test-mktype-self-reading-functor-sees-one-plane = {
      expr =
        let
          mirror =
            { kind, ... }:
            {
              inherit kind;
              __functor = self: _: {
                options = {
                  x = genMerge.mkOption {
                    type = genMerge.types.str;
                    default = "x";
                  };
                }
                // builtins.listToAttrs (
                  map (n: {
                    name = "${n}_mirror";
                    value = genMerge.mkOption {
                      type = genMerge.types.str;
                      default = "m";
                    };
                  }) (builtins.attrNames (self.options or { }))
                );
              };
            };
          k = kindOf { mkType = mirror; } { };
          published = builtins.attrNames k.options;
        in
        {
          inherit published;
          imported = builtins.filter (n: builtins.substring 0 7 n != "_module") (
            builtins.attrNames (genMerge.evalModuleTree { modules = [ k ]; }).options
          );
          identityKeysArePublished = genSchema.identityKeysForKind { } k == [ "name" ] ++ published;
        };
      expected = {
        published = [ "x" ];
        imported = [ "x" ];
        identityKeysArePublished = true;
      };
    };
    # The `mkType` arm's mark reads the option plane an instance imports (mx07b §4 Q1 ruled (b),
    # den-hoag-88cfa; paid by (c+), den-hoag-markof-partial-preimage-znfjq): a refined and a bare
    # `mkType` kind mint APART.
    test-mktype-mark-reads-the-option-plane = {
      expr =
        mkKind.__mint.minted == (kindOf { mkType = aspectShaped; } {
          options.myPort = genMerge.mkOption { type = genMerge.types.int; };
        }).__mint.minted;
      expected = false;
    };
  };

  # WHICH refusal fired is the subject, so it lives on testsError (see ci/tests-error.nix's header).
  # The message is the one a non-`mkType` kind gives for the same declaration.
  flake.testsError.mktype-refinements-refusal = {
    # A caller whose `mkType` result is NOT a module functor (den-hoag-g8lo): the published value
    # carries its keys beside `options`, a module syntax gen-merge refuses on its first read, so
    # `refinements` refuses by name, as an instance of the kind does. Its door-or-falsifier is the
    # refusal, naming the kind and the first surplus key.
    test-mktype-non-module-result-refuses-by-name = {
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
      expectedError = {
        type = "ThrownError";
        msg = "^gen-merge: module `<gen-schema mkType kind host>' has an unsupported attribute `custom'[.] ";
      };
    };
    # The derivation reads the value an instance IMPORTS, not the raw `mkType` result: the raw result
    # `{ kind; options.myPort; }` would be refused naming `kind`, while the published value (its
    # `options` overwritten by `options = { }`) is refused naming `keySemantics`. The KEY is what
    # tells the two apart, so it is pinned.
    test-mktype-published-value-refusal-names-its-key = {
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
      expectedError = {
        type = "ThrownError";
        msg = "^gen-merge: module `<gen-schema mkType kind host>' has an unsupported attribute `keySemantics'[.] ";
      };
    };
    test-mktype-refined-option-refuses-by-name = {
      expr = hostsWith mkKind 70000;
      expectedError = {
        type = "ThrownError";
        msg = "gen-schema: refinement failed at host:a[.]myPort";
      };
    };
  };
}
