#!/usr/bin/env perl
use strict;
use warnings;
################################################################################
# https://developers.google.com/accounts/docs/OAuth2InstalledApp
# https://developers.google.com/google-apps/tasks/v1/reference
################################################################################
# http://search.cpan.org/~jesse/WWW-Mechanize-1.72/lib/WWW/Mechanize.pm
# http://search.cpan.org/~gaas/libwww-perl-6.04/lib/LWP/UserAgent.pm
# http://search.cpan.org/~gaas/HTTP-Message-6.06/lib/HTTP/Request.pm
# http://search.cpan.org/~makamaka/JSON-PP-2.27201/lib/JSON/PP.pm
# http://search.cpan.org/~tjenness/File-Temp-0.22/Temp.pm
################################################################################

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
	"agent" => "Mozilla/5.0",
);

use HTTP::Request;
use JSON::PP;
my $json = JSON::PP->new();

use File::Temp qw(tempfile);
use MIME::Base64;

################################################################################

my $FILE		= "tasks";
my $DEFAULT_LIST	= "0.GTD";
my $PROJECT_LIST	= "0.Projects";

my $PROJ_LINK_NORMAL	= "*";
my $PROJ_LINK_OPEN	= "=";
my $PROJ_LINK_CLOSED	= "x";
my $PROJ_LINK_SEPARATE	= ": ";

my $INDENT		= " ";

my $SCOPE		= "https://www.googleapis.com/auth/tasks";
my $URL			= "https://www.googleapis.com/tasks/v1";

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

#>>> JSON:PP Methods

	$json->loose(0);

	$json->escape_slash(0);
	$json->indent_length(1);

	$json->sort_by(sub {
		my $order = {};
		#>>> http://learn.perl.org/faq/perlfaq4.html#How-do-I-merge-two-hashes-
		@{ $order }{@{ $JSON_FIELDS }} = 0..$#{ $JSON_FIELDS };
		if (exists($order->{$JSON::PP::a}) && exists($order->{$JSON::PP::b})) {
			$order->{$JSON::PP::a} <=> $order->{$JSON::PP::b};
		} else {
			$JSON::PP::a cmp $JSON::PP::b;
		};
	});

########################################

our $USERNAME;
our $PASSWORD;
our $CLIENTID;
our $CLSECRET;
our $REDIRECT;
do(".auth") || die();

our $CODE;
our $REFRESH;
our $ACCESS;
do(".token") || die();

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

sub refresh_tokens {
	if (!${CODE} || !${REFRESH}) {
		$mech->get("https://accounts.google.com/ServiceLogin") && $API_REQUEST_COUNT++;
		$mech->form_id("gaia_loginform");
		$mech->field("Email",	${USERNAME});
		$mech->field("Passwd",	${PASSWORD});
		$mech->submit() && $API_REQUEST_COUNT++;

		$mech->get("https://accounts.google.com/o/oauth2/auth"
			. "?client_id=${CLIENTID}"
			. "&redirect_uri=${REDIRECT}"
			. "&scope=${SCOPE}"
			. "&response_type=code"
		) && $API_REQUEST_COUNT++;
		$mech->submit_form(
			"form_id"	=> "connect-approve",
			"fields"	=> {"submit_access" => "true"},
		) && $API_REQUEST_COUNT++;
		$CODE = $mech->content();
		$CODE =~ s|^.*<input id="code" type="text" readonly="readonly" value="||s;
		$CODE =~ s|".*$||s;

		$mech->post("https://accounts.google.com/o/oauth2/token", {
			"code"			=> ${CODE},
			"client_id"		=> ${CLIENTID},
			"client_secret"		=> ${CLSECRET},
			"redirect_uri"		=> ${REDIRECT},
			"grant_type"		=> "authorization_code",
		}) && $API_REQUEST_COUNT++;
		$REFRESH = decode_json($mech->content());
		$REFRESH = $REFRESH->{"refresh_token"};

		open(OUTPUT, ">", ".token") || die();
		print OUTPUT "our \$CODE    = '${CODE}';\n";
		print OUTPUT "our \$REFRESH = '${REFRESH}';\n";
		close(OUTPUT) || die();
	};

	$mech->post("https://accounts.google.com/o/oauth2/token", {
		"refresh_token"		=> ${REFRESH},
		"client_id"		=> ${CLIENTID},
		"client_secret"		=> ${CLSECRET},
		"grant_type"		=> "refresh_token",
	}) && $API_REQUEST_COUNT++;
	$ACCESS = decode_json($mech->content());
	$ACCESS = $ACCESS->{"access_token"};

	print "CODE:    ${CODE}\n";
	print "REFRESH: ${REFRESH}\n";
	print "ACCESS:  ${ACCESS}\n";

	$mech->add_header("Authorization" => "Bearer ${ACCESS}");

	return(0);
};

################################################################################

sub api_create_list {
	my $fields = shift;
	my $output = &api_post("${URL}/users/\@me/lists", ${fields});
	return(${output});
};

########################################

sub api_fetch_lists {
	my $output = &api_get("${URL}/users/\@me/lists");
	return(${output});
};

########################################

sub api_create_task {
	my $listid	= shift;
	my $fields	= shift;
	my $url = "${URL}/lists/${listid}/tasks";
	$url .= "?parent=" . ($fields->{"parent"} || "") . "&previous=" . ($fields->{"previous"} || "");
	my $output = &api_post(${url}, ${fields});
	return(${output});
};

########################################

sub api_fetch_tasks {
	my $listid	= shift;
	my $output = &api_get("${URL}/lists/${listid}/tasks", {
		"showCompleted"		=> "true",
		"showDeleted"		=> "true",
		"showHidden"		=> "true",
	});
	return(${output});
};

########################################

sub api_get {
	my $url		= shift;
	my $fields	= shift;
	my $output;
	my $page;

#>>> BUG IN GOOGLE TASKS API!
#>>> http://code.google.com/a/google.com/p/apps-api-issues/issues/detail?id=2837
#>>> SHOULD BE ABLE TO REQUEST AN ARBITRARY AMOUNT
	$url .= "?maxResults=100";

	if (defined(${fields})) {
		foreach my $field (keys(${fields})) {
			$url .= "&" . ${field} . "=" . $fields->{$field};
		};
	};

	do {
		$mech->get("${url}"
			. (defined(${page}) ? "&pageToken=${page}" : "")
		) && $API_REQUEST_COUNT++;
		my $out = decode_json($mech->content());

		#>>> http://www.perlmonks.org/?node_id=995613
		foreach my $key (keys(${out})) {
			if (exists($output->{$key}) && $output->{$key} ne $out->{$key}) {
				if (ref($output->{$key}) eq "ARRAY") {
					push(@{$output->{$key}}, @{$out->{$key}});
				} else {
					$output->{$key} = [ ${API_ERROR}, $output->{$key}, $out->{$key} ];
				};
			} else {
				$output->{$key} = $out->{$key};
			};
		}

		$page = $out->{"nextPageToken"};
		delete($out->{"nextPageToken"});
		delete($output->{"nextPageToken"});
		$output->{$API_PAGES}++;
	}
	until (!defined(${page}));

	return(${output});
};

########################################

sub api_move {
	my $selflink	= shift;
	my $fields	= shift;
	$selflink .= "/move?parent=" . ($fields->{"parent"} || "") . "&previous=" . ($fields->{"previous"} || "");
	my $output = &api_post(${selflink}, {});
	return(${output});
};

########################################

sub api_patch {
	my $selflink	= shift;
	my $fields	= shift;
	if (exists($fields->{"parent"}) || exists($fields->{"previous"})) {
		my $output = &api_move(${selflink}, ${fields});
		$selflink = $output->{"selfLink"};
	};
	$mech->request(HTTP::Request->new(
		"PATCH", ${selflink}, ["Content-Type", "application/json"], encode_json(${fields}),
	)) && $API_REQUEST_COUNT++;
	return(decode_json($mech->content()));
};

########################################

sub api_delete {
	my $selflink	= shift;
	my $fields	= shift;
	$mech->request(HTTP::Request->new(
		"DELETE", ${selflink}, ["Content-Type", "application/json"], encode_json(${fields}),
	)) && $API_REQUEST_COUNT++;
	return(decode_json($mech->content()));
};

########################################

sub api_post {
	my $selflink	= shift;
	my $fields	= shift;
	$mech->request(HTTP::Request->new(
		"POST", ${selflink}, ["Content-Type", "application/json"], encode_json(${fields}),
	)) && $API_REQUEST_COUNT++;
	return(decode_json($mech->content()));
};

################################################################################

sub taskwarrior_export {
	my $title	= shift;
	my $tasks	= shift || "";
	my $field_one	= shift || "description";
	my $field_two	= shift || "entry";
	my $links	= [];
	my $previous	= undef;
	my $created;
	my $listid;
	my $output;

	my($default_one, $default_two);
	($field_one, $default_one) = split(",", $field_one);
	($field_two, $default_two) = split(",", $field_two);

	$tasks = qx(task export "${tasks}");
	$tasks = decode_json("[${tasks}]");

	$output = &api_fetch_lists();

	foreach my $tasklist (@{$output->{"items"}}) {
		if ($tasklist->{"title"} eq ${title}) {
			$created = "1";
			$listid = $tasklist->{"id"};

			$output = &api_fetch_tasks($tasklist->{"id"});

			foreach my $task (@{$output->{"items"}}) {
				push(@{$links}, $task->{"selfLink"});
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
	foreach my $task (sort({
		((
			($a->{$field_one} || ${default_one}) cmp ($b->{$field_one} || ${default_one})
		) || (
			($a->{$field_two} || ${default_two}) cmp ($b->{$field_two} || ${default_two})
		) || (
			$a->{"description"} cmp $b->{"description"}
		) || (
			$a->{"entry"} cmp $b->{"entry"}
		));
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
		my $blob = {
			"title"		=> $task->{"description"},
			"status"	=> $task->{"status"},
			"due"		=> $task->{"due"},
			"completed"	=> $task->{"end"},
			"deleted"	=> $task->{"deleted"},
			"notes"		=> $task->{"notes"},
			"parent"	=> undef,
			"previous"	=> ${previous},
		};
		if (@{$links}) {
			$output = &api_patch(shift(@{$links}), ${blob});
			$previous = $output->{"id"};
			print "=";
		} else {
			$output = &api_create_task(${listid}, ${blob});
			$previous = $output->{"id"};
			print "+";
		};
	};

	while (@{$links}) {
		$output = &api_patch(shift(@{$links}), {
			"title"		=> "0",
			"status"	=> "needsAction",
			"due"		=> undef,
			"completed"	=> undef,
			"deleted"	=> "true",
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

sub edit_notes {
	my $argv_list	= shift;
	my $argv_name	= shift;
	my $selflink;
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
					$selflink = $task->{"selfLink"};
					last();
				};
			};

			last();
		};
	};

	if (!${selflink}) {
		print STDERR "\n";
		print STDERR "DOES NOT EXIST!\n";
		&EXIT(1);
	} else {
		$output = &api_get(${selflink});
		$output = &edit_notes_text($output->{"notes"});

		if ($output) {
			&refresh_tokens();
			&api_patch(${selflink}, {
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

	foreach my $key (sort({$a cmp $b} keys($links->{$MLINK_SRC}))) {
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
	foreach my $key (sort({$a cmp $b} keys($links->{$MLINK_DST}))) {
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
	foreach my $key (sort({$a cmp $b} keys($links->{"NONE_$MLINK_DST"}))) {
		print "\t${key}\n";
		foreach my $val (@{$links->{"NONE_$MLINK_DST"}->{ $key }}) {
			print "\t\t${val}\n";
		};
	};
	print "NO ${MLINK_SRC}\n";
	foreach my $key (sort({$a cmp $b} keys($links->{"NONE_$MLINK_SRC"}))) {
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
			&api_patch($task->{"selfLink"}, {
				"title"		=> $task->{"title"},
			});
		};

		if (	$task->{"title"} ne "0"	&&
			!$task->{"title"}	&&
			!$task->{"notes"}	&&
			!$task->{"due"}
		) {
			printf("%-10.10s %-50.50s %s\n", "clearing:", $task->{"id"}, $task->{"title"} || "-");
			&api_patch($task->{"selfLink"}, {
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
			&api_patch($task->{"selfLink"}, {
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

	foreach $key (keys(${tree})) {
		if (!exists($tree->{$key}->{"pos"})) {
			$tree->{$key}->{"pos"} = "";
		};
	};

	foreach $key (sort({$tree->{$a}{"pos"} cmp $tree->{$b}{"pos"}} keys(${tree}))) {
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
	if (${ARGV[0]} eq "taskwarrior") {
		shift;
		&refresh_tokens();
		&taskwarrior_export(@{ARGV});
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
