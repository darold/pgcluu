#!/usr/bin/perl
#------------------------------------------------------------------------------
# Collect of statistics on a running PostgreSQL server with pgcluu_collectd,
# then report generation with pgcluu.
#
# This test needs a PostgreSQL server and is skipped unless PGCLUU_TEST_LIVE
# is set. Connection uses the standard libpq variables (PGHOST, PGPORT,
# PGUSER, PGPASSWORD, PGDATABASE), the user must be a superuser or a member
# of pg_monitor. Values cannot be compared with expected results, the test
# checks the format of the files following the server version and that the
# reports of this version are generated.
#------------------------------------------------------------------------------
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Test::More;
use PgcluuTest;

plan skip_all => 'set PGCLUU_TEST_LIVE=1 and the PG* connection variables to run this test' if (!$ENV{PGCLUU_TEST_LIVE});

my $root = root_dir();
my @psql = ('psql', '-X', '-At', '-v', 'ON_ERROR_STOP=1', '-d', $ENV{PGDATABASE} || 'postgres');

my ($rc, $out, $err) = run_cmd(@psql, '-c', 'SHOW server_version_num');
if ($rc != 0) {
	BAIL_OUT("can not connect to PostgreSQL: $err");
}
chomp($out);
my $major = int($out / 10000);
note("PostgreSQL server version $out, major $major");

# Workload running during the collect
my $workload = <<'EOS';
CREATE TABLE IF NOT EXISTS pgcluu_test_t (id int, val text);
INSERT INTO pgcluu_test_t SELECT g, md5(g::text) FROM generate_series(1, 50000) g;
SELECT count(*) FROM pgcluu_test_t;
UPDATE pgcluu_test_t SET val = md5(val) WHERE id % 10 = 0;
CREATE TEMP TABLE pgcluu_test_tmp AS SELECT * FROM pgcluu_test_t;
SELECT count(*) FROM pgcluu_test_tmp;
DELETE FROM pgcluu_test_t WHERE id % 2 = 0;
VACUUM pgcluu_test_t;
CHECKPOINT;
EOS
my $tmp = tmp_dir();
open(my $fh, '>', "$tmp/workload.sql") or die;
print $fh $workload;
close($fh);

my $wpid = fork();
die "FATAL: fork failed\n" if (!defined $wpid);
if (!$wpid)
{
	open(STDOUT, '>', '/dev/null');
	open(STDERR, '>', '/dev/null');
	my $end = time() + 14;
	while (time() < $end) {
		system(@psql, '-q', '-f', "$tmp/workload.sql");
	}
	exit 0;
}

my $data = "$tmp/data";
mkdir($data);
my @collect = ($^X, "$root/pgcluu_collectd", '-i', '3', '-E', '15', '-f', "$tmp/collectd.pid",
	'-S', '--disable-pidstat', '-d', $ENV{PGDATABASE} || 'postgres');
push(@collect, '-h', $ENV{PGHOST}) if ($ENV{PGHOST});
push(@collect, '-p', $ENV{PGPORT}) if ($ENV{PGPORT});
push(@collect, '-U', $ENV{PGUSER}) if ($ENV{PGUSER});
($rc, $out, $err) = run_cmd(@collect, $data);
waitpid($wpid, 0);
run_cmd(@psql, '-c', 'DROP TABLE IF EXISTS pgcluu_test_t');

is($rc, 0, 'pgcluu_collectd exits with 0') or diag("$out\n$err");
unlike("$out\n$err", qr/\b(ERROR|FATAL):/, 'no error during the collect') or diag("$out\n$err");

# sysinfo.txt contains the server version
my $sysinfo = do { local $/; open(my $f, '<', "$data/sysinfo.txt") or die; <$f> };
like($sysinfo, qr/^\[PGVERSION\]\nPostgreSQL $major/m, 'sysinfo.txt contains the PostgreSQL version');

# Statistics files expected for this version, with their number of fields
my %files = (
	'pg_stat_database.csv' => undef,
	'pg_stat_bgwriter.csv' => undef,
	'pg_database_size.csv' => 4,
);
$files{'pg_stat_io.csv'} = 21 if ($major >= 16);
$files{'pg_stat_aio.csv'} = 9 if ($major >= 18);

foreach my $f (sort keys %files)
{
	ok(-s "$data/$f", "$f is collected") or next;
	open(my $in, '<', "$data/$f") or die;
	my %counts = ();
	my $snapshots = 0;
	my %seen = ();
	while (my $l = <$in>) {
		chomp($l);
		my @fields = split(/;/, $l, -1);
		$counts{scalar @fields}++;
		$snapshots++ if (!$seen{$fields[0]}++);
	}
	close($in);
	is(scalar keys %counts, 1, "$f: all lines have the same number of fields") or diag(explain(\%counts));
	if (defined $files{$f}) {
		is((keys %counts)[0], $files{$f}, "$f: lines have $files{$f} fields");
	}
	cmp_ok($snapshots, '>=', 3, "$f: several snapshots collected");
}
ok(!-e "$data/pg_stat_io.csv", 'pg_stat_io is not collected before PG16') if ($major < 16);
ok(!-e "$data/pg_stat_aio.csv", 'pg_aios is not collected before PG18') if ($major < 18);

# pg_stat_io: WAL rows exist since PG18 only
if ($major >= 16)
{
	my $io = do { local $/; open(my $f, '<', "$data/pg_stat_io.csv") or die; <$f> };
	if ($major >= 18) {
		like($io, qr/;wal;normal;/, 'pg_stat_io: WAL I/O collected (PG18+)');
	} else {
		unlike($io, qr/;wal;/, 'pg_stat_io: no WAL I/O before PG18');
	}
	like($io, qr/^[^;]+;client backend;relation;normal;/m, 'pg_stat_io: client backend I/O collected');
}

# Kernel statistics are collected when the database host is the local host
my $local = (!$ENV{PGHOST} || $ENV{PGHOST} =~ m#^/# || $ENV{PGHOST} =~ /^(localhost|127\.0\.0\.1|::1)$/);
SKIP: {
	skip('no pressure stall information on this host', 2) if (!$local || !-r '/proc/pressure/cpu');
	ok(-s "$data/kernel_stats.csv", 'kernel_stats.csv is collected');
	my $k = do { local $/; open(my $f, '<', "$data/kernel_stats.csv") or die; <$f> };
	like($k, qr/;host;psi_cpu_some;\d+$/m, 'kernel_stats.csv: host pressure stall information');
}
# The postmaster limits need the server processes to be visible from the
# collect host, which is not the case with a server in a container.
SKIP: {
	skip('set PGCLUU_TEST_SAME_HOST=1 when the server runs on this host', 2) if (!$ENV{PGCLUU_TEST_SAME_HOST});
	like($sysinfo, qr/^\[POSTMASTER\]\npid: \d+$/m, 'sysinfo.txt contains the postmaster pid');
	like($sysinfo, qr/^limit open files: \S+ \/ \S+$/m, 'sysinfo.txt contains the postmaster limits');
}

# Report generation
my $report = "$tmp/report";
mkdir($report);
($rc, $out, $err) = run_cmd($^X, "$root/pgcluu", '-S', '-o', $report, $data);
is($rc, 0, 'pgcluu exits with 0') or diag($err);
ok(-e "$report/index.html", 'index.html is generated');
if ($major >= 16) {
	ok(-e "$report/cluster-io_throughput.html", 'I/O throughput report is generated');
	ok(-e "$report/cluster-io_latency.html", 'I/O latency report is generated');
}
if ($major >= 18) {
	ok(-e "$report/cluster-io_wal.html", 'WAL I/O report is generated');
	ok(-e "$report/cluster-io_aio.html", 'asynchronous I/O report is generated');
} else {
	ok(!-e "$report/cluster-io_wal.html", 'no WAL I/O report before PG18');
}

done_testing();
