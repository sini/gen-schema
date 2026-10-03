# A PATH module naming itself, defining one declared and one undeclared key (STRICT MODE's refusal
# names the file the undeclared definition came from).
{
  _file = "/real/ST.nix";
  config.DECLAREDOPTION = 1;
  config.OFFENDINGKEY = 2;
}
