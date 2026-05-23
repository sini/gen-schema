# Group instances — demonstrates setOf deduplication.
{ ... }:
{
  fleet.groups.web = {
    members = [
      "igloo"
      "iceberg"
      "igloo" # igloo deduped by id_hash
    ];
  };
}
