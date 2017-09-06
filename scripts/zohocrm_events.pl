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
my $URL_FETCH	= "https://crm.zoho.com/crm/private/json/Events/getRecords";

my $URL_SCOPE	= "crmapi";
my $API_SCOPE	= "ZohoCRM/${URL_SCOPE}";

########################################

my $APP_NAME	= "Event_Download";

my $START_DATE	= "2016-10-24"; if ($ARGV[0] && $ARGV[0] =~ m/^[0-9]{4}[-][0-9]{2}[-][0-9]{2}$/) { $START_DATE = shift(); };
my $SORT_COLUMN	= "Start DateTime";
my $SORT_ORDER	= "asc";
my $MAX_RECORDS	= "200";

my $S_UID	= "%-36.36s";
my $S_DATE	= "%-19.19s";

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

my $events = {};

########################################

my $last_beg	= ${START_DATE};
my $index_no	= "1";
my $records	= "0";
my $found;

while (1) {
	if ($last_beg =~ m/^[0-9]{4}[-][0-9]{2}[-][0-9]{2}$/) {
		$last_beg .= " 00:00:00";
	};

	print STDERR "\n\tProcessing: ${last_beg} (${index_no} to " . (${index_no} + (${MAX_RECORDS} -1)) . ")... ";

	$mech->get(${URL_FETCH}
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

	if (ref( $output->{"response"}{"result"}{"Events"}{"row"} ) eq "ARRAY") {
		$found = $#{		$output->{"response"}{"result"}{"Events"}{"row"} };
		foreach my $event (@{	$output->{"response"}{"result"}{"Events"}{"row"} }) {
			${last_beg} = &parse_event( $event->{"FL"} );
		};
	} else {
		$found = $#{			$output->{"response"}{"result"}{"Events"}{"row"}{"FL"} };
		${last_beg} = &parse_event(	$output->{"response"}{"result"}{"Events"}{"row"}{"FL"} );
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

########################################

print STDERR "\n";
print STDERR "\tTotal Events: " . scalar(keys(%{$events})) . "\n";
print STDERR "\tAPI Requests: ${API_REQUEST_COUNT}\n";

################################################################################

sub parse_event {
	my $event = shift();
	my $new = {};
	my $uid;
	my $last;

	foreach my $value (@{$event}) {
		if ($value->{"val"} eq ${UID}) {
			$uid = $value->{"content"};
		};
		if ($value->{"val"} eq ${BEG}) {
			$last = $value->{"content"};
		};

		$new->{ $value->{"val"} } = $value->{"content"};
	};

	$events->{$uid} = ${new};

	return($last);
}

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
			($list->{$event}{$SUB} =~ m/${find}/i)
		) {
			if (
				(!${case}) ||
				((${case}) && ($list->{$event}{$SUB} =~ m/${find}/))
			) {
				&print_fields("${stderr}", "", ${keep}, $list->{$event});

				$entries++;
			};
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

	my $subject = ($vals->{$SUB} ? $vals->{$SUB} : "");
	my $details = ($vals->{$DSC} ? $vals->{$DSC} : "");
	if (!${header}) {
		if ($vals->{$LOC}) { $subject = "[ ${subject} ][ $vals->{$LOC} ]"; };
		if ($vals->{$DSC}) { $subject = "**${subject}**"; };
		if ($vals->{$DSC}) { $details = "[ ${details} ]"; $details =~ s/\n+/\]\[/g; };
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

if (%{$events}) {
	&print_events();
};

########################################

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
