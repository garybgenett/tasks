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
	print "<-- DUMPER " . ("-" x 30) . ">\n";
	print Dumper(${DUMP});
	print "<-- DUMPER " . ("-" x 30) . ">\n";
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

########################################

$| = "1";

################################################################################

my $URL_AUTH	= "https://accounts.zoho.com/apiauthtoken/nb/create";
sub URL_FETCH	{ "https://crm.zoho.com/crm/private/json/" . shift() . "/getRecords"; };
sub URL_LINK	{ "https://crm.zoho.com/crm/EntityInfo.do?module=" . shift() . "&id=" . shift(); };

my $URL_SCOPE	= "crmapi";
my $API_SCOPE	= "ZohoCRM/${URL_SCOPE}";

########################################

my $APP_NAME	= "Event_Download";

my $START_DATE	= "2016-10-24"; if ($ARGV[0] && $ARGV[0] =~ m/^[0-9]{4}[-][0-9]{2}[-][0-9]{2}$/) { $START_DATE = shift(); };
my $SORT_COLUMN	= "Modified DateTime";
my $SORT_ORDER	= "asc";
my $MAX_RECORDS	= "200";

my $S_UID	= "%-19.19s";
my $S_DATE	= "%-19.19s";

my $LID		= "LEADID";
my $CMP		= "Company";
my $LNM		= "Last Name";
my $FNM		= "First Name";
my $SRC		= "Lead Source";
my $STS		= "Lead Status";

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

print STDERR "### Log\n";
print STDERR "\n";
print STDERR "\tTOKEN: ${APITOKEN}\n";

################################################################################

my $fetches = {};
my $leads = {};
my $events = {};

########################################

sub fetch_entries {
	my $type	= shift() || "Events";
	my $last_mod	= ${START_DATE};
	my $index_no	= "1";
	my $records	= "0";
	my $found;

	while (1) {
		if ($last_mod =~ m/^[0-9]{4}[-][0-9]{2}[-][0-9]{2}$/) {
			$last_mod .= " 00:00:00";
		};

		print STDERR "\n\tProcessing: ${last_mod} (${index_no} to " . (${index_no} + (${MAX_RECORDS} -1)) . ")... ";

		$mech->get(&URL_FETCH(${type})
			. "?scope=${URL_SCOPE}"
			. "&authtoken=${APITOKEN}"
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

		if (ref( $output->{"response"}{"result"}{${type}}{"row"} ) eq "ARRAY") {
			$found = $#{		$output->{"response"}{"result"}{${type}}{"row"} };
			foreach my $event (@{	$output->{"response"}{"result"}{${type}}{"row"} }) {
				${last_mod} = &parse_entry( $event->{"FL"} );
			};
		} else {
			$found = $#{			$output->{"response"}{"result"}{${type}}{"row"}{"FL"} };
			${last_mod} = &parse_entry(	$output->{"response"}{"result"}{${type}}{"row"}{"FL"} );
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
	print STDERR "\tTotal: " . scalar(keys(%{$fetches})) . "\n";
	print STDERR "\tRequests: ${API_REQUEST_COUNT}\n";

	return(0);
};

########################################

sub parse_entry {
	my $event = shift();
	my $new = {};
	my $uid;
	my $last;

	foreach my $value (@{$event}) {
		if ($value->{"val"} eq ${UID} || $value->{"val"} eq ${LID}) {
			$uid = $value->{"content"};
		};
		if ($value->{"val"} eq ${MOD}) {
			$last = $value->{"content"};
		};

		$new->{ $value->{"val"} } = $value->{"content"};
	};

	$fetches->{$uid} = ${new};

	return($last);
}

########################################

sub print_leads {
	print STDERR "\n";
	print STDERR "### Broken Leads\n";
	print STDERR "\n";

	print STDERR "| ${SRC} | ${STS} | [ ${LNM} ][ ${FNM}]\n";
	print STDERR "|:---|:---|:---|\n";

	my $entries = "0";

	foreach my $lead (sort({
		(($leads->{$a}{$LNM} ? $leads->{$a}{$LNM} : "") cmp ($leads->{$b}{$LNM} ? $leads->{$b}{$LNM} : "")) ||
		(($leads->{$a}{$FNM} ? $leads->{$a}{$FNM} : "") cmp ($leads->{$b}{$FNM} ? $leads->{$b}{$FNM} : "")) ||
		(($leads->{$a}{$MOD} ? $leads->{$a}{$MOD} : "") cmp ($leads->{$b}{$MOD} ? $leads->{$b}{$MOD} : ""))
	} keys(%{$leads}))) {
		my $src = ($leads->{$lead}{${SRC}} ? $leads->{$lead}{${SRC}} : "");
		my $sts = ($leads->{$lead}{${STS}} ? $leads->{$lead}{${STS}} : "");

		my $name = "";
		$name .= "[ " . ($leads->{$lead}{${LNM}} ? $leads->{$lead}{${LNM}} : "") . " ]";
		$name .= "[ " . ($leads->{$lead}{${FNM}} ? $leads->{$lead}{${FNM}} : "") . " ]";
		$name = "[${name}](" . &URL_LINK("Leads", $leads->{$lead}{${LID}}) . ")";
		$name =~ s/\"/\'/g;

		if (
			(!$leads->{$lead}{$SRC}) ||
			(!$leads->{$lead}{$STS})
		) {
			print STDERR "| ${src} | ${sts} | ${name}\n";

			$entries++;
		};
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

	if (${stderr}) {
		print STDERR "\n";
		print STDERR "### ${label}\n";
		print STDERR "\n";
	} else {
		print "\n";
		print "### ${label}\n";
		print "\n";
	};

	my $fields = {};
	foreach my $field (@{$keep}) {
		$fields->{$field} = ${field};
	};
	&print_fields(${stderr}, "1", ${keep}, ${fields});

	my $entries = "0";

	foreach my $event (sort({
		$list->{$a}{$BEG} cmp $list->{$b}{$BEG} ||
		$list->{$a}{$END} cmp $list->{$b}{$END} ||
		$list->{$a}{$SUB} cmp $list->{$b}{$SUB}
	} keys(%{$list}))) {
		if (
			($list->{$event}{$BEG} ge ${START_DATE}) &&
			($list->{$event}{$SUB} =~ m/${find}/i) &&
			(
				(!${case}) ||
				((${case}) && ($list->{$event}{$SUB} =~ m/${find}/))
			)
		) {
			&print_fields("${stderr}", "", ${keep}, $list->{$event});

			$entries++;
		};
	};

	my $output = "\nEntries: ${entries}\n";
	if (${stderr}) {
		print STDERR ${output};
	} else {
		print ${output};
	};

	return(0);
};

########################################

sub print_fields {
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
		if ($vals->{$LOC})			{ $subject = "[ ${subject} ][ $vals->{$LOC} ]"; };
		if ($vals->{$DSC})			{ $subject = "**${subject}**"; };
		if ($vals->{$DSC})			{ $details = "[ ${details} ]"; $details =~ s/\n+/\]\[/g; };
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

&fetch_entries("Leads");
$leads = \%{ ${fetches} };
$fetches = {};

&fetch_entries("Events");
$events = \%{ ${fetches} };
$fetches = {};

########################################

if (%{$leads}) {
	&print_leads();
};

########################################

if (%{$events}) {
	&print_events();
};

if (%{$events}) {
	foreach my $search (@{ARGV}) {
		&print_events(${events}, ${search}, [ ${BEG}, ${REL}, ${SUB}, ]);
	};
};

########################################

exit(0);

################################################################################
# end of file
################################################################################
