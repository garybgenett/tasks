#!/usr/bin/env perl
use strict;
use warnings;
################################################################################
# https://developers.google.com/accounts/docs/OAuth2InstalledApp
# https://developers.google.com/google-apps/tasks/v1/reference
################################################################################
# 5.18.2	https://www.perl.org
# 1.730.0	http://search.cpan.org/~ether/WWW-Mechanize/lib/WWW/Mechanize.pm
# 6.50.0	http://search.cpan.org/~gaas/libwww-perl/lib/LWP/UserAgent.pm
# 6.30.0	http://search.cpan.org/~gaas/HTTP-Message/lib/HTTP/Request.pm
# 2.272.20	http://search.cpan.org/~makamaka/JSON-PP/lib/JSON/PP.pm
# 0.230.0	http://search.cpan.org/~dagolden/File-Temp-0.2304/lib/File/Temp.pm
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

use HTTP::Request;
use JSON::XS;

########################################

$| = "1";

################################################################################

my $FILE		= "drive";

my $URL_WEB		= "https://mail.google.com/tasks/canvas";
my $URL_OAUTH_AUTH	= "https://accounts.google.com/o/oauth2/auth";
my $URL_OAUTH_TOKEN	= "https://accounts.google.com/o/oauth2/token";
my $URL_SCOPE		= "https://www.googleapis.com/auth/drive";
my $URL_API_UP		= "https://www.googleapis.com/upload/drive/v3";
my $URL_API		= "https://www.googleapis.com/drive/v3";

my $REQ_PER_SEC		= "3";
my $REQ_PER_SEC_SLEEP	= "2";

########################################

our $USERNAME;
our $PASSWORD;
our $CLIENTID;
our $CLSECRET;
our $REDIRECT;
do("./.auth-${FILE}") || die();

our $CODE;
our $REFRESH;
our $ACCESS;
do("./.token-${FILE}") || die($!);

################################################################################

my $API_REQUEST_COUNT	= "0";

sub EXIT {
	my $status = shift || "0";
	print "\nAPI Requests: ${API_REQUEST_COUNT}\n";
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

		open(OUTPUT, ">", ".token-${FILE}") || die();
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

	$mech->add_header("Authorization" => "Bearer ${ACCESS}");

	return(0);
};

########################################

sub api_req_per_sec {
	$API_REQUEST_COUNT++;
	if ((${API_REQUEST_COUNT} % ${REQ_PER_SEC}) == 0) {
		sleep(${REQ_PER_SEC_SLEEP});
	};
	return();
};

################################################################################

sub api_upload {
	my $file	= shift;
	my $id		= shift;

	open(INPUT, "<", ${file}) || die();
	my $input = do { local $/; <INPUT> };
	close(INPUT) || die();

	$mech->request(HTTP::Request->new(
		"PATCH", "${URL_API_UP}/files/${id}?uploadType=media", [], ${input},
	)) && api_req_per_sec();

	print "${file} (";
	{ use bytes; print length(${input}); };
	print ") -> ${id}\n";

	return(0);
};

########################################

sub api_download {
	my $file	= shift;
	my $id		= shift;

	$mech->get("${URL_API}/files/${id}?alt=media") && api_req_per_sec();
	my $output = $mech->content();

	open(OUTPUT, ">", ${file}) || die();
	print OUTPUT ${output};
	close(OUTPUT) || die();

	print "${id} -> ${file} (";
	{ use bytes; print length(${output}); };
	print ")\n";

	return(0);
};

################################################################################

if (@{ARGV}) {
	&refresh_tokens();
	print "\n";

	my $upload = "0";
	my $num = "0";
	while ($ARGV[${num}]) {
		if ($ARGV[${num}] eq "upload") {
			$upload = "1";
			splice(@{ARGV}, ${num}, 1);
			${num}--;
		};
		${num}++;
	};

	foreach my $drive (@{ARGV}) {
		my($file, $id) = split(/[:]/, ${drive});
		if (${upload}) {
			&api_upload(${file}, ${id});
		} else {
			&api_download(${file}, ${id});
		};
	};
};

########################################

&EXIT(0);

################################################################################
# end of file
################################################################################
