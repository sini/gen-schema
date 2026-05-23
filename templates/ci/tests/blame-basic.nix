{ lib, schemaLib, ... }:
let
  blameLib = import ../../../nix/lib/blame.nix { inherit lib; };
  inherit (blameLib) blame isBlame collectBlame;
in
{
  blame-basic.test-blame-constructor = {
    expr = blame "port" "invalid value";
    expected = { __blame = true; field = "port"; message = "invalid value"; };
  };

  blame-basic.test-isBlame-true = {
    expr = isBlame (blame "port" "bad");
    expected = true;
  };

  blame-basic.test-isBlame-false-plain-attrset = {
    expr = isBlame { field = "port"; };
    expected = false;
  };

  blame-basic.test-isBlame-false-non-attrset = {
    expr = isBlame "not an attrset";
    expected = false;
  };

  blame-basic.test-collectBlame-filters = {
    expr = collectBlame [
      (blame "port" "bad port")
      null
      { some = "other"; }
      (blame "host" "bad host")
    ];
    expected = [
      { __blame = true; field = "port"; message = "bad port"; }
      { __blame = true; field = "host"; message = "bad host"; }
    ];
  };

  blame-basic.test-collectBlame-empty = {
    expr = collectBlame [ null { x = 1; } ];
    expected = [];
  };
}
