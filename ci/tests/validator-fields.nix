# Row-polymorphic validator filtering: mkFieldValidator and filterValidators.
# Validators with __fields are skipped when any required field is absent from the kind.
# Plain validators (no __fields) always run regardless of kind options.
{
  lib,
  schemaLib,
  genLib,
  ...
}:
let
  validateLib = import ../../nix/lib/validate.nix {
    inherit lib;
    genAlgebra = genLib;
  };
  inherit (validateLib) mkFieldValidator filterValidators;
  inherit (genLib) mkValidator;

  # A plain validator (no fields) — always runs
  plainValidator = mkValidator "always-run" (inst: inst ? name) "must have name";

  # Requires both "port" and "protocol"
  portProtocolValidator = mkFieldValidator {
    fields = [
      "port"
      "protocol"
    ];
    name = "https-port-check";
    check = inst: !(inst.protocol == "https" && inst.port == 80);
    message = "HTTPS should not use port 80";
  };

  # Requires "metrics_port"
  metricsValidator = mkFieldValidator {
    fields = [ "metrics_port" ];
    name = "metrics-port-check";
    check = inst: inst.metrics_port > 0;
    message = "metrics port must be positive";
  };

  allValidators = [
    plainValidator
    portProtocolValidator
    metricsValidator
  ];

  # Kind with port, protocol, name — no metrics_port
  serviceOptionNames = [
    "port"
    "protocol"
    "name"
  ];

  # Kind with port, protocol, name, metrics_port
  monitoredOptionNames = [
    "port"
    "protocol"
    "name"
    "metrics_port"
  ];
in
{
  "validator-fields".test-field-validator-has-fields = {
    expr = portProtocolValidator ? __fields;
    expected = true;
  };

  "validator-fields".test-field-validator-preserves-pred = {
    expr = portProtocolValidator.pred {
      port = 443;
      protocol = "https";
    };
    expected = true;
  };

  "validator-fields".test-plain-validator-no-fields = {
    expr = plainValidator ? __fields;
    expected = false;
  };

  "validator-fields".test-filter-service-kind = {
    # plain + portProtocol pass; metrics excluded (metrics_port absent)
    expr = builtins.length (filterValidators serviceOptionNames allValidators);
    expected = 2;
  };

  "validator-fields".test-filter-monitored-kind = {
    # all three pass — monitored kind has metrics_port
    expr = builtins.length (filterValidators monitoredOptionNames allValidators);
    expected = 3;
  };

  "validator-fields".test-filter-empty-kind = {
    # only plain validator (no __fields) passes an empty option set
    expr = builtins.length (filterValidators [ ] allValidators);
    expected = 1;
  };

  "validator-fields".test-filter-plain-always-passes = {
    expr = builtins.length (filterValidators [ ] [ plainValidator ]);
    expected = 1;
  };
}
