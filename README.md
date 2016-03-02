# FlindersDSpace-FullTextCollection

Tools for creating and reporting on a DSpace full-text collection.

## fulltext_col_check.sh

This script does the following:

- Checks User-Interface item count and OAI-PMH item count & warns if the
  item counts differ.
- Checks if there are any non-mapped items & warns if any are found.
- Checks if any items no longer have a bitstream & warns if any such
  items are found.

What can cause DSpace to give differing item counts?

- DSpace 3.1 bug: When an item is newly mapped to a collection using the
  Batch Metadata Editing tool, DSpace does not update the last_modified
  field. This causes such items to not appear at the OAI-PMH interface.
- DSpace 3.1 bug: When an item is released from embargo, DSpace does
  not update the last_modified field. This causes such items to not
  appear at the OAI-PMH interface.

