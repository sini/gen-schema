{
  lib,
  prelude,
  genSchema,
  genAlgebra,
  ...
}:
let
  R = genAlgebra.record;
  record = R;
  mixinLib = import ../../lib/mixin.nix { inherit prelude record; };
  inherit (mixinLib)
    mkMixin
    beta
    applyMixin
    ;
in
{
  flake.tests.mixin-basic.test-mkMixin-creates-mixin = {
    expr =
      (mkMixin
        {
          requires = [ "port" ];
          provides = [ "metrics_port" ];
        }
        (parent: {
          metrics_port = (R.select "port" parent) + 1000;
        })
      ).__isMixin;
    expected = true;
  };

  flake.tests.mixin-basic.test-mkMixin-default-direction = {
    expr = (mkMixin { } (_: { })).__direction;
    expected = "smalltalk";
  };

  flake.tests.mixin-basic.test-beta-changes-direction = {
    expr = (beta (mkMixin { } (_: { }))).__direction;
    expected = "beta";
  };

  flake.tests.mixin-basic.test-apply-mixin-adds-fields = {
    expr =
      let
        base = R.fromAttrs {
          port = 8080;
          hostname = "localhost";
        };
        m =
          mkMixin
            {
              requires = [ "port" ];
              provides = [ "metrics_port" ];
            }
            (parent: {
              metrics_port = (R.select "port" parent) + 1000;
            });
      in
      R.select "metrics_port" (applyMixin m base "service");
    expected = 9080;
  };

  flake.tests.mixin-basic.test-apply-mixin-preserves-base = {
    expr =
      let
        base = R.fromAttrs {
          port = 8080;
          hostname = "localhost";
        };
        m =
          mkMixin
            {
              requires = [ "port" ];
              provides = [ "metrics_port" ];
            }
            (parent: {
              metrics_port = (R.select "port" parent) + 1000;
            });
      in
      R.select "hostname" (applyMixin m base "service");
    expected = "localhost";
  };

  flake.tests.mixin-basic.test-apply-mixin-structural-check-fails = {
    expr = builtins.tryEval (
      let
        base = R.fromAttrs { hostname = "localhost"; };
        m = mkMixin { requires = [ "port" ]; } (_: { });
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
        } (_: { });
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
        m =
          mkMixin
            {
              requires = [ "port" ];
              provides = [ "status" ];
              kinds = [
                "service"
                "gateway"
              ];
            }
            (_: {
              status = "ok";
            });
      in
      R.has "status" (applyMixin m base "service");
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
        m = beta (
          mkMixin
            {
              requires = [ "port" ];
              provides = [ "display" ];
            }
            (_: {
              display = "mixin-display";
            })
        );
      in
      R.select "display" (applyMixin m base "service");
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
        m =
          mkMixin
            {
              requires = [ "port" ];
              provides = [ "display" ];
            }
            (_: {
              display = "mixin-display";
            });
      in
      R.select "display" (applyMixin m base "service");
    expected = "mixin-display"; # Smalltalk: mixin (child) wins
  };
}
