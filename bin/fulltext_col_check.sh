#!/bin/sh
# Usage:  fulltext_col_check.sh  [--email|-e]
#
# Copyright (c) 2016-2018, Flinders University, South Australia. All rights reserved.
# Contributors: Library, Corporate Services, Flinders University.
# See the accompanying LICENSE file (or http://opensource.org/licenses/BSD-3-Clause).
#
# This script does the following:
# - Check User-Interface item count and OAI-PMH item count & warn if the
#   item counts differ.
# - Check if any non-mapped items & warn if any are found.
# - Check if any items no longer have a bitstream & warn if any such
#   items are found.
#
# What can cause DSpace to give differing item counts?
# - DSpace 3.1 bug: When an item is newly mapped to a collection using the
#   Batch Metadata Editing tool, DSpace does not update the last_modified
#   field. This causes such items to not appear at the OAI-PMH interface.
# - DSpace 3.1 bug: When an item is released from embargo, DSpace does
#   not update the last_modified field. This causes such items to not
#   appear at the OAI-PMH interface.
#
##############################################################################
URL_PROTO_HOST="http://dspace.example.com"			# CUSTOMISE
HDL_PREFIX="123456789"						# CUSTOMISE
COLLECTION_HDL="$HDL_PREFIX/35727"				# CUSTOMISE: Collection handle nnnn/mmmm

# Space separated list of email addresses for mailx
EMAIL_DEST_LIST="me@example.com" 		                # CUSTOMISE
TIMESTAMP_PRETTY=`date "+%Y-%m-%d %H:%M:%S"`			# Timestamp for humans
EMAIL_SUBJECT="FAC full-text collection check $TIMESTAMP_PRETTY"	# CUSTOMISE

HORIZ_LINE_CHAR='*'
HORIZ_LINE_LENGTH=60
HORIZ_LINE=`printf "%${HORIZ_LINE_LENGTH}s\n" "" |tr " " "$HORIZ_LINE_CHAR"`

##############################################################################
OAI_SET_SPEC=`echo "$COLLECTION_HDL" |sed 's~^~col_~; s~/~_~'`	# Collection OAI-PMH set spec: col_nnnn_mmmm
OAI_URL="$URL_PROTO_HOST/oai/request?verb=ListIdentifiers&metadataPrefix=oai_dc&set=$OAI_SET_SPEC"

UI_URL="$URL_PROTO_HOST/xmlui/handle/$COLLECTION_HDL/browse?type=title"

##############################################################################
DS_USER=$USER		# CUSTOMISE: Database user: Assume same name as the Unix user
DS_DB=dspace		# CUSTOMISE: Database name
DS_HOST="dspace-db.example.com"				# CUSTOMISE: Database remotehost
DS_CONNECT_OPTS="-h $DS_HOST -U $DS_USER -d $DS_DB"	# CUSTOMISE: Connect options
IS_DSPACE5=1		# CUSTOMISE: 1=DSpace 5 database schema; 0=DSpace 3 schema

# DSpace resource_type_id
# See https://github.com/DSpace/DSpace/blob/master/dspace-api/src/main/java/org/dspace/core/Constants.java
TYPE_BITSTREAM=0
TYPE_BUNDLE=1
TYPE_ITEM=2
TYPE_COLLECTION=3

##############################################################################
# Optionally override any of the above variables.
ENV_FNAME=`echo $0 |sed 's/\.sh$/_env.sh/'`	# Path to fulltext_col_check_env.sh
[ -f $ENV_FNAME ] && . $ENV_FNAME

##############################################################################
intro() {
  cat <<-EOMSG_INTRO
		  Program name:         `basename $0`
		  Server protocol/host: $URL_PROTO_HOST
		  FT collection handle: $COLLECTION_HDL

	EOMSG_INTRO
}

##############################################################################
# Check User-Interface item count versus OAI-PMH item count
##############################################################################
check_item_counts() {
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

  count_msg=""
  if [ -z "$ui_warning" -a -z "$oai_warning" ]; then
    if [ "$ui_count" = "$oai_count" ]; then
      count_msg="GOOD: The UI and OAI-PMH item counts are the same."
    else
      count_msg="**WARNING** The UI and OAI-PMH item counts differ. Please investigate."
    fi
  else
    count_msg="Cannot compare UI and OAI-PMH item counts due to warning below. Please investigate."
  fi

  cat <<-EOMSG_ITEM_COUNTS
		$HORIZ_LINE
		Check item counts
		$HORIZ_LINE

		$count_msg
		  User-Interface item count:  '$ui_count'$ui_warning
		  OAI-PMH item count:         '$oai_count'$oai_warning

		where
		  UI URL:      $UI_URL
		  OAI-PMH URL: $OAI_URL

	EOMSG_ITEM_COUNTS
}

##############################################################################
# Check if any non-mapped items
##############################################################################
check_if_nonmapped_items() {
  query_nonmapped_items count	# Count of non-mapped (ie. problem) items
  query_count="$query"

  query_nonmapped_items		# Detailed list of non-mapped items
  results=`echo "$query_count; $query" |psql $DS_CONNECT_OPTS -A`

  echo "$HORIZ_LINE"
  echo "Check if any items are not mapped"
  echo "$HORIZ_LINE"
  echo
  if [ `echo "$results" |head -1` = 0 ]; then
    echo "GOOD: All items in the full-text collection are mapped into it (not owned by it)."
  else
    echo "**WARNING**"
    echo "  The following items in the full-text collection are owned by it"
    echo "  (instead of being mapped into it). Please investigate."
    echo
    echo "$results" |awk 'NR>1'
  fi
  echo
}

##############################################################################
query_nonmapped_items() {
  if [ "$1" = "count" ]; then		# Record count only
    select_clause="count(*)"
    orderby_clause=""
    header_clause=""
    forcequote_clause=""
  else					# Record details
    select_clause="i.item_id, (select handle from handle where resource_type_id=$TYPE_ITEM and resource_id=i.item_id) item_hdl"
    orderby_clause="order by item_hdl"
    header_clause="header"
    forcequote_clause="force quote item_id, item_hdl"
  fi

  sql=`cat <<-EOSQL_NONMAPPED_ITEMS
		select
		  $select_clause
		from (
		  select item_id,owning_collection from item where owning_collection = (
		    -- select resource_id from handle where resource_type_id=$TYPE_COLLECTION and handle='$HDL_PREFIX/35857' -- TEST
		    select resource_id from handle where resource_type_id=$TYPE_COLLECTION and handle='$COLLECTION_HDL'
		  ) and item_id in (
		    select item_id from collection2item where collection_id = (
		      select resource_id from handle where resource_type_id=$TYPE_COLLECTION and handle='$COLLECTION_HDL'
		    )
		  )
		) i
		$orderby_clause
	EOSQL_NONMAPPED_ITEMS
`

  query=`cat <<-EOQRY_NONMAPPED_ITEMS
		copy (
		$sql
		)
		to stdout
		with
		delimiter ','
		csv
		$header_clause
		$forcequote_clause
	EOQRY_NONMAPPED_ITEMS
`
}

##############################################################################
# Check if any items no longer have a bitstream
##############################################################################
check_if_no_bitstreams() {
  query_no_bitstreams count	# Count of items with no bitstreams
  query_count="$query"

  query_no_bitstreams		# Detailed list of items with no bitstreams
  results=`echo "$query_count; $query" |psql $DS_CONNECT_OPTS -A`

  echo "$HORIZ_LINE"
  echo "Check if any items no longer have a bitstream"
  echo "$HORIZ_LINE"
  echo
  count=`echo "$results" |head -1`
  if [ "$count" = 0 ]; then
    echo "GOOD: All items in the full-text collection (still) have bitstreams."
  else
    echo "**WARNING**"
    echo "  The following items in the full-text collection no longer have (non-licence,"
    echo "  non-deleted and non-embargoed) bitstreams. Please investigate."
    echo
    echo "$results" |awk 'NR>1'
  fi
  echo
}

##############################################################################
query_no_bitstreams() {
  if [ "$1" = "count" ]; then		# Record count only
    select_clause="count(distinct item_id)"
    orderby_clause=""
    header_clause=""
    forcequote_clause=""
  else					# Record details
    select_clause="distinct item_id,
(select handle from handle where resource_type_id=$TYPE_ITEM and resource_id=i.item_id) item_hdl,
owning_collection, last_modified"
    orderby_clause="order by item_hdl"
    header_clause="header"
    forcequote_clause="force quote item_id, owning_collection, last_modified, item_hdl"
  fi

  if [ $IS_DSPACE5 = 1 ]; then
    bundle_clause=`cat <<-EOSQL_BUNDLE_CLAUSE

		      select resource_id from metadatavalue where text_value='ORIGINAL' and resource_type_id=$TYPE_BUNDLE and metadata_field_id in
		        (select metadata_field_id from metadatafieldregistry where element='title' and qualifier is null)

	EOSQL_BUNDLE_CLAUSE
`
  else
    bundle_clause="select bundle_id from bundle where name='ORIGINAL'"
  fi

  sql=`cat <<-EOSQL_NO_BITSTREAMS
		select
		  $select_clause
		from item i
		where
		  withdrawn = 'f' and
		  in_archive = 't' and
		  owning_collection is not null and
		  exists (select resource_id from handle h where h.resource_type_id=$TYPE_ITEM and h.resource_id=item_id) and

		  item_id in (
		    select item_id from collection2item where collection_id = (
		      -- select resource_id from handle where resource_type_id=$TYPE_COLLECTION and handle='$HDL_PREFIX/8266' -- TEST
		      select resource_id from handle where resource_type_id=$TYPE_COLLECTION and handle='$COLLECTION_HDL'
		    )
		  ) and

		  -- Does NOT have (non-licence, non-deleted and non-embargoed) bitstream
		  item_id not in (
		    select item_id from item2bundle where bundle_id in (
		      $bundle_clause
		    )
		    and bundle_id in (
		      select bundle_id from bundle2bitstream where bitstream_id in (
		        select bitstream_id from bitstream where deleted<>'t' and bitstream_id not in (
		          select resource_id from resourcepolicy where resource_type_id=$TYPE_BITSTREAM and start_date > 'now'
		        )
		      )
		    )
		  )
		$orderby_clause
	EOSQL_NO_BITSTREAMS
`
  query=`cat <<-EOQRY_NO_BITSTREAMS
		copy (
		$sql
		)
		to stdout
		with
		delimiter ','
		csv
		$header_clause
		$forcequote_clause
	EOQRY_NO_BITSTREAMS
`
}

##############################################################################
run_all_checks() {
  intro
  check_item_counts
  check_if_nonmapped_items
  check_if_no_bitstreams
}

##############################################################################
# main()
##############################################################################
if [ "$1" = --email -o "$1" = -e ]; then
  run_all_checks |mailx -s "$EMAIL_SUBJECT" $EMAIL_DEST_LIST
else
  run_all_checks
fi

