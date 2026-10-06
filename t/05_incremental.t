#!/usr/bin/perl
#------------------------------------------------------------------------------
# Incremental mode: statistics are cached with pgcluu -C, then new lines are
# appended to the csv files and pgcluu -C is run again before generating the
# report from the cache. The result is compared with a report built at once.
#
# All pages must be identical, except the known differences listed in
# %KNOWN_DIFF (TODO tests): one point is lost at the boundary for the
# statistics computed as deltas and the tablespace sizes are duplicated.
# The pg_stat_io reports keep the last raw values in the cache and have no
# such difference.
#------------------------------------------------------------------------------
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Test::More;
use File::Basename qw(basename);
use PgcluuTest;

my $root = root_dir();

# Pages with known differences in incremental mode
my %KNOWN_DIFF = map { $_ => 1 } qw(
	cluster-bgwriter_count.html cluster-bgwriter_read.html cluster-bgwriter_write.html
	cluster-checkpoints.html cluster-checkpoints_time.html cluster-database-backends.html
	cluster-database-cache_ratio.html cluster-database-canceled_queries.html
	cluster-database-commits_rollbacks.html cluster-database-deadlocks.html
	cluster-database-read_ratio.html cluster-database-read_write_query.html
	cluster-database-temporary_bytes.html cluster-database-temporary_files.html
	cluster-database-transactions.html cluster-database-write_ratio.html
	cluster-tablespace-size.html database-conflict-postgres.html database-conn-postgres.html
	database-io-postgres.html database-lock-postgres.html database-postgres.html
	database-tmpf-postgres.html database-tx-postgres.html
);
my $fixture = 'pg18';
my $src = fixture_dir($fixture);

# Split time: 5th snapshot of pg_stat_database.csv
open(my $fh, '<', "$src/pg_stat_database.csv") or die;
my %times = map { (split(/;/))[0] => 1 } <$fh>;
close($fh);
my $split = (sort keys %times)[4];
ok($split, "split time found: $split");

# First part of the csv files, other files as is
my $data = tmp_dir();
opendir(my $dh, $src) or die;
my @files = grep { -f "$src/$_" } readdir($dh);
closedir($dh);
foreach my $f (@files)
{
	open(my $in, '<', "$src/$f") or die;
	open(my $out, '>', "$data/$f") or die;
	while (my $l = <$in>) {
		print $out $l if ($f !~ /\.csv$/ || (split(/;/, $l))[0] lt $split);
	}
	close($in);
	close($out);
}
my ($rc, $o, $err) = run_cmd($^X, "$root/pgcluu", '-S', '-C', $data);
is($rc, 0, 'cache built with the first part') or diag($err);

# Append the second part and update the cache
foreach my $f (grep { /\.csv$/ } @files)
{
	open(my $in, '<', "$src/$f") or die;
	open(my $out, '>>', "$data/$f") or die;
	while (my $l = <$in>) {
		print $out $l if ((split(/;/, $l))[0] ge $split);
	}
	close($in);
	close($out);
}
($rc, $o, $err) = run_cmd($^X, "$root/pgcluu", '-S', '-C', $data);
is($rc, 0, 'cache updated with the second part') or diag($err);

my $incr = tmp_dir();
($rc, $o, $err) = run_cmd($^X, "$root/pgcluu", '-S', '-o', $incr, $data);
is($rc, 0, 'report generated from the cache') or diag($err);

my $full = tmp_dir();
($rc, $o, $err) = run_cmd($^X, "$root/pgcluu", '-S', '-o', $full, $src);
is($rc, 0, 'report generated at once') or diag($err);

my $r_incr = normalize_report_dir($incr);
my $r_full = normalize_report_dir($full);
is_deeply([sort keys %{$r_incr}], [sort keys %{$r_full}], 'same list of pages');

foreach my $page (sort keys %{$r_full})
{
	TODO: {
		local $TODO = 'known limitation of the incremental mode' if ($KNOWN_DIFF{$page});
		is_deeply($r_incr->{$page}, $r_full->{$page}, "$page: identical in incremental mode");
	}
}

done_testing();
