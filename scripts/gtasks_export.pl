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
#>>> ${web}, ${PURGE_LIST}, ${URL_WEB_POST} and ${purge_list} only exist for the hackery in &{purge_lists}!
#my $web = WWW::Mechanize->new(
#	"agent"		=> "Mozilla/5.0",
#	"autocheck"	=> "1",
#	"stack_depth"	=> "0",
#	"onwarn"	=> \&web_fail,
#	"onerror"	=> \&web_fail,
#);
#sub web_fail {
#	&DUMPER($web->response());
#	&confess();
#};
#>>>

use HTTP::Request;
use JSON::XS;
my $json = JSON::XS->new();

use File::Temp qw(tempfile);
use MIME::Base64;

use POSIX qw(strftime);

########################################

$| = "1";

################################################################################

my $FILE		= "tasks";
my $DEFAULT_LIST	= "0.GTD";
my $PROJECT_LIST	= "0.Projects";
#>>> ${web}, ${PURGE_LIST}, ${URL_WEB_POST} and ${purge_list} only exist for the hackery in &{purge_lists}!
#my $PURGE_LIST		= "PURGE";
#>>>

my $PROJ_LINK_NORMAL	= "*";
my $PROJ_LINK_OPEN	= "=";
my $PROJ_LINK_CLOSED	= "x";
my $PROJ_LINK_SEPARATE	= ": ";

my $NOTES_APPEND	= "[...]";
my $NOTES_LENGTH	= ((2**13) - length(${NOTES_APPEND}));

my $INDENT		= " ";

my $URL_WEB		= "https://mail.google.com/tasks/canvas";
my $URL_OAUTH_AUTH	= "https://accounts.google.com/o/oauth2/auth";
my $URL_OAUTH_TOKEN	= "https://accounts.google.com/o/oauth2/token";
my $URL_SCOPE		= "https://www.googleapis.com/auth/tasks";
my $URL_API		= "https://www.googleapis.com/tasks/v1";
#>>> ${web}, ${PURGE_LIST}, ${URL_WEB_POST} and ${purge_list} only exist for the hackery in &{purge_lists}!
#my $URL_WEB_POST	= "https://mail.google.com/tasks/r/d";
#>>>

my $REQ_PER_SEC		= "3";
my $REQ_PER_SEC_SLEEP	= "2";

########################################

my $SEARCH_FIELDS = [
	"title",
	"due",
	"notes",
];

my $MANAGE_LINKS_ALL	= "0";
my $MLINK_SRC		= "PARENTS";
my $MLINK_DST		= "CHILDREN";

my $MANAGE_CRUFT_ALL	= "1";

my $EXPORT_JSON		= "1";
my $EXPORT_CSV		= "1";
my $EXPORT_TXT		= "1";

my $JSON_FIELDS = [
	"kind",
	"id",
	"etag",
	"title",
	"updated",
	"selfLink",
	"parent",
	"position",
	"notes",
	"status",
	"due",
	"completed",
	"deleted",
	"hidden",
	"links",

	"nextPageToken",
	"items",
];

my $CSV_FIELDS = [
	"title",

	"due",
	"status",
	"completed",
	"deleted",
	"hidden",
	"notes",

	"kind",
	"id",
	"etag",
	"selfLink",
	"updated",

	"parent",
	"position",
	"links",
];

my $HIDE_COMPLETED	= "0";
my $HIDE_DELETED	= "0";

my $CAT_TEXT		= "0";

########################################

#>>> JSON Methods

	$json->allow_blessed(0);
	$json->allow_nonref(0);
	$json->allow_unknown(0);
	$json->convert_blessed(0);
	$json->relaxed(0);

	$json->ascii(1);
	$json->latin1(0);
	$json->utf8(0);

	$json->canonical(0);
	$json->pretty(0);
	$json->shrink(0);

	$json->indent(1);
	$json->space_after(1);
	$json->space_before(0);

#>>> JSON::PP Methods

#>	$json->loose(0);
#>
#>	$json->escape_slash(0);
#>	$json->indent_length(1);
#>
#>	$json->sort_by(sub {
#>		my $order = {};
#>		#>>> http://learn.perl.org/faq/perlfaq4.html#How-do-I-merge-two-hashes-
#>		@{ $order }{@{ $JSON_FIELDS }} = 0..$#{ $JSON_FIELDS };
#>		if (exists($order->{$JSON::PP::a}) && exists($order->{$JSON::PP::b})) {
#>			$order->{$JSON::PP::a} <=> $order->{$JSON::PP::b};
#>		} else {
#>			$JSON::PP::a cmp $JSON::PP::b;
#>		};
#>	});

########################################

our $USERNAME;
our $PASSWORD;
our $CLIENTID;
our $CLSECRET;
our $REDIRECT;
do("./.auth") || die();

our $CODE;
our $REFRESH;
our $ACCESS;
do("./.token") || die();

################################################################################

my $API_ERROR		= "GTASKS_EXPORT_ERROR";
my $API_PAGES		= "GTASKS_EXPORT_PAGES";

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

sub api_get {
	my $url		= shift;
	my $fields	= shift;
	my $object;
	my $page;

#>>> BUG IN GOOGLE TASKS API!
#>>> http://code.google.com/a/google.com/p/apps-api-issues/issues/detail?id=2837
#>>> SHOULD BE ABLE TO REQUEST AN ARBITRARY AMOUNT
	$url .= "?maxResults=100";

	if (defined(${fields})) {
		foreach my $field (keys(%{$fields})) {
			$url .= "&" . ${field} . "=" . $fields->{$field};
		};
	};

	do {
		$mech->get("${url}"
			. (defined(${page}) ? "&pageToken=${page}" : "")
		) && api_req_per_sec();
		my $out = decode_json($mech->content());

		#>>> http://www.perlmonks.org/?node_id=995613
		foreach my $key (keys(%{$out})) {
			if (exists($object->{$key}) && $object->{$key} ne $out->{$key}) {
				if (ref($object->{$key}) eq "ARRAY") {
					push(@{$object->{$key}}, @{$out->{$key}});
				} else {
					push(@{$object->{$API_ERROR}}, [ ${key}, $object->{$key}, $out->{$key} ]);
				};
			} else {
				$object->{$key} = $out->{$key};
			};
		}

		$page = $out->{"nextPageToken"};
		delete($out->{"nextPageToken"});
		delete($object->{"nextPageToken"});
		$object->{$API_PAGES}++;
	}
	until (!defined(${page}));

	return(${object});
};

########################################

sub api_method {
	my $method	= shift;
	my $object	= shift;
	my $fields	= shift;
	my $selflink = $object->{"selfLink"};
	if ($fields->{"parent"}) {
		$selflink .= "?";
		$selflink .= "parent=" . ($fields->{"parent"} || "");
	};
	if ($fields->{"previous"}) {
		if (!$fields->{"parent"}) {	$selflink .= "?";
		} else {			$selflink .= "&";
		};
		$selflink .= "previous=" . ($fields->{"previous"} || "");
	};
	if ($fields->{"notes"}) {
		$fields->{"notes"} = substr($fields->{"notes"} || "", 0, ${NOTES_LENGTH}) . ${NOTES_APPEND};
	};
	$mech->request(HTTP::Request->new(
		${method}, ${selflink}, ["Content-Type", "application/json"], encode_json(${fields}),
	)) && api_req_per_sec();
	if (${method} eq "DELETE") {
		return(0);
	} else {
		return(decode_json($mech->content()));
	};
};

################################################################################

sub api_create_list {
	my $fields = shift;
	my $object = {};
#>>> THIS IS A HACK!
	$object->{"selfLink"} = "${URL_API}/users/\@me/lists";
#>>>
	my $output = &api_method("POST", ${object}, ${fields});
	return(${output});
};

########################################

sub api_fetch_lists {
	my $output = &api_get("${URL_API}/users/\@me/lists");
	return(${output});
};

########################################

sub api_create_task {
	my $listid	= shift;
	my $fields	= shift;
	my $object	= {};
#>>> THIS IS A HACK!
	$object->{"selfLink"} = "${URL_API}/lists/${listid}/tasks";
#>>>
	my $output = &api_method("POST", ${object}, ${fields});
	return(${output});
};

########################################

sub api_fetch_tasks {
	my $listid	= shift;
	my $output = &api_get("${URL_API}/lists/${listid}/tasks", {
		"showCompleted"		=> "true",
		"showDeleted"		=> "true",
		"showHidden"		=> "true",
	});
	return(${output});
};

################################################################################

sub taskwarrior_export {
	my $title	= shift || "Export";
	my $tasks	= shift || "";
	my $search	= shift || "";
	my $links	= [];
	my $previous	= undef;
	my $filter;
	my $fields;
	my $created;
	my $listid;
	my $output;

	print "\n${title}: ";

	if (!${tasks}) {
		$tasks = qx(task show rc.defaultwidth=0 "default.command" 2>&1);	$tasks =~ m/^default[.]command[ ](.*)$/gm;		$tasks = (${1} || "");
	};
	$filter = qx(task show rc.defaultwidth=0 "report.${tasks}.filter" 2>&1);	$filter =~ m/^report[.]${tasks}[.]filter[ ](.*)$/gm;	$filter = (${1} || "");
	$fields = qx(task show rc.defaultwidth=0 "report.${tasks}.sort" 2>&1);		$fields =~ m/^report[.]${tasks}[.]sort[ ](.*)$/gm;	$fields = (${1} || "");
	$tasks = qx(task export "${filter}" "${search}");
	$tasks =~ s/\n//g;
	$tasks = decode_json(${tasks});

	$output = &api_fetch_lists();

	foreach my $tasklist (@{$output->{"items"}}) {
		if ($tasklist->{"title"} eq ${title}) {
			$created = "1";
			$listid = $tasklist->{"id"};

			$output = &api_fetch_tasks($tasklist->{"id"});

			foreach my $task (@{$output->{"items"}}) {
				push(@{$links}, ${task});
			};

			last();
		};
	};
	if (!${created}) {
		$output = &api_create_list({
			"title"		=> ${title},
		});
		$listid = $output->{"id"};
	};

#>>> BUG IN PERL!
#>>> http://www.perlmonks.org/?node_id=490213
	my @array = @{$tasks};
	my @yarra = split(/,/, ${fields});
	foreach my $task (sort({
		my $result = "0";
		my %pri = ("H" => 3, "M" => 2, "L" => 1);
		foreach my $field_source (@{yarra}) {
			my $field = ${field_source};
			my $order = "";
			if ($field =~ m/[+-]$/) {
				$field =~ s/([+-])$//g;
				$order = ${1};
			};
			if (${field} eq "priority") {
				my $aa = ($a->{$field} || "");
				my $bb = ($b->{$field} || "");
				if (${order} eq "-") {
					$result = ($pri{$bb} || "0") <=> ($pri{$aa} || "0");
				} else {
					$result = ($pri{$aa} || "0") <=> ($pri{$bb} || "0");
				};
			} elsif (
				(${field} eq "id") ||
				(${field} eq "imask") ||
				(${field} eq "urgency")
			) {
				if (${order} eq "-") {
					$result = ($b->{$field} || "0") <=> ($a->{$field} || "0");
				} else {
					$result = ($a->{$field} || "0") <=> ($b->{$field} || "0");
				};
			} elsif (
				(${field} eq "due") ||
				(${field} eq "end") ||
				(${field} eq "entry") ||
				(${field} eq "modified") ||
				(${field} eq "scheduled") ||
				(${field} eq "start") ||
				(${field} eq "until") ||
				(${field} eq "wait")
			) {
				if (${order} eq "-") {
					$result = ($b->{$field} || "0") cmp ($a->{$field} || "0");
				} else {
					$result = ($a->{$field} || "9999") cmp ($b->{$field} || "9999");
				};
			} else {
				if (${order} eq "-") {
					$result = ($b->{$field} || "") cmp ($a->{$field} || "");
				} else {
					$result = ($a->{$field} || "") cmp ($b->{$field} || "");
				};
			};
			if (${result} != 0) {
				last();
			};
		};
		return(${result});
	} @{array})) {
#>>>
		if ($task->{"status"} eq "deleted") {
			$task->{"deleted"} = "true";
		};
		$task->{"status"} = "needsAction";
		$task->{"notes"} = "";
		if (defined($task->{"due"})) {
			$task->{"due"} =~ s/^([0-9]{4})([0-9]{2})([0-9]{2})[T]([0-9]{2})([0-9]{2})([0-9]{2})[Z]$/$1-$2-$3T$4:$5:$6Z/;
		};
		if (defined($task->{"end"})) {
			$task->{"end"} =~ s/^([0-9]{4})([0-9]{2})([0-9]{2})[T]([0-9]{2})([0-9]{2})([0-9]{2})[Z]$/$1-$2-$3T$4:$5:$6Z/;
			$task->{"status"} = "completed";
		};
		if (defined($task->{"annotations"})) {
			foreach my $annotation (@{$task->{"annotations"}}) {
				if ($annotation->{"description"} =~ /^[[]notes[]][:]/) {
					my $notes = $annotation->{"description"};
					$notes =~ s/^[[]notes[]][:]//g;
					$task->{"notes"} = decode_base64(${notes});
				};
			};
		};
		my $task_title = $task->{"description"};
		if (defined($task->{"project"}))	{ $task_title = "[" . $task->{"project"} . "] " . ${task_title}		; };
		if (defined($task->{"priority"}))	{ $task_title = "<" . $task->{"priority"} . "> " . ${task_title}	; };
		if (defined($task->{"tags"}))		{ $task_title .= " @" . join(" @", @{$task->{"tags"}})			; };
		if (defined($task->{"uuid"}))		{ $task_title .= " [" . substr($task->{"uuid"}, 0, 8) . "]"		; };
		my $blob = {
			"title"		=> ${task_title},
			"status"	=> $task->{"status"},
			"due"		=> $task->{"due"},
			"completed"	=> $task->{"end"},
			"deleted"	=> $task->{"deleted"},
			"notes"		=> $task->{"notes"},
			"parent"	=> undef,
			"previous"	=> ${previous},
		};
		if (@{$links}) {
			$output = &api_method("PATCH", shift(@{$links}), ${blob});
			$previous = $output->{"id"};
			print "=";
		} else {
			$output = &api_create_task(${listid}, ${blob});
			$previous = $output->{"id"};
			print "+";
		};
	};

	while (@{$links}) {
		$output = &api_method("PATCH", shift(@{$links}), {
			"title"		=> "0",
			"status"	=> "needsAction",
			"due"		=> undef,
			"completed"	=> undef,
			"deleted"	=> JSON::XS::true,
			"notes"		=> "",
			"parent"	=> undef,
			"previous"	=> ${previous},
		});
		$previous = $output->{"id"};
		print "-";
	};

	print "\n";

	return(0);
};

########################################

sub taskwarrior_import {
	my $title	= shift;
	my $created;
	my $output;
	my $taskid;
	my $uuid;

	print "\n${title}:\n";

	$output = &api_fetch_lists();

	foreach my $tasklist (@{$output->{"items"}}) {
		if ($tasklist->{"title"} eq ${title}) {
			$created = "1";

			$output = &api_fetch_tasks($tasklist->{"id"});

			foreach my $task (@{$output->{"items"}}) {
				if (!$task->{"completed"} && !$task->{"deleted"}) {
					print "\n";
					print $task->{"title"} . "\n";

					alarm 10;
					chomp($output = qx(task $task->{"title"} 2>&1));
					my $status = $?;
					alarm 0;

					if (${status} != 0 ) {
						$output = "FAILED COMMAND!\n" . ${output};
						print STDERR ${output} . "\n";

						&api_method("PATCH", ${task}, {
							"notes"		=> ${output},
						});
					} else {
						$taskid = ${output};
						$taskid =~ m/task[ ]([0-9a-f-]+)/;
						$taskid = $1;

						if (!${taskid}) {
							$output = "UNKNOWN OUTPUT!\n" . ${output};
							print STDERR ${output} . "\n";

							&api_method("PATCH", ${task}, {
								"notes"		=> ${output},
							});
						} else {
							print ${output} . "\n";

							chomp($uuid = qx(task uuids ${taskid}));
							chomp($taskid = qx(task export ${uuid}));
							$uuid = $task->{"updated"} . "\n" . ${uuid} . "\n" . ${taskid};
							print ${uuid} . "\n";

							&api_method("PATCH", ${task}, {
								"status"	=> "completed",
								"completed"	=> strftime("%Y-%m-%dT%H:%M:%SZ", gmtime()),
								"notes"		=> ${uuid},
							});
						};
					};
				};
			};

			last();
		};
	};

	if (!${created}) {
		print STDERR "\n";
		print STDERR "DOES NOT EXIST!\n";
		&EXIT(1);
	};

	return(0);
};

########################################

sub search_regex {
	my $regex	= shift;
	my $output;

	print "\n";

	$output = &api_fetch_lists();

#>>> BUG IN PERL!
#>>> http://www.perlmonks.org/?node_id=490213
	my @array = @{$output->{"items"}};
	foreach my $tasklist (sort({$a->{"title"} cmp $b->{"title"}} @{array})) {
#>>>
		if ($tasklist->{"title"} ne ${DEFAULT_LIST}) {
			printf("%-10.10s %-50.50s %s\n", (("-" x 9) . ">"), $tasklist->{"id"}, $tasklist->{"title"} || "-");

			$output = &api_fetch_tasks($tasklist->{"id"});

			foreach my $task (@{$output->{"items"}}) {
				my $match;
				foreach my $field (@{$SEARCH_FIELDS}) {
					if (
						!$task->{"completed"} && !$task->{"deleted"} &&
						$task->{$field} && $task->{$field} =~ m|${regex}|gm
					) {
						push(@{$match}, ${field});
					};
				};
				if (${match}) {
					print "\t" . $task->{"title"} . "\n";
					foreach my $field (@{$match}) {
						if (${field} eq "title") {
							print "\t\t<" . ${field} . ">\n";
							next();
						};
						my $test = $task->{$field};
						my $link = "\\s*(?:MATCH|[${PROJ_LINK_NORMAL}${PROJ_LINK_OPEN}${PROJ_LINK_CLOSED}][ ])?";
						while (${test} =~ m|^${link}(.*${regex}.*)$|gm) {
							print "\t\t<" . ${field} . ">\t" . $1 . "\n";
						};
					};
				};
			};
		};
	};

	return(0);
};

########################################

sub manage_links {
	my $links	= {};
	my $output;

	$output = &api_fetch_lists();

#>>> BUG IN PERL!
#>>> http://www.perlmonks.org/?node_id=490213
	my @array = @{$output->{"items"}};
	foreach my $tasklist (sort({$a->{"title"} cmp $b->{"title"}} @{array})) {
#>>>
		if ($tasklist->{"title"} ne ${DEFAULT_LIST}) {
			my $out = &manage_links_list($tasklist->{"id"});
			if ($tasklist->{"title"} eq ${PROJECT_LIST}) {
				#>>> http://learn.perl.org/faq/perlfaq4.html#How-do-I-merge-two-hashes-
				@{ $links->{$MLINK_SRC} }{keys(%{ $out->{$MLINK_SRC} })} = values(%{ $out->{$MLINK_SRC} });
			} else {
				#>>> http://learn.perl.org/faq/perlfaq4.html#How-do-I-merge-two-hashes-
				@{ $links->{$MLINK_DST} }{keys(%{ $out->{$MLINK_DST} })} = values(%{ $out->{$MLINK_DST} });
			};
		};
	};

	foreach my $key (sort({$a cmp $b} keys(%{ $links->{$MLINK_SRC} }))) {
		foreach my $val (@{$links->{$MLINK_SRC}->{ $key }}) {
			my $match = 0;
			foreach my $cmp (@{$links->{$MLINK_DST}->{ $key }}) {
				if ($val eq $cmp) {
					$match = 1;
				};
			};
			if (!${match}) {
				push(@{$links->{"NONE_$MLINK_DST"}->{ $key }}, $val);
			};
		};
	};
	foreach my $key (sort({$a cmp $b} keys(%{ $links->{$MLINK_DST} }))) {
		foreach my $val (@{$links->{$MLINK_DST}->{ $key }}) {
			my $match = 0;
			foreach my $cmp (@{$links->{$MLINK_SRC}->{ $key }}) {
				if ($val eq $cmp) {
					$match = 1;
				};
			};
			if (!${match}) {
				push(@{$links->{"NONE_$MLINK_SRC"}->{ $key }}, $val);
			};
		};
	};

	print "\n";
	print "NO ${MLINK_DST}\n";
	foreach my $key (sort({$a cmp $b} keys(%{ $links->{"NONE_$MLINK_DST"} }))) {
		print "\t${key}\n";
		foreach my $val (@{$links->{"NONE_$MLINK_DST"}->{ $key }}) {
			print "\t\t${val}\n";
		};
	};
	print "NO ${MLINK_SRC}\n";
	foreach my $key (sort({$a cmp $b} keys(%{ $links->{"NONE_$MLINK_SRC"} }))) {
		foreach my $val (@{$links->{"NONE_$MLINK_SRC"}->{ $key }}) {
			print "\t${key}${PROJ_LINK_SEPARATE}${val}\n";
		};
	};

	return(0);
};

########################################

sub manage_links_list {
	my $listid	= shift;
	my $output;

	$output = &api_fetch_tasks(${listid});

	foreach my $task (@{$output->{"items"}}) {
		while ($task->{"notes"} && $task->{"notes"} =~ m|^\s*([${PROJ_LINK_OPEN}${PROJ_LINK_CLOSED}])[ ](.+)$|gm) {
			if (${MANAGE_LINKS_ALL} || (!$task->{"completed"} && $1 ne ${PROJ_LINK_CLOSED})) {
				push(@{$output->{$MLINK_SRC}->{ $task->{"title"} }}, $2);
			};
		};
		while ($task->{"title"} && $task->{"title"} =~ m|^(.+)${PROJ_LINK_SEPARATE}(.+)$|gm) {
			if (${MANAGE_LINKS_ALL} || !$task->{"completed"}) {
				push(@{$output->{$MLINK_DST}->{ $1 }}, $2);
			};
		};
	};

	return(${output});
};

########################################

sub manage_cruft {
	my $output;

	print "\n";

	$output = &api_fetch_lists();

#>>> BUG IN PERL!
#>>> http://www.perlmonks.org/?node_id=490213
	my @array = @{$output->{"items"}};
	foreach my $tasklist (sort({$a->{"title"} cmp $b->{"title"}} @{array})) {
#>>>
		if (${MANAGE_CRUFT_ALL} || $tasklist->{"title"} eq ${DEFAULT_LIST}) {
			printf("%-10.10s %-50.50s %s\n", (("-" x 9) . ">"), $tasklist->{"id"}, $tasklist->{"title"} || "-");
			&manage_cruft_list($tasklist->{"id"});
		};
	};

	return(0);
};

########################################

sub manage_cruft_list {
	my $listid	= shift;
	my $output;

	$output = &api_fetch_tasks(${listid});

	foreach my $task (@{$output->{"items"}}) {
#>>> BUG IN GOOGLE TASKS API!
#>>> http://code.google.com/a/google.com/p/apps-api-issues/issues/detail?id=2888
#>>> SHOULD JUST BE ABLE TO MOVE THEM TO A "PURGE" LIST FOR MANUAL DELETION
		if ($task->{"title"} =~ "\n") {
			$task->{"title"} =~ s/\n//g;
			printf("%-10.10s %-50.50s %s\n", "rescuing:", $task->{"id"}, $task->{"title"} || "-");
			&api_method("PATCH", ${task}, {
				"title"		=> $task->{"title"},
			});
		};

		if (	$task->{"title"} ne "0"	&&
			!$task->{"title"}	&&
			!$task->{"notes"}	&&
			!$task->{"due"}
		) {
			printf("%-10.10s %-50.50s %s\n", "clearing:", $task->{"id"}, $task->{"title"} || "-");
			&api_method("PATCH", ${task}, {
				"title"		=> "0",
				"status"	=> "needsAction",
				"completed"	=> undef,
				"deleted"	=> "0",
			});
		};

		if ((	!$task->{"title"}	&& (
			$task->{"notes"}	||
			$task->{"due"}		)
		) || (
			$task->{"deleted"}
		)) {
			printf("%-10.10s %-50.50s %s\n", "reviving:", $task->{"id"}, $task->{"title"} || "-");
			&api_method("PATCH", ${task}, {
				"title"		=> "[" . sprintf("%.3d", int(rand(10**3))) . "]:[" . $task->{"title"} . "]",
				"status"	=> "needsAction",
				"completed"	=> undef,
				"deleted"	=> "0",
			});
		};
#>>>
	};

	return(0);
};

########################################

sub purge_lists {
	my $skips	= shift;
	my $keeps	= shift;
	my $skip;
	my $keep;
	my $output;

	if ($skips) { $skips = [ split(",", ${skips}) ]; } else { $skips = []; };
	if ($keeps) { $keeps = [ split(",", ${keeps}) ]; } else { $keeps = []; };

	print "\n";

#>>> ${web}, ${PURGE_LIST}, ${URL_WEB_POST} and ${purge_list} only exist for the hackery in &{purge_lists}!
#	$output = &api_create_list({
#		"title"		=> ${PURGE_LIST},
#	});
#	my $purge_list = $output->{"selfLink"};
#	$web = &auth_login(${web});
#>>>
	$output = &api_fetch_lists();

#>>> BUG IN PERL!
#>>> http://www.perlmonks.org/?node_id=490213
	my @array = @{$output->{"items"}};
	foreach my $tasklist (sort({$a->{"title"} cmp $b->{"title"}} @{array})) {
#>>>
		$skip = "0";
		$keep = "0";

		foreach my $list (@{$skips}) {
			if ($tasklist->{"title"} eq ${list}) {
				$skip = "1";
				last();
			};
		};
		foreach my $list (@{$keeps}) {
			if ($tasklist->{"title"} eq ${list}) {
				$keep = "1";
				last();
			};
		};

#>>> ${web}, ${PURGE_LIST}, ${URL_WEB_POST} and ${purge_list} only exist for the hackery in &{purge_lists}!
#		if ($tasklist->{"selfLink"} eq ${purge_list}) {
#			print $tasklist->{"title"} . ": ignored";
#		}
#		elsif ($skip) {
		if ($skip) {
#>>>
			print $tasklist->{"title"} . ": skipped";
		}
		elsif ($keep) {
			print $tasklist->{"title"} . ": keeping";
#>>> MISSING FEATURE IN GOOGLE TASKS!
#>>> https://productforums.google.com/d/msg/gmail/yKbRwhi6hYU/48XhvtZ5LTIJ
#>>> https://productforums.google.com/d/msg/gmail/yKbRwhi6hYU/2QXGlAfwQx4J
			$output = &api_fetch_tasks($tasklist->{"id"});
			foreach my $task (@{$output->{"items"}}) {
				&api_method("PATCH", ${task}, {
#>>>					"title"		=> " ",
					"title"		=> "0",
#>>>					"status"	=> "needsAction",
					"status"	=> "completed",
					"due"		=> undef,
#>>>					"completed"	=> undef,
					"completed"	=> strftime("%Y-%m-%dT%H:%M:%SZ", gmtime()),
					"deleted"	=> undef,
					"notes"		=> "",
				});
#>>>				&api_method("DELETE", ${task});
				print ".";
			};
#>>> ${web}, ${PURGE_LIST}, ${URL_WEB_POST} and ${purge_list} only exist for the hackery in &{purge_lists}!
#>>> keeping for posterity... this crap didn't work either (essentially the same effect)...
#			$web->get(${URL_WEB});
#			$output = $web->content();
#			$output =~ s|^.+<script>function _init\(\){_setup\(||gms;
#			$output =~ s|\)}</script>.+$||gms;
#			$output = decode_json(${output});
#
#			#>>> https://stackoverflow.com/questions/4214917/android-problem-to-access-google-tasks-with-oauth#4771907
#			$web->add_header("AT" => "1");
#
#			my $target;
#			my $id;
#
#			foreach $output (@{ $output->{"t"}{"lists"} }) {
#				#>>> technically, ${PURGE_LIST} is not accurate here, but what the hell... this is a total hack already...
#				if ($output->{"name"} eq ${PURGE_LIST}) {
#					$target = $output->{"id"};
#				};
#				if ($output->{"name"} eq $tasklist->{"title"}) {
#					$id = $output->{"id"};
#				};
#			};
#
#			$web->post(${URL_WEB_POST}, {
#				"r"				=> encode_json({
#					"action_list"		=> [{
#						"action_type"	=> "get_all",
#						"action_id"	=> "0",
#						"list_id"	=> ${id},
#						"get_deleted"	=> JSON::XS::true,
#					}],
#					"client_version"	=> "0",
#				}),
#			});
#			$output = decode_json($web->content());
#
#			foreach $output (@{ $output->{"tasks"} }) {
#				$web->post(${URL_WEB_POST}, {
#					"r"				=> encode_json({
#						"action_list"		=> [{
#							"action_type"	=> "move",
#							"action_id"	=> "0",
#							"id"		=> $output->{"id"},
#							"source_list"	=> ${id},
#							"dest_list"	=> ${target},
#							"dest_parent"	=> ${target},
#						}],
#						"current_list_id"	=> ${id},
#						"client_version"	=> "0",
#						"last_sync_point"	=> "0",
#					}),
#				});
#				#>>> clear instead of move, just for fun...
#				#$web->post(${URL_WEB_POST}, {
#				#	"r"				=> encode_json({
#				#		"action_list"		=> [{
#				#			"action_type"	=> "update",
#				#			"action_id"	=> "0",
#				#			"id"		=> $output->{"id"},
#				#			"entity_delta"	=> { "task_date" => "", },
#				#		}],
#				#		"current_list_id"	=> ${id},
#				#		"client_version"	=> "0",
#				#		"last_sync_point"	=> "0",
#				#	}),
#				#});
#				#$web->post(${URL_WEB_POST}, {
#				#	"r"				=> encode_json({
#				#		"action_list"		=> [{
#				#			"action_type"	=> "update",
#				#			"action_id"	=> "0",
#				#			"id"		=> $output->{"id"},
#				#			"entity_delta"	=> { "notes" => "", },
#				#		}],
#				#		"current_list_id"	=> ${id},
#				#		"client_version"	=> "0",
#				#		"last_sync_point"	=> "0",
#				#	}),
#				#});
#				#>>>
#				print ",";
#			};
#>>>
		}
		else {
			print $tasklist->{"title"} . ": purged";
			&api_method("DELETE", ${tasklist});
		};

		print "\n";
	};

#>>> ${web}, ${PURGE_LIST}, ${URL_WEB_POST} and ${purge_list} only exist for the hackery in &{purge_lists}!
#	&api_method("DELETE", ${purge_list});
#>>>
	return(0);
};

#######################################

sub edit_notes {
	my $argv_list	= shift;
	my $argv_name	= shift;
	my $object;
	my $output;

	if (${argv_list} eq "0") {
		$argv_list = ${PROJECT_LIST};
	};

	$output = &api_fetch_lists();

	foreach my $tasklist (@{$output->{"items"}}) {
		if ($tasklist->{"title"} eq ${argv_list}) {
			$output = &api_fetch_tasks($tasklist->{"id"});

			foreach my $task (@{$output->{"items"}}) {
				if ($task->{"title"} eq ${argv_name}) {
					$object = ${task};
					last();
				};
			};

			last();
		};
	};

	if (!${object}) {
		print STDERR "\n";
		print STDERR "DOES NOT EXIST!\n";
		&EXIT(1);
	} else {
		$output = &api_get($object->{"selfLink"});
		$output = &edit_notes_text($output->{"notes"});

		if ($output) {
			&refresh_tokens();
			&api_method("PATCH", ${object}, {
				"notes"		=> ${output},
			});
		};
	};

	return(0);
};

########################################

sub edit_notes_text {
	my $notes	= shift;

	$notes =~ s|^(${INDENT}+)|("\t" x (length($1) / 2))|egm;

	my($TEMPFILE, $tempfile) = tempfile(".${FILE}.XXXX", "UNLINK" => "0");
	print ${TEMPFILE} ${notes};
	close(${TEMPFILE}) || die();

	system("${ENV{EDITOR}} ${tempfile}");

	open(${TEMPFILE}, "<", "${tempfile}") || die();
	$notes = do { local $/; <$TEMPFILE> };
	close(${TEMPFILE}) || die();

	$notes =~ s|^(\t+)|(${INDENT} x (length($1) * 2))|egm;
	$notes =~ s/\n+$//;

	return(${notes});
};

########################################

sub export_files {
	my $output;

	(${EXPORT_JSON}) && (open(JSON, ">", "${FILE}.json") || die());
	(${EXPORT_CSV})  && (open(CSV,  ">", "${FILE}.csv")  || die());
	(${EXPORT_TXT})  && (open(TXT,  ">", "${FILE}.txt")  || die());

	if (${EXPORT_CSV}) {
		print CSV "\"indent\",";
		foreach my $field (@{$CSV_FIELDS}) {
			print CSV "\"${field}\",";
		};
		print CSV "\n";
	};

	$output = &api_fetch_lists();

	if (${EXPORT_JSON}) {
		print JSON ("#" x 5) . "[ LISTS ]" . ("#" x 5) . "\n\n";
		print JSON $json->encode(${output});
		print JSON "\n";
	};

#>>> BUG IN PERL!
#>>> http://www.perlmonks.org/?node_id=490213
	my @array = @{$output->{"items"}};
	foreach my $tasklist (sort({$a->{"title"} cmp $b->{"title"}} @{array})) {
#>>>
		$output = &api_fetch_tasks($tasklist->{"id"});

		$tasklist->{"title"} .= " (" . ($#{$output->{"items"}} + 1) . ")";

		if (${EXPORT_JSON}) {
			print JSON ("#" x 5) . "[ " . $tasklist->{"title"} . " ]" . ("#" x 5) . "\n\n";
			print JSON $json->encode(${output});
			print JSON "\n";
		};

		&export_files_item(${tasklist}, "-", "-");
		&export_files_list(${output});

		print TXT  "\n";
	};

	(${EXPORT_JSON}) && print JSON ("#" x 5) . "[ END OF FILE ]" . ("#" x 5) . "\n";
	(${EXPORT_TXT})  && print TXT  ("=" x 5) . "[ END OF FILE ]" . ("=" x 5) . "\n";

	(${EXPORT_JSON}) && (close(JSON) || die());
	(${EXPORT_CSV})  && (close(CSV)  || die());
	(${EXPORT_TXT})  && (close(TXT)  || die());

	if (${EXPORT_TXT} && ${CAT_TEXT}) {
		open(TXT, "<", "${FILE}.txt") || die();
		print "\n";
		print <TXT>;
		close(TXT) || die();
	};

	return(0);
};

########################################

sub export_files_list {
	my $list	= shift;
	my $tree	= {};

	foreach my $task (@{$list->{"items"}}) {
		(${HIDE_COMPLETED}	&& $task->{"completed"}		) && (next());
		(${HIDE_DELETED}	&& $task->{"deleted"}		) && (next());
		if (!exists($task->{"parent"})) {
			$tree->{$task->{"id"}} = {
				"node" => ${task},
				"pos" => $task->{"position"},
			};
		} else {
			$tree->{$task->{"parent"}}{"sub"}{$task->{"id"}} = {
				"node" => ${task},
				"pos" => $task->{"position"},
			};
		};
	};

	&export_files_list_tree(${tree}, ${tree}, "0");

	return(0);
};

########################################

sub export_files_list_tree {
	my $root_tree	= shift;
	my $tree	= shift;
	my $indent	= shift;
	my $key;

	foreach $key (keys(%{$tree})) {
		if (!exists($tree->{$key}->{"pos"})) {
			$tree->{$key}->{"pos"} = "";
		};
	};

	foreach $key (sort({$tree->{$a}{"pos"} cmp $tree->{$b}{"pos"}} keys(%{$tree}))) {
		if ($tree->{$key}->{"pos"}) {
			&export_files_item($tree->{$key}{"node"}, ${indent}, "");
			if (exists($root_tree->{$key}{"sub"})) {
				&export_files_list_tree(${root_tree}, $root_tree->{$key}->{"sub"}, (${indent} + 1));
			};
		};
	};

	return(0);
};

########################################

sub export_files_item {
	my $task	= shift;
	my $indent	= shift;
	my $empty	= shift;

	if (${EXPORT_CSV}) {
		print CSV "\"${indent}\",";
		foreach my $field (@{$CSV_FIELDS}) {
			if(exists($task->{$field})) {
				my $output = $task->{$field};
				$output =~ s/"/""/g;
				print CSV "\"${output}\",";
			} else {
				print CSV "\"${empty}\",";
			};
		};
		print CSV "\n";
	};

	if (${EXPORT_TXT}) {
		if (${indent} !~ /\d+/) {
			print TXT ("=" x 5) . "[ " . $task->{"title"} . " ]" . ("=" x 5) . "\n";
		} else {
			print TXT  ("\t" x (${indent} + 1));
			my $note = ("\t" x (${indent} + 2)) . ("-" x 5);
			my $tabs = ("\t" x (${indent} + 3));

			if ($task->{"completed"}) {
				print TXT "x";
			} elsif ($task->{"deleted"}) {
				print TXT ">";
			} else {
				print TXT "*";
			};

			foreach my $field (qw/
				completed
				due
				title
				notes
			/) {
				if(exists($task->{$field})) {
					my $output = $task->{$field};
					if (${field} eq "due") {
						$output =~ s/T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9A-Z]{4}$//g;
					};
					if (${field} eq "notes") {
						$output =~ s|^(${INDENT}+)|("\t" x (length($1) / 2))|egm;
						$output =~ s/^/${tabs}/gm;
						$output =~ s/^/\n${note}\n/;
					};
					if (${field} ne "notes") {
						print TXT " ";
					};
					print TXT "${output}";
				};
			};

			print TXT "\n";
		};
	};

	return(0);
};

################################################################################

if (@{ARGV}) {
	if (${ARGV[0]} eq "twexport" || ${ARGV[0]} eq "taskwarrior") {
		shift;
		&refresh_tokens();
		&taskwarrior_export(@{ARGV});
	}
	elsif (${ARGV[0]} eq "twimport") {
		shift;
		&refresh_tokens();
		&taskwarrior_import(@{ARGV});
	}
	elsif (${ARGV[0]} eq "search") {
		shift;
		&refresh_tokens();
		&search_regex(@{ARGV});
	}
	elsif (${ARGV[0]} eq "links") {
		shift;
		&refresh_tokens();
		&manage_links(@{ARGV});
	}
	elsif (${ARGV[0]} eq "cruft") {
		shift;
		&refresh_tokens();
		&manage_cruft(@{ARGV});
	}
	elsif (${ARGV[0]} eq "purge") {
		shift;
		&refresh_tokens();
		&purge_lists(@{ARGV});
	}
	elsif (defined(${ARGV[0]}) && defined(${ARGV[1]})) {
		&refresh_tokens();
		&edit_notes(@{ARGV});
	}
	else {
		print STDERR "\n";
		print STDERR "INVALID ARGUMENTS!\n";
		&EXIT(1);
	};
}

########################################

else {
	&refresh_tokens();
	&export_files(@{ARGV});
};

########################################

&EXIT(0);

################################################################################
# end of file
################################################################################
