#!/usr/bin/perl
#------------------------------------------------------------------------------
# Cluster wide totals of the database sizes and of the connections (issue
# #156): the total must always be the sum of the per database values, even
# when the same csv line is read twice or when two lines have the same
# timestamp. Before the fix the per database value was overwritten but the
# total was summed twice, the cluster graphs showed twice the real value.
#
# Data: two databases, db1 (size 1000, 10 connections: 2 active, 1 idle in
# transaction) and db2 (size 2000, 20 connections: 4 active, 1 idle in
# transaction) at each snapshot. Expected cluster values: size 3000,
# active 6, idle 22, idle in transaction 2, waiting 0.
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

my @DBS = (
	# oid, name, size, total, active, waiting, idle_in_xact
	[ 16384, 'db1', 1000, 10, 2, 0, 1 ],
	[ 16385, 'db2', 2000, 20, 4, 0, 1 ],
);
my %EXPECTED = (
	'cluster-database-size.html'        => [ 1000, 2000, 3000 ],  # db1, db2, all
	'cluster-database-connections.html' => [ 0, 2, 6, 22 ],       # waiting, idle_in_xact, active, idle
);
my %CGI_ACTION = (
	'cluster-database-size.html'        => 'cluster-size',
	'cluster-database-connections.html' => 'cluster-connections',
);

# Write one snapshot of both files per timestamp
sub write_csv
{
	my ($dir, $append, @times) = @_;

	my $mode = $append ? '>>' : '>';
	open(my $sz, $mode, "$dir/pg_database_size.csv") or die;
	open(my $cn, $mode, "$dir/pg_stat_connections.csv") or die;
	foreach my $t (@times)
	{
		foreach my $d (@DBS)
		{
			print $sz "$t;$d->[0];$d->[1];$d->[2]\n";
			print $cn "$t;$d->[3];$d->[4];$d->[5];$d->[6];$d->[1]\n";
		}
	}
	close($sz);
	close($cn);
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
	is_deeply(\@got, $EXPECTED{$page}, "$label: $page shows the right cluster total")
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

# Install the CGI with its own configuration file
sub cgi_install
{
	my $input_dir = shift;

	my $tmp = tmp_dir();
	open(my $fh, '>', "$tmp/pgcluu.conf") or die;
	print $fh "INPUT_DIR $input_dir\n";
	close($fh);
	my $src = do { local $/; open(my $in, '<', "$root/cgi-bin/pgcluu.cgi") or die; <$in> };
	$src =~ s{^my \$CONFIG_FILE\s*=\s*"[^"]*";}{my \$CONFIG_FILE = "$tmp/pgcluu.conf";}m or die;
	open($fh, '>', "$tmp/pgcluu.cgi") or die;
	print $fh $src;
	close($fh);

	return "$tmp/pgcluu.cgi";
}

sub check_cgi
{
	my ($input_dir, $label) = @_;

	my $cgi = cgi_install($input_dir);
	foreach my $page (sort keys %EXPECTED)
	{
		my ($rc, $out, $err) = cgi_run($cgi, "db=all&action=$CGI_ACTION{$page}");
		is($rc, 0, "$label: $CGI_ACTION{$page} runs") or diag($err);
		check_values($out, $page, $label);
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
		skip('CGI.pm is not installed', 2 * keys %EXPECTED) if (!have_cgi_pm());
		check_cgi($base, 'overlapping cache runs (cgi)');
	}
}

#### CGI with a trailing slash in INPUT_DIR
SKIP: {
	skip('CGI.pm is not installed', 2 * keys %EXPECTED) if (!have_cgi_pm());

	my $base = tmp_dir();
	my $data = "$base/$PgcluuTest::FIXTURE_DAY";
	make_path($data);
	write_csv($data, 0, "$day 08:00:00+00", "$day 08:05:00+00");
	my ($rc, $o, $err) = run_cmd($^X, "$root/pgcluu", '-S', '-C', $base);
	die "FATAL: pgcluu -C failed: $err\n" if ($rc != 0);

	check_cgi("$base/", 'trailing slash in INPUT_DIR (cgi)');
}

done_testing();
