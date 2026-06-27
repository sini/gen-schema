{
  lib,
  genSchema,
  genAlgebra,
  ...
}:
let
  refinedLib = import ../../lib/refined.nix { inherit lib; };
  inherit (refinedLib)
    types
    isRefined
    getRefinements
    checkRefinements
    refinements
    ;

  # Single refinement
  refinedPort = types.refined lib.types.int {
    check = self: self > 0 && self < 65536;
    message = "must be valid port";
  };

  # Composed refinements — two independent upper/lower bounds, both can fail together
  strictPort = types.refined lib.types.int [
    {
      check = self: self >= 1024;
      message = "must be >= 1024";
    }
    {
      check = self: self < 65536;
      message = "must be < 65536";
    }
  ];
in
{
  flake.tests.refined-basic.test-is-refined = {
    expr = isRefined refinedPort;
    expected = true;
  };

  flake.tests.refined-basic.test-plain-type-not-refined = {
    expr = isRefined lib.types.int;
    expected = false;
  };

  flake.tests.refined-basic.test-get-refinements-count = {
    expr = builtins.length (getRefinements refinedPort);
    expected = 1;
  };

  flake.tests.refined-basic.test-composed-refinements-count = {
    expr = builtins.length (getRefinements strictPort);
    expected = 2;
  };

  flake.tests.refined-basic.test-check-valid-value = {
    expr = checkRefinements "port" refinedPort 8080;
    expected = [ ];
  };

  flake.tests.refined-basic.test-check-invalid-value = {
    expr = builtins.length (checkRefinements "port" refinedPort (-1));
    expected = 1;
  };

  flake.tests.refined-basic.test-check-failure-structure = {
    expr =
      let
        failures = checkRefinements "port" refinedPort (-1);
      in
      builtins.head failures;
    expected = {
      field = "port";
      message = "must be valid port";
      value = -1;
      lazy = false;
    };
  };

  # 0 fails both: not >= 1024 and not < 65536 is irrelevant, but 0 < 65536 passes...
  # Use 70000: fails < 65536 but passes >= 1024 → one failure
  # Use 0: fails >= 1024 but passes < 65536 → one failure
  # Use 70000 and add a value that fails both: impossible with these bounds (any int either >= 1024 or not, either < 65536 or not)
  # A value > 65535 fails the second; a value < 1024 fails the first. Can't fail both simultaneously with disjoint ranges.
  # Redesign: use two overlapping upper bounds so a large value fails both.
  flake.tests.refined-basic.test-composed-both-fail = {
    expr =
      let
        bothFail = types.refined lib.types.int [
          {
            check = self: self < 100;
            message = "must be < 100";
          }
          {
            check = self: self < 200;
            message = "must be < 200";
          }
        ];
      in
      builtins.length (checkRefinements "x" bothFail 300);
    expected = 2;
  };

  flake.tests.refined-basic.test-composed-one-fails = {
    expr = builtins.length (checkRefinements "port" strictPort 70000);
    expected = 1;
  };

  flake.tests.refined-basic.test-reusable-refinement = {
    expr =
      let
        portType = types.refined lib.types.int refinements.tcpPort;
      in
      checkRefinements "port" portType 8080;
    expected = [ ];
  };

  flake.tests.refined-basic.test-reusable-refinement-invalid = {
    expr =
      let
        portType = types.refined lib.types.int refinements.tcpPort;
      in
      builtins.length (checkRefinements "port" portType 0);
    expected = 1;
  };

  # Refined type preserves base NixOS type behavior
  flake.tests.refined-basic.test-evalmodules-with-refined-type = {
    expr =
      let
        eval = lib.evalModules {
          modules = [
            {
              options.port = lib.mkOption { type = refinedPort; };
              config.port = 8080;
            }
          ];
        };
      in
      eval.config.port;
    expected = 8080;
  };

  flake.tests.refined-basic.test-base-type-preserved = {
    expr = refinedPort.name;
    expected = lib.types.int.name;
  };

  flake.tests.refined-basic.test-lazy-refinement-flag = {
    expr =
      let
        lazyType = types.refined lib.types.int {
          check = self: self > 0;
          message = "must be positive";
          lazy = true;
        };
        failures = checkRefinements "x" lazyType (-1);
      in
      (builtins.head failures).lazy;
    expected = true;
  };
}
