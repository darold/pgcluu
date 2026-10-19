#!/usr/bin/perl
#------------------------------------------------------------------------------
# Cache files written by pgcluu -C and read by pgcluu.cgi:
#   - only one pgcluu -C runs at a time on an input directory, an other one
#     exits without touching the cache,
#   - cache files are written in temporary files then renamed, no temporary
#     file is left,
#   - a reader waits while the cache files of a directory are replaced,
#   - the input directory is normalized (trailing and duplicated slashes)
#     the same way by pgcluu and pgcluu.cgi: the offsets stored in the cache
#     are found and the csv files are not read again.
#
# To see if a csv file is read again, a line already in the cache is
# modified without changing its length: the new value is shown only when
# the line is read again.
#------------------------------------------------------------------------------
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Test::More;
use Fcntl qw(:flock);
use File::Path qw(make_path);
use PgcluuTest;

my $root = root_dir();
(my $day = $PgcluuTest::FIXTURE_DAY) =~ s#/#-#g;

# Input directory with a day of database sizes: db1 1000, db2 2000
sub make_input
{
	my $base = tmp_dir();
	my $data = "$base/$PgcluuTest::FIXTURE_DAY";
	make_path($data);
	open(my $fh, '>', "$data/pg_database_size.csv") or die;
	foreach my $t ("$day 08:00:00+00", "$day 08:05:00+00") {
		print $fh "$t;16384;db1;1000\n$t;16385;db2;2000\n";
	}
	close($fh);
	return ($base, $data);
}

# Change the size of db1 in the csv file, same length
sub change_cached_line
{
	my $data = shift;
	open(my $fh, '<', "$data/pg_database_size.csv") or die;
	my $c = do { local $/; <$fh> };
	close($fh);
	$c =~ s/;db1;1000\n/;db1;9000\n/g or die;
	open($fh, '>', "$data/pg_database_size.csv") or die;
	print $fh $c;
	close($fh);
}

sub cache
{
	my $dir = shift;
	return run_cmd($^X, "$root/pgcluu", '-S', '-C', $dir);
}

# Distinct values of the data points of a page
sub graph_values
{
	my $html = shift;
	my %seen = ();
	return sort { $a <=> $b } grep { !$seen{$_}++ } ($html =~ /\[\d{13},(-?[\d.]+)\]/g);
}

#### Only one pgcluu -C at a time
{
	my ($base, $data) = make_input();
	open(my $lock, '>>', "$base/.pgcluu_cache_run.lock") or die;
	flock($lock, LOCK_EX) or die;
	my ($rc, $out, $err) = cache($base);
	is($rc, 0, 'pgcluu -C exits with 0 when an other run holds the lock');
	like($err, qr/an other pgcluu process is building the cache/, 'pgcluu -C reports the other run');
	ok(!-e "$data/global_infos.bin", 'no cache file written while an other run holds the lock');
	close($lock);

	($rc, $out, $err) = cache($base);
	is($rc, 0, 'pgcluu -C runs once the lock is released') or diag($err);
	ok(-e "$data/global_infos.bin", 'cache files written');
	opendir(my $dh, $data) or die;
	my @tmp = grep { /\.tmp$/ } readdir($dh);
	closedir($dh);
	is_deeply(\@tmp, [], 'no temporary cache file left');
	ok(-e "$data/.pgcluu_cache.lock", 'lock file of the cache files created');
}

#### Readers wait while the cache files are replaced
SKIP: {
	skip('timeout command not found', 2) if (system('timeout 1 true >/dev/null 2>&1') != 0);

	my ($base, $data) = make_input();
	my ($rc, $out, $err) = cache($base);
	die "FATAL: pgcluu -C failed: $err\n" if ($rc != 0);

	open(my $lock, '>>', "$data/.pgcluu_cache.lock") or die;
	flock($lock, LOCK_EX) or die;
	my $out_dir = tmp_dir();
	($rc) = run_cmd('timeout', '3', $^X, "$root/pgcluu", '-S', '-o', $out_dir, $base);
	is($rc, 124, 'pgcluu waits while the cache files are locked');

	SKIP: {
		skip('CGI.pm is not installed', 1) if (!have_cgi_pm());
		my $cgi = cgi_install($base);
		($rc) = run_cmd('timeout', '3', $^X, $cgi, "db=all&action=cluster-size&$PgcluuTest::CGI_RANGE");
		is($rc, 124, 'pgcluu.cgi waits while the cache files are locked');
	}
	close($lock);
}

#### Normalization of the input directory
foreach my $spelling ('/', '//', '/./')
{
	my ($base, $data) = make_input();
	my ($rc, $out, $err) = cache($base);
	die "FATAL: pgcluu -C failed: $err\n" if ($rc != 0);
	change_cached_line($data);

	# '/./' is not normalized, the offsets are not found: the line is read
	# again, it shows that the test detects a csv file read again.
	my $found = ($spelling eq '/./') ? 9000 : 1000;
	my $input = ($spelling eq '/./') ? "$base/." : "$base$spelling";

	SKIP: {
		skip('CGI.pm is not installed', 2) if (!have_cgi_pm());
		my $cgi = cgi_install($input);
		($rc, $out, $err) = cgi_run($cgi, 'db=all&action=cluster-size');
		is($rc, 0, "cgi with INPUT_DIR ending with '$spelling' runs") or diag($err);
		my @got = graph_values($out);
		ok(grep({ $_ == $found } @got), "cgi with INPUT_DIR ending with '$spelling': db1 size is $found")
			or diag("values found: @got");
	}

	# A second cache pass with the other spelling must not read the line again
	next if ($spelling eq '/./');
	($rc, $out, $err) = cache("$base$spelling");
	is($rc, 0, "pgcluu -C with input directory ending with '$spelling'") or diag($err);
	my $out_dir = tmp_dir();
	($rc, $out, $err) = run_cmd($^X, "$root/pgcluu", '-S', '-o', $out_dir, $base);
	my $html = do { local $/; open(my $fh, '<', "$out_dir/$PgcluuTest::FIXTURE_DAY/cluster-database-size.html") or die; <$fh> };
	my @got = graph_values($html);
	ok(grep({ $_ == 1000 } @got) && !grep({ $_ == 9000 } @got),
		"pgcluu -C with input directory ending with '$spelling' does not read the csv file again")
		or diag("values found: @got");
}

done_testing();
