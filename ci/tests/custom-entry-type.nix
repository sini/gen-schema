{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption mkInstanceRegistry;

  # Custom mkType that produces a simple attrset with a `modules` list
  # instead of the default deferredModule __functor wrapping.
  # This mimics what gen-aspects would do with its recursive aspectType.
  customMkType =
    {
      kindModule,
      collections,
      kind,
      defs ? [ ],
    }:
    let
      baseModules = lib.optional (kindModule != null) kindModule;
    in
    {
      __functor =
        _:
        { ... }:
        {
          imports = baseModules;
        };
      inherit kind;
      _customMarker = true;
    }
    // collections;

  # --- Basic: custom mkType produces a result without __functor wrapping from merge ---

  basicEval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption {
          mkType = customMkType;
        };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
        };
      }
    ];
  };

  hostKind = basicEval.config.schema.host;

  # --- Collections still extracted with custom mkType ---

  collectionEval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption {
          mkType = customMkType;
          collections.tags = {
            default = [ ];
          };
        };
        config.schema.host = {
          tags = [
            "server"
            "prod"
          ];
        };
      }
    ];
  };

  collectionHost = collectionEval.config.schema.host;

  # --- Collections stripped before custom type sees defs ---

  collectionStripEval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption {
          mkType = customMkType;
          collections.tags = {
            default = [ ];
          };
          strict = true;
        };
        options.hosts = mkInstanceRegistry collectionStripEval.config.schema "host" { };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
          tags = [ "server" ];
        };
        config.hosts.igloo = {
          name = "igloo";
        };
      }
    ];
  };

  stripResult = builtins.tryEval (
    builtins.deepSeq collectionStripEval.config.hosts.igloo collectionStripEval.config.hosts.igloo
  );

  # --- Introspection works with custom mkType ---
  # mkType receives kindModule (baseModule) and must produce a callable result.
  # Introspection uses lib.evalModules { modules = [ config.${k} ]; } so the
  # __functor must import modules that declare the options we want to introspect.

  introEval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption {
          mkType = customMkType;
          baseModule =
            kind:
            {
              host = {
                options.name = lib.mkOption { type = lib.types.str; };
              };
              user = {
                options.userName = lib.mkOption { type = lib.types.str; };
              };
            }
            .${kind} or { };
        };
        config.schema.host = { };
        config.schema.user = { };
      }
    ];
  };

  # --- Custom marker present (proves mkType controls the result) ---

  # --- baseModule passed as kindModule ---

  baseModEval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption {
          mkType = customMkType;
          baseModule = {
            options.base-field = lib.mkOption {
              type = lib.types.str;
              default = "from-base";
            };
          };
        };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
        };
      }
    ];
  };

  # Evaluate the custom type as a module to check baseModule options are accessible
  baseModInnerEval = lib.evalModules {
    modules = [ baseModEval.config.schema.host ];
  };

  # --- Mixin pipeline skipped with custom mkType ---
  # If mixins ran, they'd fail since our custom type doesn't go through applyMixin.
  # The fact that this evaluates proves mixins are skipped.

  mixinSkipEval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption {
          mkType = customMkType;
          mixins = [
            (
              { record, ... }:
              record
              // {
                extraField = {
                  type = lib.types.str;
                  default = "mixin-value";
                };
              }
            )
          ];
        };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
        };
      }
    ];
  };

  mixinSkipHost = mixinSkipEval.config.schema.host;

  # --- baseModule as function of kind name ---

  baseModFnEval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption {
          mkType = customMkType;
          baseModule = kind: {
            options.kindName = lib.mkOption {
              type = lib.types.str;
              default = kind;
            };
          };
        };
        config.schema.host = { };
      }
    ];
  };

  # --- Topology and edges resolve correctly with custom mkType ---
  # parent is a built-in collection; extractedCollections.parent flows through
  # // collections into the custom result, so config.${k}.parent is readable by
  # the topology derivation in _topology / _edges.

  topoEval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption {
          mkType = customMkType;
          collections.tags = {
            default = [ ];
          };
        };
        config.schema.host = {
          tags = [ "server" ];
        };
        config.schema.user = {
          parent = "host";
          tags = [ "person" ];
        };
      }
    ];
  };

  topoSchema = topoEval.config.schema;

in
{
  flake.tests.custom-entry-type.test-custom-marker-present = {
    expr = hostKind._customMarker;
    expected = true;
  };
  flake.tests.custom-entry-type.test-kind-on-result = {
    expr = hostKind.kind;
    expected = "host";
  };
  flake.tests.custom-entry-type.test-collections-extracted = {
    expr = collectionHost.tags;
    expected = [
      "server"
      "prod"
    ];
  };
  flake.tests.custom-entry-type.test-custom-type-works-with-registry = {
    # End-to-end: custom mkType + mkInstanceRegistry resolves an instance correctly.
    # Collection keys are stripped before the custom type sees defs, so strict eval succeeds.
    expr = stripResult.success;
    expected = true;
  };
  flake.tests.custom-entry-type.test-introspect-kind-names = {
    expr = introEval.config.schema._kindNames;
    expected = [
      "host"
      "user"
    ];
  };
  flake.tests.custom-entry-type.test-introspect-kind-meta = {
    expr = builtins.elem "name" (introEval.config.schema._kindMeta "host").optionNames;
    expected = true;
  };
  flake.tests.custom-entry-type.test-mixin-skipped = {
    expr = !(mixinSkipHost ? extraField);
    expected = true;
  };
  flake.tests.custom-entry-type.test-basemodule-passed-as-kindmodule = {
    # Proves baseModule was forwarded as kindModule: the __functor imports it,
    # so evaluating the type as a module exposes base-field in options.
    expr = baseModInnerEval.options ? base-field && baseModInnerEval.config.base-field == "from-base";
    expected = true;
  };
  flake.tests.custom-entry-type.test-basemodule-fn-resolved = {
    expr = baseModFnEval.config.schema.host.kind;
    expected = "host";
  };
  flake.tests.custom-entry-type.test-topology-with-custom-type = {
    expr = topoSchema._topology.user.parent;
    expected = "host";
  };
  flake.tests.custom-entry-type.test-edges-with-custom-type = {
    expr = builtins.any (e: e.from == "user" && e.to == "host" && e.type == "parent") topoSchema._edges;
    expected = true;
  };
  # The custom mkType controls the result structure entirely: its __functor is
  # present but the standard gen-schema wrapper fields (mixins, refinements) are
  # absent — proving the default deferredModule wrapping path was skipped.
  flake.tests.custom-entry-type.test-custom-functor-not-default-wrapper = {
    expr = hostKind ? __functor && !(hostKind ? mixins) && !(hostKind ? refinements);
    expected = true;
  };
}
