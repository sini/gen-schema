# Structured blame error constructor for field-level attribution.
{ lib }:
{
  blame = field: message: {
    __blame = true;
    inherit field message;
  };

  isBlame = v: builtins.isAttrs v && v ? __blame;

  collectBlame = results:
    builtins.filter (r: r != null && builtins.isAttrs r && r ? __blame) results;
}
