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

use JSON::XS;
my $json = JSON::XS->new();

use Archive::Zip qw(:ERROR_CODES);
use File::Temp qw(tempfile);
use File::Copy;

########################################

$| = "1";

################################################################################

my $C_FILE		= "calendar";
my $D_FILE		= "drive";
my $EXTENSION		= ".ics";

my $URL_WEB		= "https://calendar.google.com";
my $URL_OAUTH_AUTH	= "https://accounts.google.com/o/oauth2/auth";
my $URL_OAUTH_TOKEN	= "https://accounts.google.com/o/oauth2/token";
my $URL_SCOPE		= "https://www.googleapis.com/auth/calendar";
my $URL_API		= "https://www.googleapis.com/calendar/v3";

#>>>my $REQ_PER_SEC		= "1";
#>>>my $REQ_PER_SEC_SLEEP	= "15";
my $REQ_PER_SEC		= "3";
my $REQ_PER_SEC_SLEEP	= "2";

########################################

our $USERNAME;
our $PASSWORD;
our $CLIENTID;
our $CLSECRET;
our $REDIRECT;
do("./.auth-calendar") || die();

our $CODE;
our $REFRESH;
our $ACCESS;
do("./.token-calendar") || die();

################################################################################

my $REQUEST_COUNT	= "0";

sub EXIT {
	my $status = shift || "0";
	print "\nRequests: ${REQUEST_COUNT}\n";
	exit(${status});
};

########################################

sub auth_login {
	my $mech_auth	= shift;

	$mech_auth->get(${URL_WEB});

#>>>	$mech_auth->get("https://accounts.google.com/ServiceLogin");
	$mech_auth->form_id("gaia_loginform");
	$mech_auth->field("Email",	${USERNAME});
	$mech_auth->field("Passwd",	${PASSWORD});
	$mech_auth->submit();

#>>>	$mech_auth->get("https://accounts.google.com/AccountLoginInfo");
	$mech_auth->form_id("gaia_loginform");
	$mech_auth->field("Email",	${USERNAME});
	$mech_auth->field("Passwd",	${PASSWORD});
	$mech_auth->submit();

	return(${mech_auth});
};

########################################

sub refresh_tokens {
	if (!${CODE} || !${REFRESH}) {
		$mech = &auth_login(${mech});

		$mech->get(${URL_OAUTH_AUTH}
			. "?client_id=${CLIENTID}"
			. "&redirect_uri=${REDIRECT}"
			. "&scope=${URL_SCOPE}"
			. "&response_type=code"
		);
		$mech->submit_form(
			"form_id"	=> "connect-approve",
			"fields"	=> {"submit_access" => "true"},
		);
		$CODE = $mech->content();
		$CODE =~ s|^.*<input id="code" type="text" readonly="readonly" value="||s;
		$CODE =~ s|".*$||s;

		$mech->post(${URL_OAUTH_TOKEN}, {
			"code"			=> ${CODE},
			"client_id"		=> ${CLIENTID},
			"client_secret"		=> ${CLSECRET},
			"redirect_uri"		=> ${REDIRECT},
			"grant_type"		=> "authorization_code",
		});
		$REFRESH = decode_json($mech->content());
		$REFRESH = $REFRESH->{"refresh_token"};

		open(OUTPUT, ">", ".token") || die();
		print OUTPUT "our \$CODE    = '${CODE}';\n";
		print OUTPUT "our \$REFRESH = '${REFRESH}';\n";
		close(OUTPUT) || die();
	};

	$mech->post(${URL_OAUTH_TOKEN}, {
		"refresh_token"		=> ${REFRESH},
		"client_id"		=> ${CLIENTID},
		"client_secret"		=> ${CLSECRET},
		"grant_type"		=> "refresh_token",
	});
	$ACCESS = decode_json($mech->content());
	$ACCESS = $ACCESS->{"access_token"};

	print "CODE:    ${CODE}\n";
	print "REFRESH: ${REFRESH}\n";
	print "ACCESS:  ${ACCESS}\n";
	print "\n";

	$mech->add_header("Authorization" => "Bearer ${ACCESS}");

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
#>>>	$mech->get("https://calendar.google.com/calendar/exporticalzip?cexp=${id}") && $REQUEST_COUNT++;
	$mech->get("https://apidata.googleusercontent.com/caldav/v2/${id}/events") && $REQUEST_COUNT++;
#>>>
	$mech->save_content($tempfile, binmode => ":raw:utf8");
#>>>	&DUMPER(${mech});

#>>>	if ($zip->read($tempfile) != AZ_OK) { die(); };
#>>>#>>>	&DUMPER($zip);
#>>>	my @files = $zip->memberNames();
#>>>	my $files = \@files;
#>>>#>>>	&DUMPER($files);
#>>>	foreach my $file (@{$files}) {
#>>>		print "\t${tempfile} -> ${file} -> ${name}\n";
#>>>		if ($zip->extractMember(${file}) != AZ_OK) { die(); };
#>>>		move(${file}, ${name});
#>>>	};
	move($tempfile, ${name});
#>>>

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
	&refresh_tokens();

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
