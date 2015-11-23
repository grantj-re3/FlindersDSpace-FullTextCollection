#!/bin/sh
# fulltext_report.sh
#
# Copyright (c) 2015, Flinders University, South Australia. All rights reserved.
# Contributors: Library, Information Services, Flinders University.
# See the accompanying LICENSE file (or http://opensource.org/licenses/BSD-3-Clause).
#
# This script does the following:
# - Gets a DSpace collection page from the User Interface (UI) and
#   reads the item count from it.
# - Gets a DSpace collection page from the OAI-PMH interface and
#   reads the item count from it.
# - Gives a warning if the 2 item counts differ.
#
# What can cause DSpace 3.1 to give differing item counts?
# - When our collection had no submitters configured, our collection
#   (which only contained items mapped using the Batch Metadata
#   Editing Tool) had an OAI-PMH item count of zero.
# - We had an item containing 2 URLs in a single dc.rights field
#   (rather than 2 separate fields). This mapped item was counted
#   and visible within the XML-UI, but did not exist within the
#   OAI-PMH interface.
#
##############################################################################
URL_PROTO_HOST="http://dspace.example.com"			# CUSTOMISE
COLLECTION_HDL="2328/35727"					# CUSTOMISE: Collection handle nnnn/mmmm

OAI_SET_SPEC=`echo "$COLLECTION_HDL" |sed 's~^~col_~; s~/~_~'`	# Collection OAI-PMH set spec: col_nnnn_mmmm

UI_URL="$URL_PROTO_HOST/xmlui/handle/$COLLECTION_HDL/browse?type=title"
OAI_URL="$URL_PROTO_HOST/oai/request?verb=ListIdentifiers&metadataPrefix=oai_dc&set=$OAI_SET_SPEC"

EMAIL_DEST_LIST="me@example.com" 		                # CUSTOMISE
TIMESTAMP_PRETTY=`date "+%Y-%m-%d %H:%M:%S"`			# Timestamp for humans
EMAIL_SUBJECT="FAC full-text collection report $TIMESTAMP_PRETTY"	# CUSTOMISE

##############################################################################
ui_count=`wget -q -O - "$UI_URL" |
  egrep class.*pagination-info |
  head -1 |
  sed 's~</p>.*$~~; s~^.* ~~'`

oai_count=`wget -q -O - "$OAI_URL" |
  grep "completeListSize" |
  sed 's~^.*completeListSize="~~; s~".*$~~'`

ui_warning=""
if ! echo "$ui_count" |egrep -q "^[[:digit:]]+$"; then
  ui_warning=" WARNING - not an integer!"
fi

oai_warning=""
if ! echo "$oai_count" |egrep -q "^[[:digit:]]+$"; then
  oai_warning=" WARNING - not an integer!"
fi

bad_count_msg=""
if [ -z "$ui_warning" -a -z "$oai_warning" -a "$ui_count" != "$oai_count" ]; then
  bad_count_msg="**WARNING** The UI and OAI-PMH item counts above differ. Please investigate."
fi

(
	cat <<-EOMSG_COUNT_REPORT
		Program name:         `basename $0`
		Server protocol/host: $URL_PROTO_HOST
		Collection handle:    $COLLECTION_HDL

		UI item count:        '$ui_count'$ui_warning
		OAI-PMH item count:   '$oai_count'$oai_warning
		$bad_count_msg

		---
		UI URL:      $UI_URL
		OAI-PMH URL: $OAI_URL
	EOMSG_COUNT_REPORT
) |mailx -s "$EMAIL_SUBJECT" $EMAIL_DEST_LIST

