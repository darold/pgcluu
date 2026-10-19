#!/usr/bin/perl
#------------------------------------------------------------------------------
# Cluster wide totals (issue #156): the total of a report must always be the
# sum of the per database (or per tablespace) values, even when the same csv
# line is read twice or when two lines have the same timestamp. Before the
# fix the per database value was overwritten but the total was summed twice,
# the cluster graphs showed twice the real value. The conflicts, stored as
# deltas, were also summed twice for each database.
#
# Data, at each snapshot:
#   database sizes        db1 1000, db2 2000                  -> total 3000
#   connections           db1 10 (2 active, 1 idle in xact),
#                         db2 20 (4 active, 1 idle in xact)   -> active 6,
#                                                                idle 22
#   tablespace sizes      pg_default 1000, pg_global 2000     -> total 3000
#   prepared transactions db1 1 (oldest 30), db2 2 (oldest 50)-> 3, oldest 50
#   buffercache           db1 10%, db2 20% of shared buffers  -> 30%
#   conflicts             lock counter of db1 +1, db2 +2      -> deltas 1, 2
#                                                                and 3
#
# Cases:
#   - static report on data with duplicated timestamps (DST change, the
#     timezone offset is not part of the timestamp key),
#   - cache built by two overlapping runs of pgcluu -C: the second run read
#     the offsets before the first one rewrote the statistics,
#   - pgcluu.cgi with a trailing slash in INPUT_DIR: the offsets stored in
#     the cache are not found and the csv files are read again.
#------------------------------------------------------------------------------
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Test::More;
use File::Copy qw(copy);
use File::Path qw(make_path);
use PgcluuTest;

my $root = root_dir();

# Lines written at each snapshot, $n is the number of the snapshot
my %CSV = (
	'pg_database_size.csv' => sub { my ($t, $n) = @_; (
		"$t;16384;db1;1000", "$t;16385;db2;2000") },
	'pg_stat_connections.csv' => sub { my ($t, $n) = @_; (
		"$t;10;2;0;1;db1", "$t;20;4;0;1;db2") },
	'pg_tablespace_size.csv' => sub { my ($t, $n) = @_; (
		"$t;pg_default;1000;/data/base", "$t;pg_global;2000;/data/global") },
	'pg_prepared_xact.csv' => sub { my ($t, $n) = @_; (
		"$t;db1;1;30", "$t;db2;2;50") },
	'pg_database_buffercache.csv' => sub { my ($t, $n) = @_; (
		"$t;db1;100;800 kB;10;5", "$t;db2;200;1600 kB;20;7") },
	'pg_stat_database_conflicts.csv' => sub { my ($t, $n) = @_; (
		"$t;16384;db1;0;" . ($n * 1) . ";0;0;0;0",
		"$t;16385;db2;0;" . ($n * 2) . ";0;0;0;0") },
);

# Static report page => [ CGI query (undef: not in the CGI), distinct values ]
# The first point of the conflicts has no previous value, its delta is 0.
my %EXPECTED = (
	'cluster-database-size.html'        => [ 'db=all&action=cluster-size', [ 1000, 2000, 3000 ] ],
	'cluster-database-connections.html' => [ 'db=all&action=cluster-connections', [ 0, 2, 6, 22 ] ],
	'cluster-tablespace-size.html'      => [ 'db=all&action=tablespace-size', [ 1000, 2000, 3000 ] ],
	'cluster-database-prepared.html'    => [ undef, [ 3, 50 ] ],
	'cluster-buffersused.html'          => [ 'db=all&action=cluster-buffersused', [ 10, 20, 30 ] ],
	'cluster-database-conflicts.html'   => [ 'db=all&action=cluster-conflicts', [ 0, 3 ] ],
	'database-conflict-db1.html'        => [ 'db=db1&action=database-conflicts', [ 0, 1 ] ],
	'database-conflict-db2.html'        => [ 'db=db2&action=database-conflicts', [ 0, 2 ] ],
);
my @CGI_PAGES = grep { defined $EXPECTED{$_}[0] } sort keys %EXPECTED;

# Write the snapshots of all the csv files, $n is the number of the first one
sub write_csv
{
	my ($dir, $n, @times) = @_;

	foreach my $f (sort keys %CSV)
	{
		open(my $fh, '>>', "$dir/$f") or die "FATAL: can not write $dir/$f, $!\n";
		my $i = $n;
		foreach my $t (@times) {
			print $fh "$_\n" foreach ($CSV{$f}->($t, $i++));
		}
		close($fh);
	}
}

# Distinct values of the data points of a page
sub graph_values
{
	my $html = shift;
	my %seen = ();
	return sort { $a <=> $b } grep { !$seen{$_}++ } ($html =~ /\[\d{13},(-?[\d.]+)\]/g);
}

sub check_values
{
	my ($html, $page, $label) = @_;
	my @got = graph_values($html);
	is_deeply(\@got, $EXPECTED{$page}[1], "$label: $page shows the right values")
		or diag("values found: @got");
}

# Build a report, $subdir is where the pages are written: with a directory of
# daily subdirectories the report is built in the same subdirectories.
sub check_report
{
	my ($dir, $label, $subdir) = @_;

	my $out = tmp_dir();
	my ($rc, $o, $err) = run_cmd($^X, "$root/pgcluu", '-S', '-o', $out, $dir);
	is($rc, 0, "$label: pgcluu report") or diag($err);
	$out .= "/$subdir" if ($subdir);
	foreach my $page (sort keys %EXPECTED)
	{
		my $html = do { local $/; open(my $fh, '<', "$out/$page") or die "$out/$page: $!"; <$fh> };
		check_values($html, $page, $label);
	}
}

sub check_cgi
{
	my ($input_dir, $label) = @_;

	my $cgi = cgi_install($input_dir);
	foreach my $page (@CGI_PAGES)
	{
		my $q = $EXPECTED{$page}[0];
		my ($rc, $out, $err) = cgi_run($cgi, $q);
		ok($rc == 0 && $err eq '', "$label: $q runs without error") or diag($err);
		check_values($out, $page, "$label $q");
	}
}

(my $day = $PgcluuTest::FIXTURE_DAY) =~ s#/#-#g;

#### Duplicated timestamps: the hour repeated by a DST change
{
	my $data = tmp_dir();
	write_csv($data, 0, '2026-10-25 01:50:00+02', '2026-10-25 02:10:00+02',
		'2026-10-25 02:10:00+01', '2026-10-25 03:10:00+01');
	check_report($data, 'duplicated timestamps');
}

#### Overlapping runs of pgcluu -C
{
	my $base = tmp_dir();
	my $data = "$base/$PgcluuTest::FIXTURE_DAY";
	make_path($data);

	write_csv($data, 0, "$day 08:00:00+00");
	my ($rc, $o, $err) = run_cmd($^X, "$root/pgcluu", '-S', '-C', $base);
	is($rc, 0, 'first cache pass') or diag($err);
	copy("$data/global_infos.bin", "$base/old_global_infos.bin") or die;

	write_csv($data, 1, "$day 08:05:00+00", "$day 08:10:00+00");
	($rc, $o, $err) = run_cmd($^X, "$root/pgcluu", '-S', '-C', $base);
	is($rc, 0, 'second cache pass') or diag($err);

	# A third run started before the second one has rewritten the cache:
	# it got the old offsets but the new statistics.
	copy("$base/old_global_infos.bin", "$data/global_infos.bin") or die;
	($rc, $o, $err) = run_cmd($^X, "$root/pgcluu", '-S', '-C', $base);
	is($rc, 0, 'overlapping cache pass') or diag($err);

	check_report($base, 'overlapping cache runs', $PgcluuTest::FIXTURE_DAY);

	SKIP: {
		skip('CGI.pm is not installed', 2 * @CGI_PAGES) if (!have_cgi_pm());
		check_cgi($base, 'overlapping cache runs (cgi)');
	}
}

#### CGI with a trailing slash in INPUT_DIR
SKIP: {
	skip('CGI.pm is not installed', 2 * @CGI_PAGES) if (!have_cgi_pm());

	my $base = tmp_dir();
	my $data = "$base/$PgcluuTest::FIXTURE_DAY";
	make_path($data);
	write_csv($data, 0, "$day 08:00:00+00", "$day 08:05:00+00");
	my ($rc, $o, $err) = run_cmd($^X, "$root/pgcluu", '-S', '-C', $base);
	die "FATAL: pgcluu -C failed: $err\n" if ($rc != 0);

	check_cgi("$base/", 'trailing slash in INPUT_DIR (cgi)');
}

done_testing();
