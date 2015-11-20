# FlindersDSpace-FullTextCollection

Tools for creating and reporting on a DSpace full-text collection.

## fulltext_report.sh

This script does the following:

- Gets a DSpace collection page from the User Interface (UI) and
  reads the item count from it.
- Gets a DSpace collection page from the OAI-PMH interface and
  reads the item count from it.
- Gives a warning if the 2 item counts differ.

What can cause DSpace to give differing item counts?

- When our collection had no submitters configured, our collection
  (which only contained items mapped using the Batch Metadata
  Editing Tool) had an OAI-PMH item count of zero. [DSpace 3.1]
- We had an item containing 2 URLs in a single dc.rights field
  (rather than 2 separate fields). This mapped item was counted
  and visible within the XML-UI, but did not exist within the
  OAI-PMH interface. [DSpace 3.1]

