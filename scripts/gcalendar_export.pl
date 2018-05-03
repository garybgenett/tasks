#!/usr/bin/env perl
use strict;
use warnings;
################################################################################
# 5.18.2	https://www.perl.org
# 1.730.0	http://search.cpan.org/~ether/WWW-Mechanize/lib/WWW/Mechanize.pm
# 1.370.0	http://search.cpan.org/~phred/Archive-Zip/lib/Archive/Zip.pm
# 0.230.0	http://search.cpan.org/~dagolden/File-Temp/lib/File/Temp.pm
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

use Archive::Zip qw(:ERROR_CODES);
use File::Temp qw(tempfile);
use File::Copy;

########################################

$| = "1";

################################################################################

my $C_FILE		= "calendar";
my $D_FILE		= "drive";
my $EXTENSION		= ".ics";

my $REQ_PER_SEC		= "1";
my $REQ_PER_SEC_SLEEP	= "15";

########################################

our $USERNAME;
our $PASSWORD;
do("./.auth") || die();

################################################################################

my $REQUEST_COUNT	= "0";

sub EXIT {
	my $status = shift || "0";
	print "\nRequests: ${REQUEST_COUNT}\n";
	exit(${status});
};

########################################

sub authenticate {
	$mech->get("https://www.google.com/calendar");

#>>>	$mech->get("https://accounts.google.com/ServiceLogin");
	$mech->form_id("gaia_loginform");
	$mech->field("Email",	${USERNAME});
	$mech->field("Passwd",	${PASSWORD});
	$mech->submit();

#>>>	$mech->get("https://accounts.google.com/AccountLoginInfo");
	$mech->form_id("gaia_loginform");
	$mech->field("Email",	${USERNAME});
	$mech->field("Passwd",	${PASSWORD});
	$mech->submit();

	return(0);
};

################################################################################

sub get_calendar {
	my $name	= shift;
	my $id		= shift;

	$name = "${C_FILE}-${name}${EXTENSION}";
	print "${name} :: ${id}\n";

	my($TEMPFILE, $tempfile) = tempfile(".${C_FILE}.XXXX", "UNLINK" => "1");
	my $zip = Archive::Zip->new();

	if ((${REQUEST_COUNT} % ${REQ_PER_SEC}) == 0) {
		sleep(${REQ_PER_SEC_SLEEP});
	};
	$mech->get("https://www.google.com/calendar/exporticalzip?cexp=${id}") && $REQUEST_COUNT++;
	$mech->save_content($tempfile);
#>>>	&DUMPER(${mech});

	if ($zip->read($tempfile) != AZ_OK) { die(); };
#>>>	&DUMPER($zip);
	my @files = $zip->memberNames();
	my $files = \@files;
#>>>	&DUMPER($files);
	foreach my $file (@{$files}) {
		print "\t${tempfile} -> ${file} -> ${name}\n";
		if ($zip->extractMember(${file}) != AZ_OK) { die(); };
		move(${file}, ${name});
	};

	close(${TEMPFILE}) || die();

	return(0);
};

########################################

sub get_drive {
	my $name	= shift;
	my $id		= shift;

	$name = "${D_FILE}-${name}";
	print "${name} :: ${id}\n";

	my($TEMPFILE, $tempfile) = tempfile(".${D_FILE}.XXXX", "UNLINK" => "1");

	if ((${REQUEST_COUNT} % ${REQ_PER_SEC}) == 0) {
		sleep(${REQ_PER_SEC_SLEEP});
	};
	$mech->get("https://docs.google.com/uc?export=download&id=${id}") && $REQUEST_COUNT++;
	$mech->save_content($tempfile);
#>>>	&DUMPER(${mech});

	print "\t${tempfile} -> ${name}\n";
	move($tempfile, ${name});

	close(${TEMPFILE}) || die();

	return(0);
};

################################################################################

if (@{ARGV}) {
	&authenticate();

	foreach my $calendar (@{ARGV}) {
		my($type, $data) = split(/[|]/, ${calendar});
		my($name, $id) = split(/[:]/, ${data});
		if (${type} eq "c") {
			&get_calendar(${name}, ${id});
		}
		elsif (${type} eq "d") {
			&get_drive(${name}, ${id});
		}
		else {
			die("INVALID TYPE [${calendar}]!");
		};
	};
};

########################################

&EXIT(0);

################################################################################
# end of file
################################################################################
