#!/usr/bin/env perl
use strict;
use warnings;
################################################################################

use Carp qw(confess);
#>>>$SIG{__WARN__}	= \&confess;
#>>>$SIG{__DIE__}	= \&confess;

use Data::Dumper;
sub DUMPER {
	my $DUMP = shift;
	local $Data::Dumper::Purity = 1;
	print STDERR "<-- DUMPER " . ("-" x 30) . ">\n";
	print STDERR Dumper(${DUMP});
	print STDERR "<-- DUMPER " . ("-" x 30) . ">\n";
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

use JSON::PP;
my $json = JSON::PP->new();
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

my $LEGEND_NAME	= "Marker: Legend";
my $LEGEND_FILE	= ".zoho.reports";
my $JSON_BASE	= "zoho-export";
my $CSV_FILE	= "zoho-data.csv";

my $START_DATE	= "2016-10-24"; if ($ARGV[0] && $ARGV[0] =~ m/^[0-9]{4}[-][0-9]{2}[-][0-9]{2}$/) { $START_DATE = shift(); };
my $SORT_COLUMN	= "Modified DateTime";
my $SORT_ORDER	= "asc";
my $MAX_RECORDS	= "200";

my $NULL_CNAME	= "0 NULL";
my $NAME_DIV	= " ";
my $DSC_FLAG	= "WORK[:]";
my $NON_ASCII	= "#";

########################################

my $LEVEL_1	= "#" x 3;
my $LEVEL_2	= "#" x 4;

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
do(".zoho-auth") || die();

our $APITOKEN;
do(".zoho-token") || die();

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

	open(OUTPUT, ">", ".zoho-token") || die();
	print OUTPUT "our \$APITOKEN = '${APITOKEN}';\n";
	close(OUTPUT) || die();
};

########################################

print STDERR "${LEVEL_1} Processing Log\n";
#>>>print STDERR "\n";
#>>>print STDERR "\tTOKEN: ${APITOKEN}\n";

################################################################################

my $z = {
	"leads"		=> {},
	"tasks"		=> {},
	"events"	=> {},
};
my $leads	= $z->{"leads"};
my $tasks	= $z->{"tasks"};
my $events	= $z->{"events"};

my $closed_list = {};
my $related_list = {};

########################################

sub fetch_entries {
	my $type	= shift() || "Events";
	my $last_mod	= ${START_DATE};
	my $index_no	= "1";
	my $records	= "0";
	my $fetches	= {};
	my $found;

	print STDERR "\n\tFetching ${type}...";

	while (1) {
		if ($last_mod =~ m/^[0-9]{4}[-][0-9]{2}[-][0-9]{2}$/) {
			$last_mod .= " 00:00:00";
		};
		if (!${THOROUGH}) {
			$last_mod =~ s/^([0-9]{4}[-][0-9]{2}[-][0-9]{2}).*$/${1} 00:00:00/g;
			$index_no = "1";
		};

		print STDERR "\n\tProcessing: ${last_mod} (${index_no} to " . (${index_no} + (${MAX_RECORDS} -1)) . ")... ";

		$mech->get(&URL_FETCH(${type})
			. "?scope=${URL_SCOPE}"
			. "&authtoken=${APITOKEN}"
			. (!${THOROUGH} ? "&lastModifiedTime=${last_mod}" : "")
			. "&sortColumnString=${SORT_COLUMN}"
			. "&sortOrderString=${SORT_ORDER}"
			. "&fromIndex=${index_no}"
			. "&toIndex=" . (${index_no} + (${MAX_RECORDS} -1))
		) && $API_REQUEST_COUNT++;
		my $output = decode_json($mech->content());

		if ( $output->{"response"}{"nodata"} ) {
			print STDERR "\n\tNo Data!";
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
		print STDERR "${found} records found (${records} total).";

		if (${found} < ${MAX_RECORDS}) {
			print STDERR "\n\tCompleted!";
			last();
		};

		$index_no += ${MAX_RECORDS};
	};

	print STDERR "\n";

	print STDERR "\n";
	print STDERR "\tTotal ${type}: " . scalar(keys(%{$fetches})) . "\n";
	print STDERR "\tRequests: ${API_REQUEST_COUNT}\n";

	return(%{$fetches});
};

########################################

sub parse_entry {
	my $event = shift();
	my $new = {};
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
	open(OUT, "<${LEGEND_FILE}") || die();
	my $legend = localtime() . "\n\n";
	$legend .= do { local $/; <OUT> };
	$legend =~ s/^["].+[|]([^|]+)[|]([^|]+)["]$/[${1}] ${2}/gm;
	close(OUT) || die();

	my $url_get = &URL_FETCH("Events");
	$url_get =~ s/getRecords/getRecordById/g;
	$url_get =~ s/json/xml/g;

	my $url_post = &URL_FETCH("Events");
	$url_post =~ s/getRecords/updateRecords/g;
	$url_post =~ s/json/xml/g;

	my $matches = "0";

	foreach my $event (keys(%{$events})) {
		if ($events->{$event}{$SUB} eq ${LEGEND_NAME}) {
			my $post_data = "";
			$post_data .= '<Events>';
			$post_data .= '<row no="1">';
			$post_data .= '<FL val="' . ${UID} . '">' . $events->{$event}{$UID} . '</FL>';
			$post_data .= '<FL val="Subject"><![CDATA[' . ${LEGEND_NAME} . ']]></FL>';
			$post_data .= '<FL val="Description"><![CDATA[' . ${legend} . ']]></FL>';
			$post_data .= '</row>';
			$post_data .= '</Events>';

			$mech->get(${url_get}
				. "?scope=${URL_SCOPE}"
				. "&authtoken=${APITOKEN}"
				. "&id=$events->{$event}{$UID}"
			) && $API_REQUEST_COUNT++;
#>>>			print STDERR "\tGET[" . $mech->content() . "]\n";

#>>>			print STDERR "\tPOST[" . ${post_data} . "]\n";
			$mech->post(${url_post}, {
				"scope"		=> ${URL_SCOPE},
				"authtoken"	=> ${APITOKEN},
				"newFormat"	=> 1,
				"id"		=> $events->{$event}{$UID},
				"xmlData"	=> ${post_data},
			}) && $API_REQUEST_COUNT++;
#>>>			print STDERR "\tRESULT[" . $mech->content() . "]\n";

			print STDERR "\n\t[$events->{$event}{$SUB}]: $events->{$event}{$UID}\n";

			${matches}++;
		};
	};

	print STDERR "\n";
	print STDERR "\tMatches: ${matches}\n";
	print STDERR "\tRequests: ${API_REQUEST_COUNT}\n";

	return(0);
};

########################################

sub print_leads {
	my $report = shift() || "";

	if (${report} eq "CSV") {
		print CSV "\"Date\",\"Day\",\"Closed\",\"${SRC}\",\"${STS}\",\"${FNM}${NAME_DIV}${LNM}\",\n";
		print CSV "\"2017-01-02\",\"Mon\",\"\",\"\",\"\",\"\",\n";
	} else {
		print STDERR "\n";
		print STDERR "${LEVEL_2} Broken Leads\n";
		print STDERR "\n";

		print STDERR "| ${SRC} | ${STS} | ${REL} | ${FNM}${NAME_DIV}${LNM} | ${DSC}\n";
		print STDERR "|:---|:---|:---|:---|:---|\n";
	};

	my $err_date_list = {};

	my $entries = "0";

	foreach my $lead (sort({
		(($leads->{$a}{$FNM} ? $leads->{$a}{$FNM} : "") cmp ($leads->{$b}{$FNM} ? $leads->{$b}{$FNM} : "")) ||
		(($leads->{$a}{$LNM} ? $leads->{$a}{$LNM} : "") cmp ($leads->{$b}{$LNM} ? $leads->{$b}{$LNM} : "")) ||
		(($leads->{$a}{$MOD} ? $leads->{$a}{$MOD} : "") cmp ($leads->{$b}{$MOD} ? $leads->{$b}{$MOD} : ""))
	} keys(%{$leads}))) {
		my $source = ($leads->{$lead}{$SRC} ? $leads->{$lead}{$SRC} : "");
		my $status = ($leads->{$lead}{$STS} ? $leads->{$lead}{$STS} : "");

		my $related = ($related_list->{ $leads->{$lead}{$LID} } ? $related_list->{ $leads->{$lead}{$LID} } : "");
		my $subject = ($leads->{$lead}{$FNM} ? $leads->{$lead}{$FNM} : "") . ${NAME_DIV} . ($leads->{$lead}{$LNM} ? $leads->{$lead}{$LNM} : "");
		my $details = ($leads->{$lead}{$DSC} ? $leads->{$lead}{$DSC} : "");
		$subject = "[${subject}](" . &URL_LINK("Leads", $leads->{$lead}{$LID}) . ")";
		$details = "[${details}]"; $details =~ s/\n+/\]\[/g;
		$details =~ s/[^[:ascii:]]/${NON_ASCII}/g;

		if (${report} eq "CSV") {
			if ($leads->{$lead}{$DSC}) {
				while ($leads->{$lead}{$DSC} =~ m/^([0-9]{4}[-][0-9]{2}[-][0-9]{2})(.*)$/gm) {
					if (${1}) {
						my $date = ${1};
						my $day = ${2};
						$day =~ s/^[,][ ]//g;

						$subject =~ s/\"/\'/g;

						print CSV "\"${date}\",\"${day}\",\"\",\"${source}\",\"${status}\",\"${subject}\",\n";

						if (!${day}) {
							$day = "NULL";
						};
						$err_date_list->{$date}{$day}++;
					};
				};
			};
		} else {
			if ((
				(!$leads->{$lead}{$SRC}) ||
				(!$leads->{$lead}{$STS})
			) || (
				(!$related_list->{ $leads->{$lead}{$LID} }) && (
					($leads->{$lead}{$STS} ne "Initial Call") &&
					($leads->{$lead}{$STS} ne "Not Interested")
				)
			) || (
				($related_list->{ $leads->{$lead}{$LID} }) && (
					($related_list->{ $leads->{$lead}{$LID} } > "1") ||
					($leads->{$lead}{$CMP} eq ${NULL_CNAME})
				)
			) || (
				(!$leads->{$lead}{$FNM}) ||
				($leads->{$lead}{$FNM} eq $leads->{$lead}{$LNM}) ||
				($leads->{$lead}{$FNM} eq $leads->{$lead}{$CMP}) ||
				($leads->{$lead}{$LNM} ne $leads->{$lead}{$CMP})
			) || (
				($leads->{$lead}{$DSC}) &&
				($leads->{$lead}{$DSC} =~ m/${DSC_FLAG}/)
			)) {
				print STDERR "| ${source} | ${status} | ${related} | ${subject} | ${details}\n";

				$entries++;
			};
		};
	};

	if (${report} eq "CSV") {
		if (${err_date_list}) {
			my $err_dates = [];
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
					my $entry = "${date}, ${is_day} =";
					foreach my $day (@{$date_list}) {
						$entry .= " [${day}]{$err_date_list->{$date}{$day}}";
					};
					push(@{$err_dates}, ${entry});
				};
			};

			if (@{$err_dates}) {
				print STDERR "\n";
				print STDERR "\tBroken Dates:\n";
				foreach my $entry (@{$err_dates}) {
					print STDERR "\t\t${entry}\n";
				};
			};
		};
	} else {
		if (!${entries}) {
			print STDERR "|\n";
		};
		print STDERR "\nEntries: ${entries}\n";
	};

	return(0);
};

########################################

sub print_tasks {
	my $report = shift() || "";

	print STDERR "\n";
	if (!${report}) {
		print STDERR "${LEVEL_2} Open Tasks\n";
	} else {
		print STDERR "${LEVEL_2} ${report} Tasks\n";
	};
	print STDERR "\n";

	print STDERR "| ${DUE} | ${TST} | ${PRI} | ${REL} | ${SUB}\n";
	print STDERR "|:---|:---|:---|:---|:---|\n";

	my $entries = "0";

	foreach my $task (sort({
		(($tasks->{$a}{$DUE} ? $tasks->{$a}{$DUE} : "") cmp ($tasks->{$b}{$DUE} ? $tasks->{$b}{$DUE} : "")) ||
		(($tasks->{$a}{$REL} ? $tasks->{$a}{$REL} : "") cmp ($tasks->{$b}{$REL} ? $tasks->{$b}{$REL} : "")) ||
		(($tasks->{$a}{$SUB} ? $tasks->{$a}{$SUB} : "") cmp ($tasks->{$b}{$SUB} ? $tasks->{$b}{$SUB} : ""))
	} keys(%{$tasks}))) {
		my $related = ($tasks->{$task}{$REL} ? $tasks->{$task}{$REL} : "");
		my $subject = ($tasks->{$task}{$SUB} ? $tasks->{$task}{$SUB} : "");
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
			print STDERR "| " . ($tasks->{$task}{$DUE} ? $tasks->{$task}{$DUE} : "");
			print STDERR " | " . ($tasks->{$task}{$TST} ? $tasks->{$task}{$TST} : "");
			print STDERR " | " . ($tasks->{$task}{$PRI} ? $tasks->{$task}{$PRI} : "");
			print STDERR " | ${related}";
			print STDERR " | ${subject}";
			print STDERR "\n";

			$entries++;
		};
	};

	if (!${entries}) {
		print STDERR "|\n";
	};
	print STDERR "\nEntries: ${entries}\n";

	return(0);
};

########################################

sub print_events {
	my $list = shift() || ${events};
	my $find = shift() || ".";
	my $keep = shift() || [ $UID, $MOD, $BEG, $END, $REL, $SUB, $DSC, ];

	my $stderr = "1";
	my $case = "";
	my $label = "";
	if (${find} =~ /\|/) {
		($stderr, $case, $find, $label) = split(/\|/, ${find});
	};
	if (!${label}) {
		if ($find eq ".") {
			$label = "All Events";
		} else {
			$label = ${find};
		};
	};

	my $report = "";
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

	if (${stderr}) {
		print STDERR "\n";
		print STDERR "${LEVEL_2} ${label}\n";
		print STDERR "\n";
	} else {
		print "\n";
		print "${LEVEL_2} ${label}\n";
		print "\n";
	};

	my $fields = {};
	foreach my $field (@{$keep}) {
		$fields->{$field} = ${field};
	};
	&print_event_fields(${stderr}, "1", ${keep}, ${fields});

	my $entries = "0";

	foreach my $event (sort({
		(($events->{$a}{$BEG} ? $events->{$a}{$BEG} : "") cmp ($events->{$b}{$BEG} ? $events->{$b}{$BEG} : "")) ||
		(($events->{$a}{$END} ? $events->{$a}{$END} : "") cmp ($events->{$b}{$END} ? $events->{$b}{$END} : "")) ||
		(($events->{$a}{$SUB} ? $events->{$a}{$SUB} : "") cmp ($events->{$b}{$SUB} ? $events->{$b}{$SUB} : ""))
	} keys(%{$list}))) {
		if ((
			(!${report}) &&
			(($list->{$event}{$BEG} ge ${START_DATE})	&& ($list->{$event}{$SUB} =~ m/${find}/i)) &&
			((!${case})					|| ($list->{$event}{$SUB} =~ m/${find}/))
		) || (
			(${report} eq "Closed!") &&
			(($list->{$event}{$RID}) && ($closed_list->{ $list->{$event}{$RID} }))
		) || (
			(${report} eq "Active") &&
			($list->{$event}{$RID})
		)) {
			if (${report} eq "Closed!") {
				print CSV "\"$list->{$event}{$BEG}\",\"\",\"1\",\"\",\"\",\"$list->{$event}{$REL}\",\n";
			};

			&print_event_fields("${stderr}", "", ${keep}, $list->{$event});

			$entries++;
		};
	};

	my $output;
	if (!${entries}) {
		$output .= "|\n";
	};
	$output .= "\nEntries: ${entries}\n";
	if (${stderr}) {
		print STDERR ${output};
	} else {
		print ${output};
	};

	return(0);
};

########################################

sub print_event_fields {
	my $stderr = shift() || "";
	my $header = shift() || "";
	my $keep = shift() || [];
	my $vals = shift() || {};

	my $related = ($vals->{$REL} ? $vals->{$REL} : "");
	my $subject = ($vals->{$SUB} ? $vals->{$SUB} : "");
	my $details = ($vals->{$DSC} ? $vals->{$DSC} : "");
	if (!${header}) {
		if ($vals->{$REL} && $vals->{$RID})	{ $related = "[${related}](" . &URL_LINK("Leads",	$vals->{$RID}) . ")"; };
		if ($vals->{$SUB} && $vals->{$UID})	{ $subject = "[${subject}](" . &URL_LINK("Events",	$vals->{$UID}) . ")"; };
		if ($vals->{$LOC})			{ $subject = "[${subject}][$vals->{$LOC}]"; };
		if ($vals->{$DSC})			{ $subject = "**${subject}**"; };
		if ($vals->{$DSC})			{ $details = "[${details}]"; $details =~ s/\n+/\]\[/g; };
		$details =~ s/[^[:ascii:]]/${NON_ASCII}/g;
	};

	my $output = "";

	foreach my $val (@{$keep}) {
		my $value = "";
		if ($vals->{$val}) {
			$value = $vals->{$val};
		};

		if (${val} eq $UID) { $value = sprintf("${S_UID}",	${value}); };
		if (${val} eq $MOD) { $value = sprintf("${S_DATE}",	${value}); };
		if (${val} eq $BEG) { $value = sprintf("${S_DATE}",	${value}); };
		if (${val} eq $END) { $value = sprintf("${S_DATE}",	${value}); };
		if (${val} eq $REL) { $value = ${related}; };
		if (${val} eq $SUB) { $value = ${subject}; };
		if (${val} eq $DSC) { $value = ${details}; };

		$output .= "| ${value} ";
	};

	$output =~ s/[[:space:]]*$//g;
	$output .= "\n";

	if (${header}) {
		foreach my $val (@{$keep}) {
			$output .= "|:---";
		};
		$output .= "|\n";
	};

	if (${stderr}) {
		print STDERR ${output};
	} else {
		print ${output};
	};

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

	open(JSON, ">${JSON_BASE}.${var}.json") || die();
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
};

########################################

if (%{$events}) {
	&update_legend();
};

########################################

open(CSV, ">${CSV_FILE}") || die();

if (%{$leads}) {
	&print_leads("CSV");
};

print "\n";
print "${LEVEL_1} Core Reports\n";

if (%{$events}) {
	&print_events(${events}, "Closed!", [ $BEG, $REL, $SUB, ]);
};

close(CSV) || die();

########################################

if (%{$leads}) {
	&print_leads();
};

########################################

if (%{$tasks}) {
	&print_tasks("Broken");
};

if (%{$tasks}) {
	&print_tasks();
};

if (%{$tasks}) {
	&print_tasks("Deferred");
};

########################################

#>>>if (%{$events}) {
#>>>	&print_events();
#>>>};

if (%{$events}) {
	&print_events(${events}, "Active", [ $BEG, $REL, $SUB, ]);
};

print "\n";
print "${LEVEL_1} Custom Reports\n";

if (%{$events}) {
	foreach my $search (@{ARGV}) {
		&print_events(${events}, ${search}, [ $BEG, $REL, $SUB, ]);
	};
};

########################################

exit(0);

################################################################################
# end of file
################################################################################
