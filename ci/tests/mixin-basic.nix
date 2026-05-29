{
  lib,
  genSchema,
  genAlgebra,
  ...
}:
let
  R = genAlgebra.record;
  record = R;
  mixinLib = import ../../nix/lib/mixin.nix { inherit lib record; };
  inherit (mixinLib)
    mkMixin
    beta
    applyMixin
    ;
in
{
  flake.tests.mixin-basic.test-mkMixin-creates-mixin = {
    expr =
      (mkMixin {
        requires = [ "port" ];
        provides = [ "metrics_port" ];
        define = parent: {
          metrics_port = (R.select parent "port") + 1000;
        };
      }).__isMixin;
    expected = true;
  };

  flake.tests.mixin-basic.test-mkMixin-default-direction = {
    expr =
      (mkMixin {
        define = _: { };
      }).__direction;
    expected = "smalltalk";
  };

  flake.tests.mixin-basic.test-beta-changes-direction = {
    expr =
      (beta (mkMixin {
        define = _: { };
      })).__direction;
    expected = "beta";
  };

  flake.tests.mixin-basic.test-apply-mixin-adds-fields = {
    expr =
      let
        base = R.fromAttrs {
          port = 8080;
          hostname = "localhost";
        };
        m = mkMixin {
          requires = [ "port" ];
          provides = [ "metrics_port" ];
          define = parent: {
            metrics_port = (R.select parent "port") + 1000;
          };
        };
      in
      R.select (applyMixin m base "service") "metrics_port";
    expected = 9080;
  };

  flake.tests.mixin-basic.test-apply-mixin-preserves-base = {
    expr =
      let
        base = R.fromAttrs {
          port = 8080;
          hostname = "localhost";
        };
        m = mkMixin {
          requires = [ "port" ];
          provides = [ "metrics_port" ];
          define = parent: {
            metrics_port = (R.select parent "port") + 1000;
          };
        };
      in
      R.select (applyMixin m base "service") "hostname";
    expected = "localhost";
  };

  flake.tests.mixin-basic.test-apply-mixin-structural-check-fails = {
    expr = builtins.tryEval (
      let
        base = R.fromAttrs { hostname = "localhost"; };
        m = mkMixin {
          requires = [ "port" ];
          define = _: { };
        };
      in
      applyMixin m base "service"
    );
    expected = {
      success = false;
      value = false;
    };
  };

  flake.tests.mixin-basic.test-apply-mixin-kind-constraint-fails = {
    expr = builtins.tryEval (
      let
        base = R.fromAttrs { port = 8080; };
        m = mkMixin {
          requires = [ "port" ];
          kinds = [
            "service"
            "gateway"
          ];
          define = _: { };
        };
      in
      applyMixin m base "database"
    );
    expected = {
      success = false;
      value = false;
    };
  };

  flake.tests.mixin-basic.test-apply-mixin-kind-constraint-passes = {
    expr =
      let
        base = R.fromAttrs { port = 8080; };
        m = mkMixin {
          requires = [ "port" ];
          kinds = [
            "service"
            "gateway"
          ];
          provides = [ "status" ];
          define = _: {
            status = "ok";
          };
        };
      in
      R.has (applyMixin m base "service") "status";
    expected = true;
  };

  # Beta direction: kind's existing field wins over mixin's
  flake.tests.mixin-basic.test-beta-kind-wins-on-conflict = {
    expr =
      let
        base = R.fromAttrs {
          port = 8080;
          display = "base-display";
        };
        m = beta (mkMixin {
          requires = [ "port" ];
          provides = [ "display" ];
          define = _: { display = "mixin-display"; };
        });
      in
      R.select (applyMixin m base "service") "display";
    expected = "base-display"; # Beta: kind (parent) wins
  };

  # Smalltalk direction: mixin's field wins over kind's
  flake.tests.mixin-basic.test-smalltalk-mixin-wins-on-conflict = {
    expr =
      let
        base = R.fromAttrs {
          port = 8080;
          display = "base-display";
        };
        m = mkMixin {
          requires = [ "port" ];
          provides = [ "display" ];
          define = _: { display = "mixin-display"; };
        };
      in
      R.select (applyMixin m base "service") "display";
    expected = "mixin-display"; # Smalltalk: mixin (child) wins
  };
}
