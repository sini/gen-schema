# First-class mixins (§ Bracha 1990).
# Reusable schema fragments with structural compatibility checks.
# Mixins are stored in _module.args so registries and outputs can reference them.
{ lib, schemaLib, genAlgebra, ... }:
let
  inherit (schemaLib) mkMixin beta composeMixins;
  record = genAlgebra.pure.record;
in
{
  config._module.args.demoMixins = rec {
    # Monitorable: any kind with "port" gets a metrics endpoint.
    # Smalltalk direction (default): mixin fields override parent.
    monitorable = mkMixin {
      name = "monitorable";
      requires = [ "port" ];
      provides = [
        "metricsPort"
        "metricsPath"
      ];
      define = parent: {
        metricsPort = lib.mkOption {
          type = lib.types.int;
          default = (record.select parent "port") + 1000;
          description = "Prometheus metrics port.";
        };
        metricsPath = lib.mkOption {
          type = lib.types.str;
          default = "/metrics";
          description = "Metrics scrape path.";
        };
      };
    };

    # TLS base: provides tls options.
    # Beta direction means existing fields take precedence over mixin's.
    tlsBase = mkMixin {
      name = "tlsBase";
      requires = [ ];
      provides = [
        "tlsEnabled"
        "tlsCertPath"
      ];
      define = _parent: {
        tlsEnabled = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether TLS is enabled.";
        };
        tlsCertPath = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Path to TLS certificate.";
        };
      };
    };

    # Composed: monitorable + beta(tlsBase).
    # monitorable requires "port", tlsBase has no requirements.
    # Beta direction means parent fields take precedence over tlsBase's.
    enhanced = composeMixins [
      monitorable
      (beta tlsBase)
    ];
  };
}
