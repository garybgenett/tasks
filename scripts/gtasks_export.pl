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
# http://search.cpan.org/~makamaka/JSON-2.53/lib/JSON.pm
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

################################################################################

my $FILE		= "tasks";
my $DEFAULT_LIST	= "0.GTD";

my $SCOPE		= "https://www.googleapis.com/auth/tasks";
my $URL			= "https://www.googleapis.com/tasks/v1";

########################################

my $MANAGE_CRUFT	= "1";
my $MANAGE_CRUFT_ALL	= "1";

my $EXPORT_JSON		= "1";
my $EXPORT_CSV		= "1";
my $EXPORT_TXT		= "1";

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

########################################

our $USERNAME;
our $PASSWORD;
our $CLIENTID;
our $CLSECRET;
our $REDIRECT;
do(".auth");

our $CODE;
our $REFRESH;
our $ACCESS;
do(".token");

################################################################################

sub refresh_tokens {
	if (!${CODE} || !${REFRESH}) {
		$mech->get("https://accounts.google.com/ServiceLogin");
		$mech->form_id("gaia_loginform");
		$mech->field("Email",	${USERNAME});
		$mech->field("Passwd",	${PASSWORD});
		$mech->submit();

		$mech->get("https://accounts.google.com/o/oauth2/auth"
			. "?client_id=${CLIENTID}"
			. "&redirect_uri=${REDIRECT}"
			. "&scope=${SCOPE}"
			. "&response_type=code"
		);
		$mech->submit_form(
			"form_id"	=> "submit_access_form",
			"fields"	=> {"submit_access" => "true"},
		);
		$CODE = $mech->content();
		$CODE =~ s|^.*<input id="code" type="text" readonly="readonly" value="||s;
		$CODE =~ s|".*$||s;

		$mech->post("https://accounts.google.com/o/oauth2/token", {
			"code"			=> ${CODE},
			"client_id"		=> ${CLIENTID},
			"client_secret"		=> ${CLSECRET},
			"redirect_uri"		=> ${REDIRECT},
			"grant_type"		=> "authorization_code",
		});
		$REFRESH = decode_json($mech->content());
		$REFRESH = $REFRESH->{"refresh_token"};
	};

	$mech->post("https://accounts.google.com/o/oauth2/token", {
		"refresh_token"		=> ${REFRESH},
		"client_id"		=> ${CLIENTID},
		"client_secret"		=> ${CLSECRET},
		"grant_type"		=> "refresh_token",
	});
	$ACCESS = decode_json($mech->content());
	$ACCESS = $ACCESS->{"access_token"};

	open(OUTPUT, ">", ".token");
	print OUTPUT "our \$CODE    = '${CODE}';\n";
	print OUTPUT "our \$REFRESH = '${REFRESH}';\n";
	close(OUTPUT);

	print "CODE:    ${CODE}\n";
	print "REFRESH: ${REFRESH}\n";
	print "ACCESS:  ${ACCESS}\n";

	$mech->add_header("Authorization" => "Bearer ${ACCESS}");

	return(0);
};

########################################

sub manage_cruft {
	(!${MANAGE_CRUFT}) && (return(0));
	my $output;

	print "\n";

	$mech->get("${URL}/users/\@me/lists"
		. "?maxResults=1000000"
	) && $API_REQUEST_COUNT++;
	$output = decode_json($mech->content());

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

	$mech->get("${URL}/lists/${listid}/tasks"
		. "?maxResults=1000000"
		. "&showCompleted=true"
		. "&showDeleted=true"
		. "&showHidden=true"
	);
	$output = decode_json($mech->content());

	foreach my $task (@{$output->{"items"}}) {
#>>> BUG IN GOOGLE TASKS API!
#>>> http://code.google.com/a/google.com/p/apps-api-issues/issues/detail?id=2888
#>>> SHOULD JUST BE ABLE TO MOVE THEM TO A "PURGE" LIST FOR MANUAL DELETION
		if ($task->{"title"} =~ "\n") {
			$task->{"title"} =~ s/\n//g;
			printf("%-10.10s %-50.50s %s\n", "rescuing:", $task->{"id"}, $task->{"title"} || "-");
		};

		if (	$task->{"title"} ne "0"	&&
			!$task->{"title"}	&&
			!$task->{"notes"}	&&
			!$task->{"due"}
		) {
			printf("%-10.10s %-50.50s %s\n", "clearing:", $task->{"id"}, $task->{"title"} || "-");
			$mech->request(HTTP::Request->new(
				"PATCH", $task->{"selfLink"}, ["Content-Type", "application/json"], encode_json({
					"title"		=> "0",
					"status"	=> "needsAction",
					"completed"	=> undef,
					"deleted"	=> "0",
				})
			));
		};

		if ((	!$task->{"title"}	&& (
			$task->{"notes"}	||
			$task->{"due"}		)
			$task->{"deleted"}
		)) {
			printf("%-10.10s %-50.50s %s\n", "reviving:", $task->{"id"}, $task->{"title"} || "-");
			$mech->request(HTTP::Request->new(
				"PATCH", $task->{"selfLink"}, ["Content-Type", "application/json"], encode_json({
					"title"		=> "[" . sprintf("%.3d", int(rand(10**3))) . "]:[$task->{'title'}]",
					"status"	=> "needsAction",
					"completed"	=> undef,
					"deleted"	=> "0",
				})
			));
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

	$mech->get("${URL}/users/\@me/lists"
		. "?maxResults=1000000"
	);
	$output = decode_json($mech->content());
	if (${EXPORT_JSON}) {
		print JSON ("#" x 5) . "[ LISTS ]" . ("#" x 5) . "\n\n";
		print JSON $mech->content();
		print JSON "\n";
	};

#>>> BUG IN PERL!
#>>> http://www.perlmonks.org/?node_id=490213
	my @array = @{$output->{"items"}};
	foreach my $tasklist (sort({$a->{"title"} cmp $b->{"title"}} @{array})) {
#>>>
		$mech->get("${URL}/lists/$tasklist->{'id'}/tasks"
			. "?maxResults=1000000"
			. "&showCompleted=true"
			. "&showDeleted=true"
			. "&showHidden=true"
		);
		$output = decode_json($mech->content());
		$tasklist->{"title"} .= " (" . ($#{$output->{"items"}} + 1) . ")";
		if (${EXPORT_JSON}) {
			print JSON ("#" x 5) . "[ $tasklist->{'title'} ]" . ("#" x 5) . "\n\n";
			print JSON $mech->content();
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

	foreach $key (keys($tree)) {
		if (!exists($tree->{$key}->{"pos"})) {
			$tree->{$key}->{"pos"} = "";
		};
	};

	foreach $key (sort({$tree->{$a}{"pos"} cmp $tree->{$b}{"pos"}} keys($tree))) {
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
				$output =~ s/^"//g;
				$output =~ s/"$//g;
				print CSV "\"${output}\",";
			} else {
				print CSV "\"${empty}\",";
			};
		};
		print CSV "\n";
	};

	if (${EXPORT_TXT}) {
		if (${indent} !~ /\d+/) {
			print TXT ("=" x 5) . "[ $task->{'title'} ]" . ("=" x 5) . "\n";
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
						$output =~ s|^([ ]+)|("\t" x (length(${1}) / 2))|egm;
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

&refresh_tokens();
&manage_cruft();
&export_files();

########################################

if (${EXPORT_TXT}) {
	open(TXT, "<", "${FILE}.txt") || die();
	print <TXT>;
	close(TXT) || die();
};

########################################

exit(0);
################################################################################
# end of file
################################################################################
