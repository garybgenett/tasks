#!/usr/bin/env perl
use strict;
use warnings;
################################################################################

use Carp qw(confess);
#>>>$SIG{__WARN__}	= \&confess;
#>>>$SIG{__DIE__}	= \&confess;

use Data::Dumper;
sub DUMPER {
	my $DUMP = shift();
	local $Data::Dumper::Purity = 1;
	&printer(2, "<-- DUMPER " . ("-" x 30) . ">\n");
	&printer(2, Dumper(${DUMP}));
	&printer(2, "<-- DUMPER " . ("-" x 30) . ">\n");
	return(0);
};

########################################

use WWW::Mechanize;
my $mech = WWW::Mechanize->new(
	"agent"		=> "Mozilla/5.0",
	"autocheck"	=> "1",
	"stack_depth"	=> "0",
	"onwarn"	=> \&mech_fail,
	"onerror"	=> \&mech_fail,
);
sub mech_fail {
	&DUMPER($mech->response());
	&confess();
};

use JSON::XS;
my $json = JSON::XS->new();
$json->ascii(1);
$json->canonical(1);
$json->pretty(1);

use POSIX qw(strftime);
use Time::Local qw(timegm timelocal);

########################################

$| = "1";

################################################################################

my $URL_AUTH	= "https://accounts.zoho.com/apiauthtoken/nb/create";
sub URL_FETCH	{ "https://crm.zoho.com/crm/private/json/" . shift() . "/getRecords"; };
sub URL_LINK	{ "https://crm.zoho.com/crm/EntityInfo.do?module=" . shift() . "&id=" . shift(); };

my $URL_SCOPE	= "crmapi";
my $API_SCOPE	= "ZohoCRM/${URL_SCOPE}";

my $APP_NAME	= "ZohoCRM Export";
my $THOROUGH	= "0"; # MANUAL TOGGLE: DOES NOT SEEM TO WORK (SKIPS MULTIPLE ENTRIES)

########################################

my $AUTH_CRED	= ".zoho-auth";
my $AUTH_TOKEN	= ".zoho-token";

my $LEGEND_NAME	= "Marker: Legend";
my $LEGEND_FILE	= ".zoho.reports";
my $LEGEND_IMP	= "1";

my $TODAY_NAME	= "Marker: Today";
my $TODAY_EXP	= "zoho.today.md";
my $TODAY_IMP	= "zoho.today.out.md";
my $TODAY_TMP	= "zoho.today.tmp.md";

my $FIND_NOTES	= "0"; # MANUAL TOGGLE: HUGE DRAIN ON API REQUESTS (ONLY USE ONCE OR TWICE A DAY)
my $NOTES_FILE	= "zoho/_Note.csv";

my $JSON_BASE	= "zoho-export";
my $CSV_FILE	= "zoho-data.csv";
my $ALL_FILE	= "zoho.all.md";
my $OUT_FILE	= "zoho.md";

my $START_DATE	= "2016-10-24"; if ($ARGV[0] && $ARGV[0] =~ m/^[0-9]{4}[-][0-9]{2}[-][0-9]{2}$/) { $START_DATE = shift(); };
my $CSV_DATE	= "2017-01-02";
my $SORT_COLUMN	= "Modified DateTime";
my $SORT_ORDER	= "asc";
my $MAX_RECORDS	= "200";

my $NULL_CNAME	= "\[0 NULL\]";
my $NULL_ENAME	= "New Event";
my $NAME_DIV	= " ";
my $DSC_IMPORT	= "IMPORTED";
my $DSC_EXP_BD	= "CANCELLED";	my $DSC_EXP_BD_I	= "X";
my $DSC_EXP_GD	= "CANCEL";	my $DSC_EXP_GD_I	= "!";
my $DSC_FLAG	= "WORK";
my $NON_ASCII	= "###";
my $NON_ASCII_M	= "[^[:ascii:]]";
my $CLOSED_MARK	= "[\$]";

my $MARK_REGEX	= "^([\$A-Z:-]+)[:][ ]";
my $SPLIT_CHAR	= "[\|]";
my $A_BEG_CHAR	= "[\[]";
my $A_END_CHAR	= "[\]]";

my $SEC_IN_DAY	= 60 * 60 * 24;
my $AGING_DAYS	= 28 * 5;

########################################

my $LEVEL_1	= "#" x 3;
my $LEVEL_2	= "#" x 4;
my $HEAD_MARKER	= "#";

my $S_UID	= "%-19.19s";
my $S_DATE	= "%-19.19s";
my $S_DATE_ONLY	= "%-10.10s";

########################################

my $TYPES	= [ "Leads", "Tasks", "Events" ];

my $LID		= "LEADID";
my $SRC		= "Lead Source";
my $STS		= "Lead Status";
my $FNM		= "First Name";
my $LNM		= "Last Name";
my $CMP		= "Company";

my $RID		= "RELATEDTOID";

my $TID		= "ACTIVITYID";
my $DUE		= "Due Date";
my $CLT		= "Closed Time";
my $TST		= "Status";
my $PRI		= "Priority";

my $UID		= "UID";
my $MOD		= "Modified Time";
my $BEG		= "Start DateTime";
my $END		= "End DateTime";
my $REL		= "Related To";
my $SUB		= "Subject";
my $LOC		= "Venue";
my $DSC		= "Description";

########################################

our $USERNAME;
our $PASSWORD;
do("./${AUTH_CRED}") || die();

our $APITOKEN;
do("./${AUTH_TOKEN}") || die();

################################################################################

my $API_REQUEST_COUNT = "0";

########################################

if (!${APITOKEN}) {
	$mech->get(${URL_AUTH}
		. "?SCOPE=${API_SCOPE}"
		. "&DISPLAY_NAME=${APP_NAME}"
		. "&EMAIL_ID=${USERNAME}"
		. "&PASSWORD=${PASSWORD}"
	);
	$APITOKEN = $mech->content();
	$APITOKEN =~ s/^.+AUTHTOKEN[=](.+)\n.+$/$1/gms;

	open(OUTPUT, ">", ${AUTH_TOKEN}) || die();
	print OUTPUT "our \$APITOKEN = '${APITOKEN}';\n";
	close(OUTPUT) || die();
};

########################################

open(ALL_FILE, ">", ${ALL_FILE}) || die();
open(OUT_FILE, ">", ${OUT_FILE}) || die();
open(TODAY_TMP, ">", ${TODAY_TMP}) || die();

sub printer {
	my $output	= shift() || "";

	my $stderr	= "0";

	if (${output} =~ m/^[0123]$/) {
		$stderr = ${output};
		$output = "";
	};
	$output .= join("", @{_});

	if (${stderr} == 3) {
		print TODAY_TMP ${output};
	}
	elsif (${stderr} == 2) {
		print ALL_FILE ${output};
		print STDERR ${output};
	}
	elsif (${stderr}) {
		print ALL_FILE ${output};
	}
	else {
		print ALL_FILE ${output};
		print OUT_FILE ${output};
	};
};

sub printer_test {
	&DUMPER("DUMPER");

	&printer(2, "output\n");
	&printer(1, "stderr\n");
	&printer(0, "stdout\n");
	&printer("no_std\n");

	&printer(2, "output",	"multiple", "arguments", "\n");
	&printer(1, "stderr",	"multiple", "arguments", "\n");
	&printer(0, "stdout",	"multiple", "arguments", "\n");
	&printer("no_std",	"multiple", "arguments", "\n");
};
#>>>&printer_test();

########################################

&printer(2, "${LEVEL_1} Processing Log\n");
#>>>&printer(2, "\n");
#>>>&printer(2, "\tTOKEN: ${APITOKEN}\n");

################################################################################

my $z = {
	"leads"		=> {},
	"tasks"		=> {},
	"events"	=> {},
};
my $leads		= $z->{"leads"};
my $tasks		= $z->{"tasks"};
my $events		= $z->{"events"};

my $closed_list		= {};
my $cancel_bd_list	= {};
my $cancel_gd_list	= {};
my $related_list	= {};
my $empty_events	= [];
my $orphaned_tasks	= {};

my $fail_exit		= "0";

########################################

sub fetch_entries {
	my $type	= shift() || "Events";

	my $last_mod	= ${START_DATE};
	my $index_no	= "1";
	my $index_to	= "1";
	my $records	= "0";
	my $fetches	= {};
	my $output;
	my $found;

	&printer(2, "\n\tFetching ${type}...");

	while (1) {
		if ($last_mod =~ m/^[0-9]{4}[-][0-9]{2}[-][0-9]{2}$/) {
			$last_mod .= " 00:00:00";
		};
		if (${THOROUGH}) {
			$last_mod =~ s/^([0-9]{4}[-][0-9]{2}[-][0-9]{2}).*$/${1} 00:00:00/g;
			$index_no = "1";
		};
		$index_to = (${index_no} + (${MAX_RECORDS} -1));

		&printer(2, "\n\tProcessing: ${last_mod} (${index_no} to ${index_to})... ");

		$mech->get(&URL_FETCH(${type})
			. "?scope=${URL_SCOPE}"
			. "&authtoken=${APITOKEN}"
			. (${THOROUGH} ? "&lastModifiedTime=${last_mod}" : "")
			. "&sortColumnString=${SORT_COLUMN}"
			. "&sortOrderString=${SORT_ORDER}"
			. "&fromIndex=${index_no}"
			. "&toIndex=${index_to}"
		) && $API_REQUEST_COUNT++;
		$output = decode_json($mech->content());

		if ( $output->{"response"}{"nodata"} ) {
			&printer(2, "\n\tNo Data!");
			last();
		};

		my($uid, $new);
		if (ref( $output->{"response"}{"result"}{$type}{"row"} ) eq "ARRAY") {
			$found = $#{		$output->{"response"}{"result"}{$type}{"row"} };
			foreach my $event (@{	$output->{"response"}{"result"}{$type}{"row"} }) {
				(${last_mod}, ${uid}, ${new}) = &parse_entry( $event->{"FL"} );
				$fetches->{$uid} = ${new};
			};
		} else {
			$found = $#{					$output->{"response"}{"result"}{$type}{"row"}{"FL"} };
			(${last_mod}, ${uid}, ${new}) = &parse_entry(	$output->{"response"}{"result"}{$type}{"row"}{"FL"} );
			$fetches->{$uid} = ${new};
		};

		$records += ++${found};
		&printer(2, "${found} records found (${records} total).");

		if (${found} < ${MAX_RECORDS}) {
			&printer(2, "\n\tCompleted!");
			last();
		};

		$index_no += ${MAX_RECORDS};
	};

	&printer(2, "\n");

	&printer(2, "\tTotal ${type}: " . scalar(keys(%{$fetches})) . "\n");

	return(%{$fetches});
};

########################################

sub parse_entry {
	my $event	= shift();

	my $new		= {};
	my $uid;
	my $mod;

	foreach my $value (@{$event}) {
		if ($value->{"val"} eq ${LID} || $value->{"val"} eq ${TID} || $value->{"val"} eq ${UID}) {
			$uid = $value->{"content"};
		};
		if ($value->{"val"} eq ${MOD}) {
			$mod = $value->{"content"};
		};

		$new->{ $value->{"val"} } = $value->{"content"};
	};

	return(${mod}, ${uid}, ${new});
}

########################################

sub update_legend {
	&update_file(${LEGEND_NAME}, ${LEGEND_FILE}, ${LEGEND_IMP});

	return(0);
};

########################################

sub update_today {
	if (-f ${TODAY_IMP}) {
		&update_file(${TODAY_NAME}, ${TODAY_IMP}, "1");
		unlink(${TODAY_IMP}) || die();
	} else {
		&update_file(${TODAY_NAME}, ${TODAY_EXP});
	};

	return(0);
};

########################################

sub update_file {
	my $title	= shift();
	my $file	= shift();
	my $import	= shift();

	my $uid		= "";
	my $output	= "";
	my $input;

	&printer(2, "\n");
	&printer(2, "\tMatching '${title}'...\n");

	if (-f ${file}) {
		open(FILE, "<", ${file}) || die();
		if (${import}) {
			$output = (stat(${file}))[9];
			$output = localtime(${output}) . "\n\n";
		};
		$output .= do { local $/; <FILE> };
		# make the input for "&print_events()" and "foreach my $search (@{ARGV})" pretty
		$output =~ s/^["]([${HEAD_MARKER}])[ ]([^"]*)["]$/${1} ${2}/gm;
		$output =~ s/^["][^|]*[|][^|]*[|]([^|]+)[|](.+)["]$/[${1}] ${2}/gm;
		$output =~ s/[ ]${A_BEG_CHAR}(.*)${A_END_CHAR}$/ {${1}}/gm;
		close(FILE) || die();
	};

	foreach my $event (sort(keys(%{$events}))) {
		if ($events->{$event}{$SUB} eq ${title}) {
			$uid = $events->{$event}{$UID};

			&printer(2, "\t\t[" . $events->{$event}{$MOD} . "]\n");
			&printer(2, "\t\t\t[${uid}](" . &URL_LINK("Events", ${uid}) . ")\n");
		};
	};

	if (!${uid}) {
		&printer(2, "\tDID NOT FIND ANY MATCHES!\n");
		return(0);
	};

	if (!${import}) {
		&printer(2, "\tExporting: ${uid}\n");
	} else {
		&printer(2, "\tImporting: ${uid}\n");
	};

	my $url_get = &URL_FETCH("Events");
	$url_get =~ s/getRecords/getRecordById/g;
	$url_get =~ s/json/xml/g;

	$mech->get(${url_get}
		. "?scope=${URL_SCOPE}"
		. "&authtoken=${APITOKEN}"
		. "&id=${uid}"
	) && $API_REQUEST_COUNT++;

	if ($mech->content() =~ m/[<]error[>]/) {
		&printer(2, "\nGET[" . $mech->content() . "]\n");
		&printer(2, "\n");
		die();
	};

	$input = $mech->content();
	$input =~ s|^.*<FL val="Description"><!\[CDATA\[||gms;
	$input =~ s|\]\]>.*$||gms;
	$input .= "\n";

	if (${output} ne ${input}) {
		if (!${import}) {
			open(FILE, ">", ${file}) || die();
			print FILE ${input};
			close(FILE) || die();
		} else {
			my $url_post = &URL_FETCH("Events");
			$url_post =~ s/getRecords/updateRecords/g;
			$url_post =~ s/json/xml/g;

			my $post_data = "";
			$post_data .= '<Events>';
			$post_data .= '<row no="1">';
			$post_data .= '<FL val="' . ${UID} . '">' . ${uid} . '</FL>';
			$post_data .= '<FL val="' . ${SUB} . '"><![CDATA[' . ${title} . ']]></FL>';
			$post_data .= '<FL val="' . ${DSC} . '"><![CDATA[' . ${output} . ']]></FL>';
			$post_data .= '</row>';
			$post_data .= '</Events>';

			$mech->post(${url_post}, {
				"scope"		=> ${URL_SCOPE},
				"authtoken"	=> ${APITOKEN},
				"newFormat"	=> 1,
				"id"		=> ${uid},
				"xmlData"	=> ${post_data},
			}) && $API_REQUEST_COUNT++;

			if ($mech->content() =~ m/[<]error[>]/) {
				&printer(2, "\nPOST[" . $mech->content() . "]\n");
				&printer(2, "\n");
				die();
			};
		};

		&printer(2, "\tCompleted!\n");
	} else {
		&printer(2, "\tSkipped!\n");
	};

	return(0);
};

########################################

sub find_notes_entries {
	my $notes	= {};

	&printer(2, "\n");
	&printer(2, "\tNotes Search");

	my $url_get = &URL_FETCH("Notes");
	$url_get =~ s/getRecords/getRelatedRecords/g;
	$url_get =~ s/json/xml/g;

	foreach my $lead (sort(keys(%{$leads}))) {
		&printer(2, ".");

		$mech->get(${url_get}
			. "?scope=${URL_SCOPE}"
			. "&authtoken=${APITOKEN}"
			. "&id=${lead}"
			. "&parentModule=Leads"
		) && $API_REQUEST_COUNT++;

		if ($mech->content() =~ m/[<]error[>]/) {
			&printer(2, "\nGET[" . $mech->content() . "]\n");
			&printer(2, "\n");
			die();
		};

		my $result = $mech->content();

		if (${result} !~ m|<nodata>|) {
			while (${result} =~ m|<row no="[0-9]+">(.+?)</row>|gms) {
				my $note = ${1};
				my $created = ${note};
				my $content = ${note};
				$created =~ s|^.*<FL val="Created Time"><!\[CDATA\[||gms;
				$created =~ s|\]\]>.*$||gms;
				$content =~ s|^.*<FL val="Note Content"><!\[CDATA\[||gms;
				$content =~ s|\]\]>.*$||gms;

				$notes->{$lead}{$created} = ${content};
			};
		};
	};

	&printer(2, "\n");

	if (%{$notes}) {
		&printer(2, "\n");
		&printer(2, "\tNotes Entries:\n");
		$fail_exit = "1";

		foreach my $lead (sort(keys(%{$notes}))) {
			my $subject = ($leads->{$lead}{$FNM} || "") . ${NAME_DIV} . ($leads->{$lead}{$LNM} || "");
			$subject = "[${subject}](" . &URL_LINK("Leads", $leads->{$lead}{$LID}) . ")";
			&printer(2, "\t\t${subject}\n");

			foreach my $note (sort(keys(%{$notes->{$lead}}))) {
				my $content = $notes->{$lead}{$note};

				$content =~ s|\n|\n\t\t\t|gms;
				$content =~ s|\t\t\t$||gms;

				&printer(2, "\t\t\tNOTES ENTRY (${note}):\n");
				&printer(2, "\t\t\t${content}\n");
			};
		};
	};

	return(0);
};

########################################

sub check_recycle_bin {
	my $recycled	= {};
	my $index_no	= "1";
	my $index_to	= "1";
	my $output;
	my $found;

	foreach my $type (@{$TYPES}) {
		while (1) {

			$index_to = (${index_no} + (${MAX_RECORDS} -1));

			my $url_get = &URL_FETCH(${type});
			$url_get =~ s/getRecords/getDeletedRecordIds/g;
			$url_get =~ s/json/xml/g;

			$mech->get(${url_get}
				. "?scope=${URL_SCOPE}"
				. "&authtoken=${APITOKEN}"
				. "&fromIndex=${index_no}"
				. "&toIndex=${index_to}"
			) && $API_REQUEST_COUNT++;

			if ($mech->content() =~ m/[<]error[>]/) {
				&printer(2, "\nGET[" . $mech->content() . "]\n");
				&printer(2, "\n");
				die();
			};

			$output = $mech->content();
			$output =~ s|^.*<DeletedIDs>||gms;
			$output =~ s|</DeletedIDs>.*$||gms;

			$found = "0";
			foreach my $item (split(",", ${output})) {
				$recycled->{$type}{$item}++;
				$found++;
			};
			if (${found} < ${MAX_RECORDS}) {
				last();
			};

			$index_no += ${MAX_RECORDS};
		};
	};

	if (%{$recycled}) {
		&printer(2, "\n");
		&printer(2, "\tRecycle Bin:\n");
		$fail_exit = "1";

		foreach my $type (@{$TYPES}) {
			&printer(2, "\t\t${type}: " . scalar(keys(%{ $recycled->{$type} })) . "\n");
		};
	};

	return(0);
};

########################################

sub unlink_null_events {
	my $null_linked	= [];

	foreach my $event (sort(keys(%{$events}))) {
		if (
			($events->{$event}{$RID}) &&
			($leads->{ $events->{$event}{$RID} }{$CMP} eq ${NULL_CNAME})
		) {
			push(@{$null_linked}, ${event});
		};
	};

	if (@{$null_linked}) {
		&printer(2, "\n");
		&printer(2, "\tNull Linked:\n");
		$fail_exit = "1";

		foreach my $event (@{$null_linked}) {
			&printer(2, "\t\t[" . $events->{$event}{$SUB} . "](" . &URL_LINK("Events", $events->{$event}{$UID}) . ")\n");

			my $url_post = &URL_FETCH("Events");
			$url_post =~ s/getRecords/updateRecords/g;
			$url_post =~ s/json/xml/g;

			my $post_data = "";
			$post_data .= '<Events>';
			$post_data .= '<row no="1">';
			$post_data .= '<FL val="' . ${UID} . '">' . ${event} . '</FL>';
			$post_data .= '<FL val="' . ${SUB} . '"><![CDATA[' . $events->{$event}{$SUB} . ']]></FL>';
			$post_data .= '<FL val="SEMODULE"></FL>';
			$post_data .= '<FL val="SEID"></FL>';
			$post_data .= '</row>';
			$post_data .= '</Events>';

			$mech->post(${url_post}, {
				"scope"		=> ${URL_SCOPE},
				"authtoken"	=> ${APITOKEN},
				"newFormat"	=> 1,
				"id"		=> ${event},
				"xmlData"	=> ${post_data},
			}) && $API_REQUEST_COUNT++;

			if ($mech->content() =~ m/[<]error[>]/) {
				&printer(2, "\nPOST[" . $mech->content() . "]\n");
				&printer(2, "\n");
				die();
			};
		};
	};

	return(0);
};

########################################

sub print_leads {
	my $report		= shift() || "";

	my $stderr		= "1";
	my $err_date_list	= {};
	my $err_dates		= {};
	my $entries		= "0";

	if (${report} eq "CSV") {
		print CSV "\"Date\",\"Day\",\"New\",\"Changed\",\"Closed\",\"Cancelled\",\"${SRC}\",\"${STS}\",\"${FNM}${NAME_DIV}${LNM}\",\n";
		print CSV "\"${CSV_DATE}\",\"Mon\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\n";
	}
	elsif (${report} eq "Aging") {
		$stderr = "0";

		&printer("\n");
		&printer("${LEVEL_2} QC Aging\n");
		&printer("\n");

		&printer("| ${MOD} | Modified Overdue | Last Note | QC Overdue | ${REL} | ${FNM}${NAME_DIV}${LNM}\n");
		&printer("|:---|:---|:---|:---|:---|:---|\n");
	}
	else {
		if (
			(${report} ne "Cancelled?") &&
			(${report} ne "Broken") &&
			(${report} ne "Graveyard")
		) {
			$report = "All";
		};

		if (${report} eq "Cancelled?") {
			$stderr = "0";

			&printer(${stderr}, "\n");
			&printer(${stderr}, "${LEVEL_2} ${report}\n");
			&printer(${stderr}, "\n");
		} else {
			&printer(${stderr}, "\n");
			&printer(${stderr}, "${LEVEL_2} ${report} Leads\n");
			&printer(${stderr}, "\n");
		};

		if (${report} eq "Broken") {
			&printer(${stderr}, "| ${SRC} | ${STS} | ${REL} | ${FNM}${NAME_DIV}${LNM} | ${DSC}\n");
			&printer(${stderr}, "|:---|:---|:---|:---|:---|\n");
		} else {
			&printer(${stderr}, "| ${SRC} | ${STS} | ${REL} | ${FNM}${NAME_DIV}${LNM}\n");
			&printer(${stderr}, "|:---|:---|:---|:---|\n");
		};
	};

	foreach my $lead (sort({
		((${report} eq "Aging") &&
			(($leads->{$a}{$MOD} || "") cmp ($leads->{$b}{$MOD} || ""))
		) ||
		((${report} eq "Cancelled?") &&
			(($cancel_bd_list->{$a} || $cancel_gd_list->{$a} || "") cmp ($cancel_bd_list->{$b} || $cancel_gd_list->{$b} || ""))
		) ||
		(($leads->{$a}{$FNM} || "") cmp ($leads->{$b}{$FNM} || "")) ||
		(($leads->{$a}{$LNM} || "") cmp ($leads->{$b}{$LNM} || "")) ||
		(($leads->{$a}{$MOD} || "") cmp ($leads->{$b}{$MOD} || ""))
	} keys(%{$leads}))) {
		my $source = ($leads->{$lead}{$SRC} || "");
		my $status = ($leads->{$lead}{$STS} || "");

		my $related = ($related_list->{ $leads->{$lead}{$LID} } || "");
		my $subject = ($leads->{$lead}{$FNM} || "") . ${NAME_DIV} . ($leads->{$lead}{$LNM} || "");
		my $details = ($leads->{$lead}{$DSC} || "");
		$subject = "[${subject}](" . &URL_LINK("Leads", $leads->{$lead}{$LID}) . ")";
		$details = "[${details}]"; $details =~ s/\n+/\]\[/g;
		$details =~ s/${NON_ASCII_M}/${NON_ASCII}/g;
		my $modified = $leads->{$lead}{$MOD} || "";

		if (${report} eq "CSV") {
			if ($leads->{$lead}{$DSC}) {
				my $matches = [];
				my $new = "1";
				my $mod = "";
				my $mod_date = ${modified};
				$mod_date =~ m/^([0-9]{4})[-]([0-9]{2})[-]([0-9]{2})[ ]([0-9]{2})[:]([0-9]{2})[:]([0-9]{2})$/;
				$mod_date = &timegm(${6},${5},${4},${3},(${2}-1),${1});
				$mod_date = &strftime("%Y-%m-%d", localtime(${mod_date}));
				my $subject_csv = ${subject};
				$subject_csv =~ s/\"/\'/g;
				while ($leads->{$lead}{$DSC} =~ m/^([0-9][0-9-]+[,]?[ ]?[A-Za-z]*)$/gm) {
					if (${1}) {
						my $match = ${1};
						if (${match} =~ m/^([0-9]{4}[-][0-9]{2}[-][0-9]{2})(.*)$/gm) {
							push(@{$matches}, ${match});
						} else {
							push(@{ $err_dates->{"NULL"}{$match} }, ${subject});
						};
					};
				};
				my $num = "0";
				foreach my $match (@{$matches}) {
					${match} =~ m/^([0-9]{4}[-][0-9]{2}[-][0-9]{2})(.*)$/gm;
					my $date = ${1};
					my $day = ${2};
					$day =~ s/^[,][ ]//g;

					if (
						(${date} eq ${mod_date}) ||
						(${num} eq $#{$matches})
					) {
						$mod = "1";
					};
					print CSV "\"${date}\",\"${day}\",\"${new}\",\"${mod}\",\"\",\"\",\"${source}\",\"${status}\",\"${subject_csv}\",\n";
					$new = "";

					if (!${day}) {
						$day = "NULL";
					};
					push(@{ $err_date_list->{$date}{$day} }, ${subject});

					${num}++;
				};
				if (!${mod}) {
					print CSV "\"${mod_date}\",\"[MOD]\",\"\",\"1\",\"\",\"\",\"${source}\",\"${status}\",\"${subject_csv}\",\n";
				};
			};
		}
		elsif (${report} eq "Aging") {
			if (
				($leads->{$lead}{$STS}) && (
					($leads->{$lead}{$STS} eq "Closed Won") ||
					($leads->{$lead}{$STS} eq "Demo")
				) &&
				(!$cancel_bd_list->{$lead})
			) {
				my $mod_days = $modified;
				my $last_log = "";
				my $overdue = "-1";
				my $logs = {};
				while ($leads->{$lead}{$DSC} =~ m/^([0-9]{4}[-][0-9]{2}[-][0-9]{2})(.*)$/gm) {
					if (${1}) {
						my $date = ${1};
						$logs->{$date}++;
					};
				};
				foreach my $date (sort(keys(%{$logs}))) {
					$last_log = ${date};
					$overdue = ${date};
				};
				if ($mod_days =~ m/^([0-9]{4})[-]([0-9]{2})[-]([0-9]{2}).*$/) {
					$mod_days = &timelocal(0,0,0,${3},(${2}-1),${1});
					$mod_days = (time() - (${AGING_DAYS} * ${SEC_IN_DAY})) - ${mod_days};
					$mod_days = int(${mod_days} / ${SEC_IN_DAY});
				};
				if ($overdue =~ m/^([0-9]{4})[-]([0-9]{2})[-]([0-9]{2}).*$/) {
					$overdue = &timelocal(0,0,0,${3},(${2}-1),${1});
					$overdue = (time() - (${AGING_DAYS} * ${SEC_IN_DAY})) - ${overdue};
					$overdue = int(${overdue} / ${SEC_IN_DAY});
				};
				if (
					(${mod_days}	>= 0) ||
					(${overdue}	>= 0) ||
					(!${last_log})
				) {
					${mod_days}	.= " days";
					${overdue}	.= " days";

					&printer(${stderr}, "| ${modified} | ${mod_days} | ${last_log} | ${overdue} | ${related} | ${subject}\n");

					$entries++;
				};
			};
		}
		elsif (${report} eq "Cancelled?") {
			if ($cancel_bd_list->{$lead} || $cancel_gd_list->{$lead}) {
				my $cancel = ($cancel_bd_list->{$lead} || $cancel_gd_list->{$lead});
				$cancel =~ s/^[^[]*[[]([^]:]*)[]:].*$/$1/g;
				my $subject_csv = ${subject};
				$subject_csv =~ s/\"/\'/g;

				print CSV "\"${cancel}\",\"[CNL]\",\"\",\"\",\"\",\"1\",\"${source}\",\"${status}\",\"${subject_csv}\",\n";

				$subject = ($cancel_bd_list->{$lead} || $cancel_gd_list->{$lead}) . " " . ${subject};

				&printer(${stderr}, "| ${source} | ${status} | ${related} | ${subject}\n");

				$entries++;
			};
		}
		elsif (${report} eq "Broken") {
			if ((
				(!$leads->{$lead}{$SRC}) ||
				(!$leads->{$lead}{$STS})
			) || (
				($leads->{$lead}{$STS} eq "Demo") && (
					($leads->{$lead}{$SRC} ne "Referral") ||
					($leads->{$lead}{$DSC} !~ m/${DSC_IMPORT}/)
				)
			) || (
				(!$related_list->{ $leads->{$lead}{$LID} }) && (
					($leads->{$lead}{$STS} ne "Demo") &&
					($leads->{$lead}{$STS} ne "Initial Call") &&
					($leads->{$lead}{$STS} ne "Not Interested")
				)
			) || (
				($related_list->{ $leads->{$lead}{$LID} }) && ((
						($related_list->{ $leads->{$lead}{$LID} } > 2)
					) || (
						($related_list->{ $leads->{$lead}{$LID} } > 1) &&
						($leads->{$lead}{$STS} ne "Closed Won")
					) || (
						($related_list->{ $leads->{$lead}{$LID} } > 0) &&
						($leads->{$lead}{$CMP} eq ${NULL_CNAME})
				))
			) || (
				(!$leads->{$lead}{$FNM}) ||
				($leads->{$lead}{$FNM} eq $leads->{$lead}{$LNM}) ||
				($leads->{$lead}{$FNM} eq $leads->{$lead}{$CMP}) ||
				($leads->{$lead}{$LNM} ne $leads->{$lead}{$CMP})
			) || (
				($leads->{$lead}{$DSC}) &&
				($leads->{$lead}{$DSC} =~ m/(${DSC_FLAG}|${NON_ASCII_M})/)
			)) {
				$details = ($leads->{$lead}{$DSC} || "");
				my $matching = "";
				while ($details =~ m/^(.*(${DSC_FLAG}|${NON_ASCII_M}).*)$/gm) {
					$matching .= "[${1}]";
				};
				$matching =~ s/${NON_ASCII_M}/${NON_ASCII}/g;
				$details = ${matching};

				if (!${details}) {
					$details = ".";
				};
				&printer(${stderr}, "| ${source} | ${status} | ${related} | ${subject} | ${details}\n");

				$entries++;
			};
		}
		elsif (${report} eq "Graveyard") {
			if (($leads->{$lead}{$STS}) && ($leads->{$lead}{$STS} eq "Not Interested")) {
				&printer(${stderr}, "| ${source} | ${status} | ${related} | ${subject}\n");

				$entries++;
			};
		}
		else {
				&printer(${stderr}, "| ${source} | ${status} | ${related} | ${subject}\n");

				$entries++;
		};
	};

	if (${report} eq "CSV") {
		if ((%{$err_date_list}) || (%{$err_dates})) {
			foreach my $date (sort(keys(%{$err_date_list}))) {
				my $date_list = [];
				@{$date_list} = sort(keys(%{ $err_date_list->{$date} }));

				my $is_day = ${date};
				$is_day =~ m/^([0-9]{4})[-]([0-9]{2})[-]([0-9]{2})$/;
				$is_day = &timelocal(0,0,0,${3},(${2}-1),${1});
				$is_day = &strftime("%a", localtime(${is_day}));

				if (
					(defined($err_date_list->{$date}{"NULL"})) ||
					(!defined($err_date_list->{$date}{$is_day})) ||
					($#{$date_list} >= 1)
				) {
					my $entry = "${date}, ${is_day}";
					foreach my $day (sort(@{$date_list})) {
						foreach my $item (sort(@{ $err_date_list->{$date}{$day} })) {
							push(@{ $err_dates->{$entry}{$day} }, ${item});
						};
					};
				};
			};

			if (%{$err_dates}) {
				&printer(2, "\n");
				&printer(2, "\tIncorrect Dates:\n");
				$fail_exit = "1";

				foreach my $date (sort(keys(%{$err_dates}))) {
					&printer(2, "\t\t[${date}]\n");
					foreach my $day (sort(keys(%{$err_dates->{$date}}))) {
						&printer(2, "\t\t\t[${day}]\n");
						foreach my $item (sort(@{$err_dates->{$date}{$day}})) {
							&printer(2, "\t\t\t\t${item}\n");
						};
					};
				};
			};
		};
	} else {
		if (!${entries}) {
			&printer(${stderr}, "|\n");
		};
		&printer(${stderr}, "\nEntries: ${entries}\n");
	};

	return(0);
};

########################################

sub print_tasks {
	my $report	= shift() || "";

	my $entries	= "0";

	&printer(1, "\n");
	if (!${report}) {
		&printer(1, "${LEVEL_2} Open Tasks\n");
	} else {
		&printer(1, "${LEVEL_2} ${report} Tasks\n");
	};
	&printer(1, "\n");

	&printer(1, "| ${DUE} | ${CLT} | ${TST} | ${PRI} | ${REL} | ${SUB}\n");
	&printer(1, "|:---|:---|:---|:---|:---|:---|\n");

	foreach my $task (sort({
		(($tasks->{$a}{$DUE} || "") cmp ($tasks->{$b}{$DUE} || "")) ||
		(($tasks->{$a}{$CLT} || "") cmp ($tasks->{$b}{$CLT} || "")) ||
		(($tasks->{$a}{$REL} || "") cmp ($tasks->{$b}{$REL} || "")) ||
		(($tasks->{$a}{$SUB} || "") cmp ($tasks->{$b}{$SUB} || ""))
	} keys(%{$tasks}))) {
		my $related = ($tasks->{$task}{$REL} || "");
		my $subject = ($tasks->{$task}{$SUB} || "");
		if ($tasks->{$task}{$REL} && $tasks->{$task}{$RID})	{ $related = "[${related}](" . &URL_LINK("Leads",	$tasks->{$task}{$RID}) . ")"; };
		if ($tasks->{$task}{$SUB} && $tasks->{$task}{$TID})	{ $subject = "[${subject}](" . &URL_LINK("Tasks",	$tasks->{$task}{$TID}) . ")"; };

		if ((
			(!${report}) &&
				($tasks->{$task}{$TST} eq "Not Started")
		) || (
			(${report} eq "Broken") && (
				(!$tasks->{$task}{$DUE}) ||
				((!$tasks->{$task}{$TST}) || (
					($tasks->{$task}{$TST} ne "Not Started") &&
					($tasks->{$task}{$TST} ne "Deferred") &&
					($tasks->{$task}{$TST} ne "Completed")
				)) ||
				($tasks->{$task}{$PRI} ne "High") ||
				((!$tasks->{$task}{$REL}) || (
					($tasks->{$task}{$TST} eq "Not Started") &&
					(!$related_list->{ $tasks->{$task}{$RID} })
				)) ||
				($tasks->{$task}{$SUB} =~ m/${DSC_FLAG}/) ||
				($tasks->{$task}{$DSC})
			)
		) || (
			(${report}) &&
				($tasks->{$task}{$TST} eq ${report})
		)) {
			&printer(1, "| " . ($tasks->{$task}{$DUE} || ""));
			&printer(1, " | " . ($tasks->{$task}{$CLT} ? sprintf("${S_DATE_ONLY}", $tasks->{$task}{$CLT}) : ""));
			&printer(1, " | " . ($tasks->{$task}{$TST} || ""));
			&printer(1, " | " . ($tasks->{$task}{$PRI} || ""));
			&printer(1, " | ${related}");
			&printer(1, " | ${subject}");
			&printer(1, "\n");

			$entries++;
		};
	};

	if (!${entries}) {
		&printer(1, "|\n");
	};
	&printer(1, "\nEntries: ${entries}\n");

	return(0);
};

########################################

sub print_events {
	my $find	= shift() || ".";
	my $keep	= shift() || [ $UID, $MOD, $BEG, $END, $SRC, $STS, $REL, $SUB, $DSC, ];
	my $list	= shift() || [];

	my $stderr	= "1";
	my $case	= "";
	my $label	= "";
	my $report	= "";
	my $fields	= {};
	my $count_list	= [];
	my $entries	= "0";
	my $output	= "";

	if (${find} =~ /${SPLIT_CHAR}/) {
		# from "foreach my $search (@{ARGV})" and in "&update_file()" it is made pretty
		($stderr, $case, $find, $label) = split(/${SPLIT_CHAR}/, ${find});
	};
	if (!${label}) {
		if ($find eq ".") {
			$label = "All Events";
		} else {
			$label = ${find};
		};
	};

	if (${find} eq "Closed!") {
		$report = ${find};
		$label = ${find};
		$find = ".";
		$stderr = "";
	}
	elsif (
		(${find} eq "Broken") ||
		(${find} eq "Active")
	) {
		$report = ${find};
		$label = ${find} . " Events";
		$find = ".";
	};

	&printer(${stderr}, "\n");
	&printer(${stderr}, "${LEVEL_2} ${label}\n");
	&printer(${stderr}, "\n");

	foreach my $field (@{$keep}) {
		$fields->{$field} = ${field};
	};
	&print_event_fields(${stderr}, "1", ${keep}, ${fields});

	foreach my $event (sort({
		(($events->{$a}{$BEG} || "") cmp ($events->{$b}{$BEG} || "")) ||
		(($events->{$a}{$END} || "") cmp ($events->{$b}{$END} || "")) ||
		(($events->{$a}{$SUB} || "") cmp ($events->{$b}{$SUB} || ""))
	} keys(%{$events}))) {
		if ((
			(!${report}) && (
				(($events->{$event}{$BEG} ge ${START_DATE})	&& ($events->{$event}{$SUB} =~ m/${find}/i)) &&
				((!${case})					|| ($events->{$event}{$SUB} =~ m/${find}/))
			)
		) || (
			(${report} eq "Closed!") && (
				(($events->{$event}{$RID}) && ($closed_list->{ $events->{$event}{$RID} })) &&
				($events->{$event}{$SUB} =~ m/${CLOSED_MARK}/)
			)
		) || (
			(${report} eq "Broken") && ((
				(($events->{$event}{$SUB}) && ($events->{$event}{$SUB} =~ m/${DSC_FLAG}/)) ||
				(($events->{$event}{$LOC}) && ($events->{$event}{$LOC} =~ m/${DSC_FLAG}/)) ||
				(($events->{$event}{$DSC}) && ($events->{$event}{$DSC} =~ m/${DSC_FLAG}/))
			) || (
				($events->{$event}{$DSC}) && (
					($events->{$event}{$SUB} ne ${LEGEND_NAME}) &&
					($events->{$event}{$SUB} ne ${TODAY_NAME})
				)
			))
		) || (
			(${report} eq "Active") && (
				($events->{$event}{$RID}) &&
				($events->{$event}{$SUB} !~ m/${CLOSED_MARK}/)
			)
		)) {
			if (${report} eq "Closed!") {
				my $source = ($leads->{ $events->{$event}{$RID} }{$SRC} || "");
				my $status = ($leads->{ $events->{$event}{$RID} }{$STS} || "");
				my $subject = ($leads->{ $events->{$event}{$RID} }{$FNM} || "") . ${NAME_DIV} . ($leads->{ $events->{$event}{$RID} }{$LNM} || "");
				$subject = "[${subject}](" . &URL_LINK("Leads", $leads->{ $events->{$event}{$RID} }{$LID}) . ")";
				my $subject_csv = ${subject};
				$subject_csv =~ s/\"/\'/g;

				print CSV "\"$events->{$event}{$BEG}\",\"[CLS]\",\"\",\"\",\"1\",\"\",\"${source}\",\"${status}\",\"${subject_csv}\",\n";
			};

			&print_event_fields(${stderr}, "", ${keep}, $events->{$event});

			push(@{$count_list}, ${event});
			$entries++;
		};
	};

	if (!${entries}) {
		$output .= "|\n";
	};
	$output .= "\nEntries: ${entries}\n";
	&printer(${stderr}, ${output});

	&count_events(${stderr}, ${count_list}, ${list});

	if (!${report}) {
		&today_tmp(${find}, ${count_list}, ${list});
	};

	return(0);
};

########################################

sub print_event_fields {
	my $stderr	= shift() || "";
	my $header	= shift() || "";
	my $keep	= shift() || [];
	my $vals	= shift() || {};

	my $rsource	= ($vals->{$SRC} || "");
	my $rstatus	= ($vals->{$STS} || "");
	my $related	= ($vals->{$REL} || "");
	my $subject	= ($vals->{$SUB} || "");
	my $details	= ($vals->{$DSC} || "");
	my $output	= "";

	if (!${header}) {
		if ($vals->{$REL} && $vals->{$RID}	&& $leads->{ $vals->{$RID} }{$SRC}) { $rsource = $leads->{ $vals->{$RID} }{$SRC}; };
		if ($vals->{$REL} && $vals->{$RID}	&& $leads->{ $vals->{$RID} }{$STS}) { $rstatus = $leads->{ $vals->{$RID} }{$STS}; };
		if ($vals->{$REL} && $vals->{$RID})	{ $related = "[${related}](" . &URL_LINK("Leads",	$vals->{$RID}) . ")"; };
		if ($vals->{$SUB} && $vals->{$UID})	{ $subject = "[${subject}](" . &URL_LINK("Events",	$vals->{$UID}) . ")"; };
		if ($vals->{$LOC})			{ $subject = "[${subject}][$vals->{$LOC}]"; };
		if ($vals->{$DSC})			{ $subject = "**${subject}**"; };
		if ($vals->{$DSC})			{ $details = "[${details}]"; $details =~ s/\n+/\]\[/g; };
		$details =~ s/${NON_ASCII_M}/${NON_ASCII}/g;
	};

	foreach my $val (@{$keep}) {
		my $value = "";
		if ($vals->{$val}) {
			$value = $vals->{$val};
		};

		if (${val} eq $UID) { $value = sprintf("${S_UID}",	${value}); };
		if (${val} eq $MOD) { $value = sprintf("${S_DATE}",	${value}); };
		if (${val} eq $BEG) { $value = sprintf("${S_DATE}",	${value}); };
		if (${val} eq $END) { $value = sprintf("${S_DATE}",	${value}); };
		if (${val} eq $SRC) { $value = ${rsource}; };
		if (${val} eq $STS) { $value = ${rstatus}; };
		if (${val} eq $REL) { $value = ${related}; };
		if (${val} eq $SUB) { $value = ${subject}; };
		if (${val} eq $DSC) { $value = ${details}; };

		if ((${val} eq $REL) && (defined($vals->{$RID}))) {
			if ($cancel_bd_list->{ $vals->{$RID} } || $cancel_gd_list->{ $vals->{$RID} }) {
				$value = ($cancel_bd_list->{ $vals->{$RID} } || $cancel_gd_list->{ $vals->{$RID} }) . " " . ${value};
			};
		};

		$output .= "| ${value} ";
	};

	$output =~ s/\s*$//g;
	$output .= "\n";

	if (${header}) {
		foreach my $val (@{$keep}) {
			$output .= "|:---";
		};
		$output .= "|\n";
	};

	&printer(${stderr}, ${output});

	return(0);
};

########################################

sub count_events {
	my $stderr	= shift() || "";
	my $count_list	= shift() || [];
	my $list	= shift() || [];

	my $count	= {};
	my $entries	= "0";

	if (@{$count_list} && @{$list}) {
		&printer(${stderr}, "\n");
		&printer(${stderr}, "| Match | Count |\n");
		&printer(${stderr}, "|:---|:---|\n");

		foreach my $item (@{$list}) {
			$count->{$item} = "0";
		};
		$count->{"DUPL"} = [];
		$count->{"NULL"} = [];

		foreach my $event (@{$count_list}) {
			my $matched	= "0";

			foreach my $item (@{$list}) {
				if ($events->{$event}{$SUB} =~ m/${item}/) {
					$count->{$item}++;
					${matched}++;
					${entries}++;
				};
			};

			if (!${matched}) {
				push(@{ $count->{"NULL"} }, ${event});
			}
			elsif (${matched} > 1) {
				push(@{ $count->{"DUPL"} }, ${event});
			};
		};

		foreach my $item (@{$list}) {
			&printer(${stderr}, "| ${item} | $count->{$item}\n");
		};

		foreach my $error ("DUPL", "NULL") {
			if (@{ $count->{$error} }) {
				&printer(${stderr}, "| *("
					. (($error eq "DUPL") ? "Duplicate"	: "")
					. (($error eq "NULL") ? "Unmatched"	: "")
					. ")* | *(" . scalar(@{ $count->{$error} }) . ")*"
				);

				foreach my $event (@{ $count->{$error} }) {
					&printer(${stderr}, " [[" . $events->{$event}{$SUB} . "](" . &URL_LINK("Events", $events->{$event}{$UID}) . ")]");
				};
				&printer(${stderr}, "\n");
			};
		};

		&printer(${stderr}, "\nEntries: ${entries}");
		if (@{ $count->{"DUPL"} } || @{ $count->{"NULL"} }) {
			&printer(${stderr}, " (" . ((${entries} - scalar(@{ $count->{"DUPL"} })) + scalar(@{ $count->{"NULL"} })) . ")");
		};
		&printer(${stderr}, "\n");
	};

	return(0);
};

########################################

sub today_tmp {
	my $title	= shift() || "";
	my $count_list	= shift() || [];
	my $list	= shift() || [];

	my $stderr	= "3";
	my $current	= [];
	my $output	= "";
	my $line;

	if (-f ${TODAY_IMP}) {
		open(FILE, "<", ${TODAY_IMP}) || die();
		@{$current} = split("\n", do { local $/; <FILE> });
		close(FILE) || die();
	}
	elsif (-f ${TODAY_EXP}) {
		open(FILE, "<", ${TODAY_EXP}) || die();
		@{$current} = split("\n", do { local $/; <FILE> });
		close(FILE) || die();
	};

	if (@{$count_list} && @{$list}) {
		foreach my $item (@{$list}) {
			$output .= "${LEVEL_2} [${title}|${item}]\n\n";

			foreach my $event (@{$count_list}) {
				if ($events->{$event}{$SUB} =~ m/${item}/) {
					$line = &today_tmp_format(${event}, "[${title}|${item}]");

					my $match = "0";
					foreach my $test (@{$current}) {
						if (${test} =~ m/\Q${line}\E/) {
							$match = "1";
						};
					};
					if (!${match}) {
						$output .= "${line}\n";
					};
				};
			};

			$output .= "\n";
		};
	};

	&printer(${stderr}, ${output});

	return(0);
};

########################################

sub today_tmp_format {
	my $event	= shift() || "";
	my $mark	= shift() || "[${DSC_FLAG}]";
	my $line;

	my $comp = $events->{$event}{$SUB};
	my $name = "";

	if ($events->{$event}{$RID}) {
		$comp =~ s/^${MARK_REGEX}//;
		if (${1})					{ $mark = "[${1}]"; };
		if ($leads->{ $events->{$event}{$RID} }{$CMP})	{ $comp = $leads->{ $events->{$event}{$RID} }{$CMP}; };
		if ($leads->{ $events->{$event}{$RID} }{$FNM})	{ $name = $leads->{ $events->{$event}{$RID} }{$FNM}; };
	};

	$line = "  * ${mark} ${comp} {${name}}";
	$line .= " {";
	$line .= (($events->{$event}{$BEG}) ? $events->{$event}{$BEG} : "");
	foreach my $task (sort(keys(%{$tasks}))) {
		if (
			(($tasks->{$task}{$RID}) && ($events->{$event}{$RID})) &&
			($tasks->{$task}{$RID} eq $events->{$event}{$RID}) &&
			($tasks->{$task}{$TST} eq "Not Started")
		) {
			$line .= "|" . $tasks->{$task}{$SUB};
			$orphaned_tasks->{$task}++;
		};
	};
	$line .= "}";
	$line .= (($events->{$event}{$LOC}) ? (" -- " . $events->{$event}{$LOC}) : "");

	return(${line});
};

########################################

sub today_tmp_reverse {
	my $stderr	= "3";
	my $current	= [];
	my $duplicates	= {};

	if (-f ${TODAY_IMP}) {
		open(FILE, "<", ${TODAY_IMP}) || die();
		@{$current} = split("\n", do { local $/; <FILE> });
		close(FILE) || die();
	}
	elsif (-f ${TODAY_EXP}) {
		open(FILE, "<", ${TODAY_EXP}) || die();
		@{$current} = split("\n", do { local $/; <FILE> });
		close(FILE) || die();
	};

	my $lines = [];
	foreach my $event (sort(keys(%{$events}))) {
		push(@{$lines}, &today_tmp_format($events->{$event}{$UID}));
	};

	&printer(${stderr}, "${LEVEL_2} [${DSC_FLAG}]\n\n");

	foreach my $task (sort(keys(%{$tasks}))) {
		if ((
			(!$tasks->{$task}{$RID}) ||
			(!$orphaned_tasks->{$task})
		) && (
			($tasks->{$task}{$TST} eq "Not Started")
		)) {
			my $related = ($tasks->{$task}{$REL} || "");
			my $subject = ($tasks->{$task}{$SUB} || "");
			if ($tasks->{$task}{$REL} && $tasks->{$task}{$RID})	{ $related = "[${related}](" . &URL_LINK("Leads",	$tasks->{$task}{$RID}) . ")"; };
			if ($tasks->{$task}{$SUB} && $tasks->{$task}{$TID})	{ $subject = "[${subject}](" . &URL_LINK("Tasks",	$tasks->{$task}{$TID}) . ")"; };
			&printer(${stderr}, "\t${subject} -> ${related}\n");
		};
	};

	&printer(${stderr}, "\n${LEVEL_2} [${DSC_FLAG}]\n\n");

	foreach my $test (@{$current}) {
		my $match = "0";
		foreach my $line (@{$lines}) {
			if (${test} =~ m/\Q${line}\E/) {
				$match = "1";
			};
		};
		if (!${match}) {
			&printer(${stderr}, "\t${test}\n");
		};
		$duplicates->{$test}++;
	};

	&printer(${stderr}, "\n${LEVEL_2} [${DSC_FLAG}]\n\n");

	foreach my $item (sort(keys(%{$duplicates}))) {
		if (
			(${item}) &&
			($duplicates->{$item} > 1)
		) {
			&printer(${stderr}, "\t${item}\n");
		};
	};

	return(0);
};

########################################

sub print_notes {
	my $notes	= {};
	my $entries	= "0";
	my $updated;

	open(CSV, "<", ${NOTES_FILE}) || die();
	$updated = (stat(${NOTES_FILE}))[9];
	$updated = localtime(${updated});
	while (<CSV>) {
		my $num = "1";
		while (${_} =~ m/zcrm[_]([0-9]+)/gm) {
			if (${num} == 3) {
				$notes->{$1}++;
				${entries}++;
			};
			${num}++;
		};
	};
	close(CSV) || die();

	&printer(1, "\n");
	&printer(1, "${LEVEL_2} Exported Notes\n");
	&printer(1, "\n");
	&printer(1, "[[Recycle Bin]](https://crm.zoho.com/crm/ShowSetup.do?tab=data&subTab=recyclebin)");
	&printer(1, "${NAME_DIV}");
	&printer(1, "[[Export Link]](https://crm.zoho.com/crm/ShowSetup.do?tab=data&subTab=export): ${updated}");
	&printer(1, "\n\n");
	&printer(1, "| Notes Count | ${FNM}${NAME_DIV}${LNM} |\n");
	&printer(1, "|:---|:---|\n");

	foreach my $note (sort(keys(%{$notes}))) {
		my $subject = ($leads->{$note}{$FNM} || "") . ${NAME_DIV} . ($leads->{$note}{$LNM} || "");
		$subject = "[${subject}](" . &URL_LINK("Leads", $leads->{$note}{$LID}) . ")";
		&printer(1, "| " . $notes->{$note} . " | " . ${subject} . "\n");
	};

	if (!${entries}) {
		&printer(1, "|\n");
	};
	&printer(1, "\nEntries: " . ${entries} . " (" . scalar(keys(%{$notes})) . " Leads)\n");

	return(0);
};

################################################################################

foreach my $type (@{$TYPES}) {
	my $var = lc(${type});

	%{ $z->{$var} } = &fetch_entries(${type});

	open(JSON, ">", ${JSON_BASE} . "." . ${var} . ".json") || die();
	print JSON $json->encode($z->{$var});
	close(JSON) || die();
};

if (
	(%{$leads}) ||
	(%{$events})
) {
	open(CSV, ">", ${CSV_FILE}) || die();
	close(CSV) || die();
};

########################################

foreach my $lead (keys(%{$leads})) {
	if ($leads->{$lead}{$STS} && $leads->{$lead}{$STS} eq "Closed Won") {
		$closed_list->{$lead}++;
	};
	foreach my $lead (keys(%{$leads})) {
		while ($leads->{$lead}{$DSC} =~ m/(${DSC_EXP_BD}|${DSC_EXP_GD})[:]?(.*)$/gm) {
			if (${1} eq ${DSC_EXP_BD}) { $cancel_bd_list->{$lead} = "**[${2}][${DSC_EXP_BD_I}]**"; };
			if (${1} eq ${DSC_EXP_GD}) { $cancel_gd_list->{$lead} = "**[${2}][${DSC_EXP_GD_I}]**"; };
		};
	};
};

foreach my $event (keys(%{$events})) {
	if ($events->{$event}{$RID}) {
		$related_list->{ $events->{$event}{$RID} }++;
	};

	if ($events->{$event}{$SUB} eq ${NULL_ENAME}) {
		push(@{$empty_events}, "[" . $events->{$event}{$BEG} . "](" . &URL_LINK("Events", $events->{$event}{$UID}) . ")");
	};
};

########################################

if (%{$events}) {
	&update_legend();
	&update_today();
};

if (
	(%{$leads}) &&
	(${FIND_NOTES})
) {
	&find_notes_entries();
};

if (%{$leads}) {
	open(CSV, ">>", ${CSV_FILE}) || die();
	&print_leads("CSV");
	close(CSV) || die();
};

if (@{$empty_events}) {
	&printer(2, "\n");
	&printer(2, "\tEmpty Events:\n");
	$fail_exit = "1";

	foreach my $entry (sort(@{$empty_events})) {
		&printer(2, "\t\t${entry}\n");
	};
};

&check_recycle_bin();

if (%{$events}) {
	&unlink_null_events();
};

########################################

&printer(2, "\n");
&printer(2, "\tTotal Requests: ${API_REQUEST_COUNT}\n");

if (${fail_exit}) {
	exit(${fail_exit});
};

################################################################################

&printer(1, "\n");
&printer("${LEVEL_1} Core Reports\n");

if (%{$events}) {
	open(CSV, ">>", ${CSV_FILE}) || die();
	&print_events("Closed!", [ $BEG, $SRC, $STS, $REL, $SUB, ]);
	&printer("\n");
	&printer("Closed: " . scalar(keys(%{$closed_list})) . "\n");
	close(CSV) || die();
};

########################################

if (%{$leads}) {
	open(CSV, ">>", ${CSV_FILE}) || die();
	&print_leads("Cancelled?");
	close(CSV) || die();
	&print_leads("Broken");
#>>>	&print_leads();
	&print_leads("Graveyard");
	&print_leads("Aging");
};

########################################

if (%{$tasks}) {
	&print_tasks("Broken");
	&print_tasks();
	&print_tasks("Deferred");
	&print_tasks("Completed");
};

########################################

if (%{$events}) {
	&print_events("Broken", [ $BEG, $STS, $REL, $SUB, ]);
#>>>	&print_events();

	my $counts = [];
	my $opt_num = "0";
	foreach my $opt (@{ARGV}) {
		if (${opt} =~ m/[#][ ]Active[ ]${A_BEG_CHAR}(.*)${A_END_CHAR}$/) {
			@{$counts} = split(/${SPLIT_CHAR}/, ${1});
			splice(@{ARGV}, ${opt_num}, 1);
		};
		${opt_num}++;
	};
	&print_events("Active", [ $BEG, $STS, $REL, $SUB, ], ${counts});
};

########################################

if (-f ${NOTES_FILE}) {
	&print_notes();
};

########################################

if (%{$events}) {
	# input for "&print_events()" and in "&update_file()" it is made pretty
	foreach my $search (@{ARGV}) {
		if (${search} =~ m/^[${HEAD_MARKER}][ ]/) {
			$search =~ s/^[${HEAD_MARKER}][ ]//g;
			&printer("\n");
			&printer("${LEVEL_1} ${search}\n");
		} else {
			my $counts = [];
			if (${search} =~ m/[ ]${A_BEG_CHAR}(.*)${A_END_CHAR}$/) {
				$search =~ s/[ ]${A_BEG_CHAR}(.*)${A_END_CHAR}$//;
				@{$counts} = split(/${SPLIT_CHAR}/, ${1});
			};
			&print_events(${search}, [ $BEG, $STS, $REL, $SUB, ], ${counts});
		};
	};

	&today_tmp_reverse();
};

################################################################################

close(ALL_FILE) || die();
close(OUT_FILE) || die();
close(TODAY_TMP) || die();

exit(0);

################################################################################
# end of file
################################################################################
