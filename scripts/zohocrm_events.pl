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

use POSIX qw(strftime);
use Time::Local qw(timelocal);

########################################

$| = "1";

################################################################################

my $URL_AUTH	= "https://accounts.zoho.com/apiauthtoken/nb/create";
sub URL_FETCH	{ "https://crm.zoho.com/crm/private/json/" . shift() . "/getRecords"; };
sub URL_LINK	{ "https://crm.zoho.com/crm/EntityInfo.do?module=" . shift() . "&id=" . shift(); };

my $URL_SCOPE	= "crmapi";
my $API_SCOPE	= "ZohoCRM/${URL_SCOPE}";

my $APP_NAME	= "Event_Download";
my $THOROUGH	= "1";

########################################

my $AUTH_CRED	= ".zoho-auth";
my $AUTH_TOKEN	= ".zoho-token";

my $LEGEND_NAME	= "Marker: Legend";
my $LEGEND_FILE	= ".zoho.reports";
my $LEGEND_IMP	= "1";

my $TODAY_NAME	= "Marker: Today";
my $TODAY_EXP	= "zoho.today.txt";
my $TODAY_IMP	= "zoho.today.out";

my $JSON_BASE	= "zoho-export";
my $CSV_FILE	= "zoho-data.csv";
my $ALL_FILE	= "zoho.all.md";
my $OUT_FILE	= "zoho.md";

my $START_DATE	= "2016-10-24"; if ($ARGV[0] && $ARGV[0] =~ m/^[0-9]{4}[-][0-9]{2}[-][0-9]{2}$/) { $START_DATE = shift(); };
my $SORT_COLUMN	= "Modified DateTime";
my $SORT_ORDER	= "asc";
my $MAX_RECORDS	= "200";

my $NULL_CNAME	= "0 NULL";
my $NULL_ENAME	= "New Event";
my $NAME_DIV	= " ";
my $DSC_IMPORT	= "IMPORTED";
my $DSC_EXPORT	= "CANCELLED";
my $DSC_FLAG	= "WORK";
my $NON_ASCII	= "###";
my $NON_ASCII_M	= "[^[:ascii:]]";
my $CLOSED_MARK	= "[\$]";

my $SEC_IN_DAY	= 60 * 60 * 24;
my $AGING_DAYS	= 28 * 5;

########################################

my $LEVEL_1	= "#" x 3;
my $LEVEL_2	= "#" x 4;
my $HEAD_MARKER	= "#";

my $S_UID	= "%-19.19s";
my $S_DATE	= "%-19.19s";

########################################

my $LID		= "LEADID";
my $SRC		= "Lead Source";
my $STS		= "Lead Status";
my $FNM		= "First Name";
my $LNM		= "Last Name";
my $CMP		= "Company";

my $TID		= "ACTIVITYID";
my $DUE		= "Due Date";
my $TST		= "Status";
my $PRI		= "Priority";

my $RID		= "RELATEDTOID";

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
do(${AUTH_CRED}) || die();

our $APITOKEN;
do(${AUTH_TOKEN}) || die();

################################################################################

my $API_REQUEST_COUNT = "0";

########################################

if (!${APITOKEN}) {
	$mech->get(${URL_AUTH}
		. "?SCOPE=${API_SCOPE}"
		. "&DISPLAY_NAME=${APP_NAME}"
		. "&EMAIL_ID=${USERNAME}"
		. "&PASSWORD=${PASSWORD}"
	) && $API_REQUEST_COUNT++;
	$APITOKEN = $mech->content();
	$APITOKEN =~ s/^.+AUTHTOKEN[=](.+)\n.+$/$1/gms;

	open(OUTPUT, ">", ${AUTH_TOKEN}) || die();
	print OUTPUT "our \$APITOKEN = '${APITOKEN}';\n";
	close(OUTPUT) || die();
};

########################################

open(ALL_FILE, ">", ${ALL_FILE}) || die();
open(OUT_FILE, ">", ${OUT_FILE}) || die();

sub printer {
	my $output	= shift() || "";

	my $stderr	= "0";

	if (${output} =~ m/^[012]$/) {
		$stderr = ${output};
		$output = "";
	};
	$output .= join("", @{_});

	if (${stderr} == 2) {
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
my $related_list	= {};
my $null_events		= {};

########################################

sub fetch_entries {
	my $type	= shift() || "Events";

	my $last_mod	= ${START_DATE};
	my $index_no	= "1";
	my $records	= "0";
	my $fetches	= {};
	my $found;
	my $output;

	&printer(2, "\n\tFetching ${type}...");

	while (1) {
		if ($last_mod =~ m/^[0-9]{4}[-][0-9]{2}[-][0-9]{2}$/) {
			$last_mod .= " 00:00:00";
		};
		if (!${THOROUGH}) {
			$last_mod =~ s/^([0-9]{4}[-][0-9]{2}[-][0-9]{2}).*$/${1} 00:00:00/g;
			$index_no = "1";
		};

		&printer(2, "\n\tProcessing: ${last_mod} (${index_no} to " . (${index_no} + (${MAX_RECORDS} -1)) . ")... ");

		$mech->get(&URL_FETCH(${type})
			. "?scope=${URL_SCOPE}"
			. "&authtoken=${APITOKEN}"
			. (!${THOROUGH} ? "&lastModifiedTime=${last_mod}" : "")
			. "&sortColumnString=${SORT_COLUMN}"
			. "&sortOrderString=${SORT_ORDER}"
			. "&fromIndex=${index_no}"
			. "&toIndex=" . (${index_no} + (${MAX_RECORDS} -1))
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

	&printer(2, "\n");
	&printer(2, "\tTotal ${type}: " . scalar(keys(%{$fetches})) . "\n");
	&printer(2, "\tRequests: ${API_REQUEST_COUNT}\n");

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
	my $matches	= "0";
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
		# this is to make the input used for "&print_events()" pretty: split(/\|/, ${find})
		$output =~ s/^["].+[|]([^|]+)[|]([^|]+)["]$/[${1}] ${2}/gm;
		close(FILE) || die();
	};

	foreach my $event (keys(%{$events})) {
		if ($events->{$event}{$SUB} eq ${title}) {
			$uid = $events->{$event}{$UID};
			&printer(2, "\t${uid}: $events->{$event}{$MOD}\n");

			${matches}++;
		};
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
			$post_data .= '<FL val="Subject"><![CDATA[' . ${title} . ']]></FL>';
			$post_data .= '<FL val="Description"><![CDATA[' . ${output} . ']]></FL>';
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

	&printer(2, "\n");
	&printer(2, "\tMatches: ${matches}\n");
	&printer(2, "\tRequests: ${API_REQUEST_COUNT}\n");

	return(0);
};

########################################

sub print_leads {
	my $report		= shift() || "";

	my $err_date_list	= {};
	my $err_dates		= [];
	my $entries		= "0";

	if (${report} eq "CSV") {
		print CSV "\"Date\",\"Day\",\"Closed\",\"${SRC}\",\"${STS}\",\"${FNM}${NAME_DIV}${LNM}\",\n";
		print CSV "\"2017-01-02\",\"Mon\",\"\",\"\",\"\",\"\",\n";
	}
	elsif (${report} eq "Aging") {
		&printer("\n");
		&printer("${LEVEL_2} QC Aging\n");
		&printer("\n");

		&printer("| ${MOD} | Modified Overdue | Last Note | QC Overdue | ${FNM}${NAME_DIV}${LNM}\n");
		&printer("|:---|:---|:---|:---|:---|\n");
	}
	else {
		&printer(1, "\n");
		&printer(1, "${LEVEL_2} Broken Leads\n");
		&printer(1, "\n");

		&printer(1, "| ${SRC} | ${STS} | ${REL} | ${FNM}${NAME_DIV}${LNM} | ${DSC}\n");
		&printer(1, "|:---|:---|:---|:---|:---|\n");
	};

	foreach my $lead (sort({
		(
			(${report} eq "Aging") &&
			(($leads->{$a}{$MOD} || "") cmp ($leads->{$b}{$MOD} || ""))
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

		if (${report} eq "CSV") {
			if ($leads->{$lead}{$DSC}) {
				while ($leads->{$lead}{$DSC} =~ m/^([0-9][0-9-]+[,]?[ ]?[A-Za-z]*)$/gm) {
					if (${1}) {
						my $match = ${1};
						if (${match} =~ m/^([0-9]{4}[-][0-9]{2}[-][0-9]{2})(.*)$/gm) {
							my $date = ${1};
							my $day = ${2};
							$day =~ s/^[,][ ]//g;

							$subject =~ s/\"/\'/g;

							print CSV "\"${date}\",\"${day}\",\"\",\"${source}\",\"${status}\",\"${subject}\",\n";

							if (!${day}) {
								$day = "NULL";
							};
							push(@{ $err_date_list->{$date}{$day} }, ${subject});
						} else {
							push(@{$err_dates}, "${match} = ${subject}");
						};
					};
				};
			};
		}
		elsif (${report} eq "Aging") {
			if ((
				($leads->{$lead}{$STS}) && (
					($leads->{$lead}{$STS} eq "Closed Won") ||
					($leads->{$lead}{$STS} eq "Demo")
				)
			) && (
				(($leads->{$lead}{$DSC}) && ($leads->{$lead}{$DSC} !~ m/${DSC_EXPORT}/))
			)) {
				my $modified = $leads->{$lead}{$MOD} || "";
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

					&printer("| ${modified} | ${mod_days} | " . (${last_log} || "-") . " | ${overdue} | ${subject}\n");

					$entries++;
				};
			};
		}
		else {
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
				&printer(1, "| ${source} | ${status} | ${related} | ${subject} | ${details}\n");

				$entries++;
			};
		};
	};

	if (${report} eq "CSV") {
		if ((${err_date_list}) || (${err_dates})) {
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
					my $entry = "${date}, ${is_day}\n";
					foreach my $day (sort(@{$date_list})) {
						$entry .= "\t\t\t[${day}]\n";
						foreach my $item (sort(@{ $err_date_list->{$date}{$day} })) {
							$entry .= "\t\t\t\t${item}\n";
						};
					};
					push(@{$err_dates}, ${entry});
				};
			};

			if (@{$err_dates}) {
				&printer(2, "\n");
				&printer(2, "\tBroken Dates:\n");
				foreach my $entry (@{$err_dates}) {
					&printer(2, "\t\t${entry}\n");
				};
			};
		};
	} else {
		if (!${entries}) {
			&printer(1, "|\n");
		};
		&printer(1, "\nEntries: ${entries}\n");
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

	&printer(1, "| ${DUE} | ${TST} | ${PRI} | ${REL} | ${SUB}\n");
	&printer(1, "|:---|:---|:---|:---|:---|\n");

	foreach my $task (sort({
		(($tasks->{$a}{$DUE} || "") cmp ($tasks->{$b}{$DUE} || "")) ||
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
				(!$tasks->{$task}{$REL}) ||
				($tasks->{$task}{$DSC})
			)
		) || (
			(${report} eq "Deferred") &&
			($tasks->{$task}{$TST} eq ${report})
		)) {
			&printer(1, "| " . ($tasks->{$task}{$DUE} || ""));
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

	my $stderr	= "1";
	my $case	= "";
	my $label	= "";
	my $report	= "";
	my $fields	= {};
	my $entries	= "0";
	my $output	= "";

	if (${find} =~ /\|/) {
		# in "&update_file()" this is made pretty: s/^["].+[|]([^|]+)[|]([^|]+)["]$/[${1}] ${2}/gm
		($stderr, $case, $find, $label) = split(/\|/, ${find});
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
	elsif (${find} eq "Active") {
		$report = ${find};
		$label = ${find};
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
			(!${report}) &&
			(($events->{$event}{$BEG} ge ${START_DATE})	&& ($events->{$event}{$SUB} =~ m/${find}/i)) &&
			((!${case})					|| ($events->{$event}{$SUB} =~ m/${find}/))
		) || (
			(${report} eq "Closed!") &&
			(($events->{$event}{$RID}) && ($closed_list->{ $events->{$event}{$RID} })) &&
			($events->{$event}{$SUB} =~ m/${CLOSED_MARK}/)
		) || (
			(${report} eq "Active") &&
			($events->{$event}{$RID})
		)) {
			if (${report} eq "Closed!") {
				print CSV "\"$events->{$event}{$BEG}\",\"\",\"1\",\"\",\"\",\"$events->{$event}{$REL}\",\n";
				if (
					($leads->{ $events->{$event}{$RID} }{$DSC}) &&
					($leads->{ $events->{$event}{$RID} }{$DSC} =~ m/${DSC_EXPORT}/)
				) {
					while ($leads->{ $events->{$event}{$RID} }{$DSC} =~ m/${DSC_EXPORT}[:]?(.*)$/gm) {
						$events->{$event}{$DSC_EXPORT} = ${1};
					};
				};
			};

			&print_event_fields(${stderr}, "", ${keep}, $events->{$event});

			$entries++;
		};
	};

	if (!${entries}) {
		$output .= "|\n";
	};
	$output .= "\nEntries: ${entries}\n";
	&printer(${stderr}, ${output});

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
		if (${val} eq $REL) { $value = ${related}; if (defined($vals->{$DSC_EXPORT})) { $value = "**[X][" . ($vals->{$DSC_EXPORT} || "") . "]** " . ${value}; }; };
		if (${val} eq $SUB) { $value = ${subject}; };
		if (${val} eq $DSC) { $value = ${details}; };

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

################################################################################

foreach my $type (
	"Leads",
	"Tasks",
	"Events",
) {
	my $var = lc(${type});

	%{ $z->{$var} } = &fetch_entries(${type});

	open(JSON, ">", ${JSON_BASE} . "." . ${var} . ".json") || die();
	foreach my $key (sort(keys(%{ $z->{$var} }))) {
		print JSON $json->encode($z->{$var}{$key}) . "\n";
	};
	close(JSON) || die();
};

########################################

foreach my $lead (keys(%{$leads})) {
	if ($leads->{$lead}{$STS} && $leads->{$lead}{$STS} eq "Closed Won") {
		$closed_list->{$lead}++;
	};
};

foreach my $event (keys(%{$events})) {
	if ($events->{$event}{$RID}) {
		$related_list->{ $events->{$event}{$RID} }++;
	};

	if ($events->{$event}{$SUB} eq ${NULL_ENAME}) {
		$null_events->{ $events->{$event}{$BEG} }++;
	};
};

########################################

if (%{$events}) {
	&update_legend();
	&update_today();
};

if (%{$null_events}) {
	&printer(2, "\n");
	&printer(2, "\tEmpty Events:\n");
	foreach my $entry (sort(keys(%{$null_events}))) {
		&printer(2, "\t\t${entry} = $null_events->{$entry}\n");
	};
};

########################################

open(CSV, ">", ${CSV_FILE}) || die();

if (%{$leads}) {
	&print_leads("CSV");
};

&printer(1, "\n");
&printer("${LEVEL_1} Core Reports\n");

if (%{$events}) {
	&print_events("Closed!", [ $BEG, $SRC, $STS, $REL, $SUB, ]);
	&printer("\n");
	&printer("Closed: " . scalar(keys(%{$closed_list})) . "\n");
};

close(CSV) || die();

########################################

if (%{$leads}) {
	&print_leads("Aging");
	&print_leads();
};

########################################

if (%{$tasks}) {
	&print_tasks("Broken");
	&print_tasks();
	&print_tasks("Deferred");
};

########################################

if (%{$events}) {
#>>>	&print_events();
	&print_events("Active", [ $BEG, $STS, $REL, $SUB, ]);
};

if (%{$events}) {
	foreach my $search (@{ARGV}) {
		if (${search} =~ m/^[${HEAD_MARKER}][ ]/) {
			$search =~ s/^[${HEAD_MARKER}][ ]//g;
			&printer("\n");
			&printer("${LEVEL_1} ${search}\n");
		} else {
			&print_events(${search}, [ $BEG, $STS, $REL, $SUB, ]);
		};
	};
};

########################################

close(ALL_FILE) || die();
close(OUT_FILE) || die();

exit(0);

################################################################################
# end of file
################################################################################
