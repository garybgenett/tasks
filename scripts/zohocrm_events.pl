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

my $START_DATE	= "2016-10-24"; if ($ARGV[0] =~ m/^[0-9]{4}[-][0-9]{2}[-][0-9]{2}$/) { $START_DATE = shift(); };
my $SORT_COLUMN	= "Modified";
my $SORT_ORDER	= "asc";
my $MAX_RECORDS	= "200";

my $S_UID	= "%-37.37";
my $S_DATE	= "%-20.20";

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

my $this_mod = ${START_DATE};
my $last_uid = "0";
my $next_uid = "1";

while (${last_uid} ne ${next_uid}) {
	$last_uid = ${next_uid};

	if (${this_mod} =~ m/^[0-9]{4}[-][0-9]{2}[-][0-9]{2}$/) {
		$this_mod = ${this_mod} . " 00:00:00";
	};
	print STDERR "\n\tProcessing: ${this_mod}...";

	$mech->get(${URL_FETCH}
		. "?scope=${URL_SCOPE}"
		. "&authtoken=${APITOKEN}"
		. "&sortColumnString=${SORT_COLUMN}"
		. "&sortOrderString=${SORT_ORDER}"
		. "&lastModifiedTime=${this_mod}"
		. "&fromIndex=1"
		. "&toIndex=${MAX_RECORDS}"
	) && $API_REQUEST_COUNT++;
	my $output = decode_json($mech->content());

	if ( $output->{"response"}{"nodata"} ) {
		last();
	};

	if (ref( $output->{"response"}{"result"}{"Events"}{"row"} ) eq "ARRAY") {
		foreach my $event (@{ $output->{"response"}{"result"}{"Events"}{"row"} }) {
			(${next_uid}, ${this_mod}) = &parse_event( $event->{"FL"} );
		};
	} else {
		print STDERR " completed!";
		(${next_uid}, ${this_mod}) = &parse_event( $output->{"response"}{"result"}{"Events"}{"row"}{"FL"} );
	};
};

print STDERR "\n";

########################################

print STDERR "\n";
print STDERR "\tTotal Events: " . scalar(keys(%{$events})) . "\n";
print STDERR "\tAPI Requests: ${API_REQUEST_COUNT}\n";

################################################################################

sub parse_event {
	my $event = shift();

	my $uid;
	my $mod;
	my $beg;
	my $end;
	my $sub;
	my $loc;
	my $dsc;

	foreach my $value (@{$event}) {
		if ($value->{"val"} eq "UID")			{ $uid = $value->{"content"}; };
		if ($value->{"val"} eq "Modified Time")		{ $mod = $value->{"content"}; };
		if ($value->{"val"} eq "Start DateTime")	{ $beg = $value->{"content"}; };
		if ($value->{"val"} eq "End DateTime")		{ $end = $value->{"content"}; };
		if ($value->{"val"} eq "Subject")		{ $sub = $value->{"content"}; };
		if ($value->{"val"} eq "Venue")			{ $loc = $value->{"content"}; };
		if ($value->{"val"} eq "Description")		{ $dsc = $value->{"content"}; };
	};

	$events->{ ${uid} } = {
		"uid"	=> $uid || "",
		"mod"	=> $mod || "",
		"beg"	=> $beg || "",
		"end"	=> $end || "",
		"sub"	=> $sub || "",
		"loc"	=> $loc || "",
		"dsc"	=> $dsc || "",
	};

	return(${uid}, ${mod});
}

########################################

sub print_events {
	my $list = shift() || ${events};
	my $find = shift() || ".";
	my $keep = shift() || "uid mod beg end sub loc dsc";

	my $label;
	($find, $label) = split(/\|/, ${find});

	my $stderr;
	if (${find} eq ".") {
		$stderr = "1";
		print STDERR "\n";
		print STDERR "### All Events\n";
		print STDERR "\n";
	} else {
		$stderr = "";
		print "\n";
		print "### " . (${label} ? ${label} : ${find}) . "\n";
		print "\n";
	};

	&print_fields(
		"${stderr}", "1",
		(($keep =~ m/uid/) ? "UID"	: ""),
		(($keep =~ m/mod/) ? "Modified"	: ""),
		(($keep =~ m/beg/) ? "Start"	: ""),
		(($keep =~ m/end/) ? "End"	: ""),
		(($keep =~ m/sub/) ? "Subject"	: ""),
		(($keep =~ m/loc/) ? ""		: ""),
		(($keep =~ m/dsc/) ? ""		: ""),
	);

	my $entries = "0";

	foreach my $event (sort({
		$list->{$a}{"beg"} cmp $list->{$b}{"beg"} ||
		$list->{$a}{"end"} cmp $list->{$b}{"end"} ||
		$list->{$a}{"sub"} cmp $list->{$b}{"sub"}
	} keys(%{$list}))) {
		if ($list->{$event}{"sub"} =~ m/${find}/i) {
			&print_fields(
				"${stderr}", "",
				(($keep =~ m/uid/) ? $list->{$event}{"uid"} : ""),
				(($keep =~ m/mod/) ? $list->{$event}{"mod"} : ""),
				(($keep =~ m/beg/) ? $list->{$event}{"beg"} : ""),
				(($keep =~ m/end/) ? $list->{$event}{"end"} : ""),
				(($keep =~ m/sub/) ? $list->{$event}{"sub"} : ""),
				(($keep =~ m/loc/) ? $list->{$event}{"loc"} : ""),
				(($keep =~ m/dsc/) ? $list->{$event}{"dsc"} : ""),
			);

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
	my $uid = shift();
	my $mod = shift();
	my $beg = shift();
	my $end = shift();
	my $sub = shift();
	my $loc = shift();
	my $dsc = shift();

	my $output = "";

	if ($loc) { $sub = "[ ${sub} ][ ${loc} ]"; };
	if ($dsc) { $sub = "**${sub}**"; };

	if ($uid) { $output .= "| "; $output .= sprintf("${S_UID}s",	$uid); };
	if ($mod) { $output .= "| "; $output .= sprintf("${S_DATE}s",	$mod); };
	if ($beg) { $output .= "| "; $output .= sprintf("${S_DATE}s",	$beg); };
	if ($end) { $output .= "| "; $output .= sprintf("${S_DATE}s",	$end); };
	if ($sub) { $output .= "| "; $output .= sprintf("%s",		$sub); };

	$output .= "\n";
	if ($header) {
		if ($uid) { $output .= "|:---"; };
		if ($mod) { $output .= "|:---"; };
		if ($beg) { $output .= "|:---"; };
		if ($end) { $output .= "|:---"; };
		if ($sub) { $output .= "|:---"; };
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
		&print_events(${events}, ${search}, "beg sub loc dsc");
	};
};

########################################

exit(0);

################################################################################
# end of file
################################################################################
