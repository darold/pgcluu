#!/usr/bin/perl
#------------------------------------------------------------------------------
# pgcluu.cgi on the fixtures.
#
# Every action of the menu (plus home, sysinfo and the pg_stat_io graphs called
# alone) is run in two modes: from the csv files only and from the cache files
# built by pgcluu -C. For each action:
#   - the CGI must exit with 0 and write nothing on stderr,
#   - both modes must give the same result, except for the known differences
#     listed in %KNOWN_CSV_DIFF (TODO tests),
#   - the result of the cache mode, the one used in production, is compared
#     with t/expected/cgi-<fixture>.json.
# The pg_stat_io pages must also show the same graphs than the static report.
#------------------------------------------------------------------------------
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Test::More;
use PgcluuTest;

plan skip_all => 'CGI.pm is not installed' if (!have_cgi_pm());

my $root = root_dir();

# Known differences between the csv mode and the cache mode of the CGI. The
# cache files are built by pgcluu, the csv files are parsed by the CGI own
# code which gives different values for the cluster wide statistics of
# pg_stat_database (backends, cache ratio, ...) and for the transactions of
# a database. In cache mode the tablespace sizes are duplicated and the
# archiver statistics are missing from the home page.
my %KNOWN_CSV_DIFF = map { $_ => 1 } qw(
	db=all&action=cluster-backends
	db=all&action=cluster-cache_ratio
	db=all&action=cluster-canceled_queries
	db=all&action=cluster-deadlocks
	db=all&action=cluster-read_ratio
	db=all&action=cluster-temporary_bytes
	db=all&action=cluster-temporary_files
	db=all&action=home
	db=all&action=tablespace-size
	db=postgres&action=database-transactions
);
# Only seen with the PG18 fixture. sysinfo: in csv mode the CGI ignores the
# mount points whose device does not start with a slash (tmpfs, ...), the
# cache built by pgcluu keeps them.
my %KNOWN_CSV_DIFF_FIXTURE = (
	'pg18' => {
		'db=all&action=cluster-read_write_query' => 1,
		'db=all&action=sysinfo' => 1,
	},
);

# pg_stat_io graphs that can be called alone
my $src = do { local $/; open(my $fh, '<', "$root/cgi-bin/pgcluu.cgi") or die; <$fh> };
my %seen = ();
my @io_graphs = grep { !$seen{$_}++ } ($src =~ /'name' =>\s+'(cluster-io_\w+)',\n\t+'page' =>/g);
ok(scalar @io_graphs >= 20, 'pg_stat_io graphs found in pgcluu.cgi');

foreach my $fixture (fixtures())
{
	my %results = ();
	foreach my $mode ('csv', 'bin')
	{
		my $cgi = cgi_setup($fixture, $mode);
		my @actions = cgi_menu_actions($cgi);
		ok(scalar @actions > 50, "$fixture/$mode: actions found in the menu");
		# The links of the System menu have no db parameter, the kernel
		# pages are added explicitly.
		push(@actions, 'db=all&action=home', 'db=all&action=sysinfo', (map { "db=all&action=$_" } @io_graphs),
			(map { "action=$_" } ('kernel-pressure', 'kernel-events', 'kernel-psi_host_some', 'kernel-oom')));

		foreach my $q (@actions)
		{
			my ($rc, $out, $err) = cgi_run($cgi, $q);
			if ($rc != 0 || $err ne '') {
				fail("$fixture/$mode: $q runs without error");
				diag($err);
			}
			$results{$mode}{$q} = normalize_html($out);
		}
	}

	foreach my $q (sort keys %{$results{bin}})
	{
		TODO: {
			local $TODO = 'known difference between the csv and the cache modes' if ($KNOWN_CSV_DIFF{$q} || $KNOWN_CSV_DIFF_FIXTURE{$fixture}{$q});
			is_deeply($results{csv}{$q}, $results{bin}{$q}, "$fixture: $q gives the same result from the csv and the cache files");
		}
	}

	# Consistency with the static report for the pg_stat_io and kernel pages
	my $out = tmp_dir();
	run_cmd($^X, "$root/pgcluu", '-S', '-o', $out, fixture_dir($fixture));
	my $report = normalize_report_dir($out);
	foreach my $page (grep { /^(cluster-io_|kernel-)/ } keys %{$report})
	{
		my $action = $page;
		$action =~ s/\.html$//;
		my $q = ($action =~ /^kernel-/) ? "action=$action" : "db=all&action=$action";
		my @static = map { $_->{data} } @{$report->{$page}{graphs}};
		my @cgi = map { $_->{data} } @{$results{bin}{$q}{graphs}};
		is_deeply(\@cgi, \@static, "$fixture: $action shows the same graphs than the static report");
	}

	check_expected($results{bin}, "cgi-$fixture.json", "$fixture cgi");
}

done_testing();
