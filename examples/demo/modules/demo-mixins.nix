# First-class mixins (§ Bracha 1990).
# Reusable schema fragments with structural compatibility checks.
#
# Under the gen-flake value-injection split this is a READER-SIDE artifact: it is PURE library
# construction (mkMixin/beta/composeMixins over records), independent of the resolved fleet config,
# and no tree module consumes it. It therefore lives on the flake-parts side and is imported by
# `outputs.nix` to exercise the mixin API — rather than being composed into the gen tree (where its
# `_module.args.demoMixins` would not cross the pure→flake-parts boundary; only `config.*` values do).
{
  lib,
  genSchema,
  genAlgebra,
}:
let
  inherit (genSchema) mkMixin beta composeMixins;
  record = genAlgebra.record;
in
rec {
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
}
