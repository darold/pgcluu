#!/usr/bin/perl
#------------------------------------------------------------------------------
# pidstat reports (PostgreSQL CPU, memory, faults, I/O, context switches).
#
# t/pidstat/pidstat_stats.dat is the output of
#   pidstat -T ALL -u -w -r -d -U postgres 1 1 | grep -v Average
# in the format of sysstat 12.6.1, three samples of two processes with the
# same values (sar_stats.dat is needed by pgcluu to read the pidstat file):
#
#   pid  %usr %system %wait  VSZ     RSS   %MEM minflt majflt kB_rd kB_wr kB_ccwr iodelay cswch nvcswch
#   100  10   5       1      200000  10000 0.5  1      0      100   50    0       2       10    1
#   101  20   10      2      300000  20000 1    3      1      200   150   10      3       30    2
#
# The values of a sample are the sum of the processes. The CHILD reports of
# -T ALL (usr-ms, minflt-nr) must be ignored.
#
# Cases: static report, older sysstat format (%user, no %wait and no
# iodelay), cache built in several passes with a sample cut in the middle
# of a line and a pass reading again lines already in the cache, two samples
# with the same timestamp (DST), pgcluu.cgi from the csv and from the cache
# files, statistics of a day not kept in the cache of the next day.
#------------------------------------------------------------------------------
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Test::More;
use File::Copy qw(copy);
use File::Path qw(make_path);
use Storable qw(retrieve);
use PgcluuTest;

my $root = root_dir();
my $src = "$root/t/pidstat";
my $DAY = $PgcluuTest::FIXTURE_DAY;

# Distinct values of each series of a page, in the order of the legends
my %EXPECTED = (
	'cpu'        => [ [45], [15], [30], [3] ],   # total, system, user, wait
	'memory'     => [ [500000], [30000] ],       # VSZ, RSS
	'mempercent' => [ [1.5] ],
	'fault'      => [ [4], [1] ],                # minflt/s, majflt/s
	'io'         => [ [300], [200], [10] ],      # kB_rd/s, kB_wr/s, kB_ccwr/s
	'iodelay'    => [ [5] ],
	'cswch'      => [ [40], [3] ],               # cswch/s, nvcswch/s
);

sub slurp
{
	my $f = shift;
	open(my $fh, '<', $f) or die "FATAL: can not read $f, $!\n";
	local $/;
	return <$fh>;
}

sub spew
{
	my ($f, $c, $append) = @_;
	open(my $fh, $append ? '>>' : '>', $f) or die "FATAL: can not write $f, $!\n";
	print $fh $c;
	close($fh);
}

# Series of a page: list of [ distinct values ] and the number of points
sub series
{
	my $html = shift;
	my @series = ();
	my %npoints = ();
	foreach my $s ($html =~ /^\s*var graph_\d+_d\d+ = (.*);$/mg)
	{
		my @v = ($s =~ /\[\d{13},(-?[\d.]+)\]/g);
		my %seen = ();
		push(@series, [ sort { $a <=> $b } grep { !$seen{$_}++ } map { $_ + 0 } @v ]);
		$npoints{scalar @v} = 1;
	}
	return (\@series, [ sort keys %npoints ]);
}

sub check_page
{
	my ($html, $page, $label, $expected, $points) = @_;
	my ($got, $npoints) = series($html);
	is_deeply($got, $expected // $EXPECTED{$page}, "$label: $page values") or diag(explain($got));
	is_deeply($npoints, [ $points // 3 ], "$label: $page has a point per sample") if (@$got);
}

# Build a static report and return the directory of the pages
sub report
{
	my ($dir, $label, $subdir) = @_;
	my $out = tmp_dir();
	my ($rc, $o, $err) = run_cmd($^X, "$root/pgcluu", '-o', $out, $dir);
	is($rc, 0, "$label: pgcluu report") or diag($err);
	return $subdir ? "$out/$subdir" : $out;
}

sub check_report
{
	my ($dir, $label, $subdir) = @_;
	my $out = report($dir, $label, $subdir);
	foreach my $page (sort keys %EXPECTED) {
		check_page(slurp("$out/pidstat-postgres-$page.html"), $page, $label);
	}
}

sub cache
{
	my ($dir, $label) = @_;
	my ($rc, $o, $err) = run_cmd($^X, "$root/pgcluu", '-C', $dir);
	is($rc, 0, "$label: pgcluu -C") or diag($err);
}

# Input directory of a day with the fixture files, the pidstat file content
# can be given.
sub make_day
{
	my ($base, $day, $pidstat) = @_;
	my $data = "$base/$day";
	make_path($data);
	copy("$src/sar_stats.dat", "$data/sar_stats.dat") or die;
	spew("$data/pidstat_stats.dat", $pidstat // slurp("$src/pidstat_stats.dat"));
	return $data;
}

my $pidstat = slurp("$src/pidstat_stats.dat");

#### Static report
{
	my $data = tmp_dir();
	make_day($data, '.');
	check_report($data, 'static report');
}

#### Older sysstat format: %user instead of %usr, no %wait, no iodelay
{
	# Remove a column from the reports whose header contains it
	my $remove = sub {
		my ($text, $name) = @_;
		my $idx = -1;
		my @out = ();
		foreach my $l (split(/\n/, $text, -1)) {
			if ($l =~ /^\d+:\d+:\d+\s/) {
				my @f = split(/(\s+)/, $l);
				if ($l =~ /\Q$name\E/) {
					($idx) = grep { $f[$_] eq $name } 0..$#f;
				}
				if ($idx >= 0) {
					splice(@f, $idx - 1, 2);
					$l = join('', @f);
				}
			} else {
				$idx = -1;
			}
			push(@out, $l);
		}
		return join("\n", @out);
	};
	my $old = $remove->($remove->($pidstat, '%wait'), 'iodelay');
	$old =~ s/%usr/%user/g;
	unlike($old, qr/%wait|iodelay/, 'older format: %wait and iodelay columns removed');

	my $data = tmp_dir();
	make_day($data, '.', $old);
	my $out = report($data, 'older format');
	check_page(slurp("$out/pidstat-postgres-cpu.html"), 'cpu', 'older format', [ [45], [15], [30] ]);
	check_page(slurp("$out/pidstat-postgres-io.html"), 'io', 'older format');
}

#### Cache built in several passes
{
	my $base = tmp_dir();
	# Cut in the middle of a line of the memory report of the second sample
	my $cut = index($pidstat, "  200000   10000", index($pidstat, '10:01:01 postgres       100      1.00'));
	ok($cut > 0, 'cache: cut position found');
	my $data = make_day($base, $DAY, substr($pidstat, 0, $cut));
	cache($base, 'cache pass 1');
	copy("$data/global_infos.bin", "$base/old_global_infos.bin") or die;
	spew("$data/pidstat_stats.dat", substr($pidstat, $cut), 1);
	cache($base, 'cache pass 2');
	check_report($base, 'cache in two passes', $DAY);

	# A pass reading again the lines read by the second pass (old offsets)
	copy("$base/old_global_infos.bin", "$data/global_infos.bin") or die;
	cache($base, 'cache pass 3');
	check_report($base, 'cache with lines read again', $DAY);

	SKIP: {
		skip('CGI.pm is not installed', 2 * keys %EXPECTED) if (!have_cgi_pm());
		my $cgi = cgi_install($base);
		foreach my $page (sort keys %EXPECTED) {
			my ($rc, $out, $err) = cgi_run($cgi, "action=pidstat-postgres-$page");
			ok($rc == 0 && $err eq '', "cgi cache: pidstat-postgres-$page runs") or diag($err);
			check_page($out, $page, 'cgi cache');
		}
	}
}

#### pgcluu.cgi from the csv files
SKIP: {
	skip('CGI.pm is not installed', 3 * keys %EXPECTED) if (!have_cgi_pm());
	my $base = tmp_dir();
	make_day($base, $DAY);
	my $cgi = cgi_install($base);
	foreach my $page (sort keys %EXPECTED) {
		my ($rc, $out, $err) = cgi_run($cgi, "action=pidstat-postgres-$page");
		ok($rc == 0 && $err eq '', "cgi csv: pidstat-postgres-$page runs") or diag($err);
		check_page($out, $page, 'cgi csv');
	}
}

#### Two samples with the same timestamp: the last one replaces the first
{
	(my $dup = $pidstat) =~ s/10:01:0([01])/10:00:0$1/g;
	my $data = tmp_dir();
	make_day($data, '.', $dup);
	my $out = report($data, 'same timestamp');
	foreach my $page (sort keys %EXPECTED) {
		check_page(slurp("$out/pidstat-postgres-$page.html"), $page, 'same timestamp', undef, 2);
	}
}

#### Statistics of a day are not kept in the cache of the next day
{
	my $base = tmp_dir();
	make_day($base, $DAY);
	(my $day2 = $DAY) =~ s#(\d+)$#sprintf('%02d', $1 + 1)#e;
	(my $next = $pidstat) =~ s#10/05/26#10/06/26#g;
	make_day($base, $day2, $next);
	cache($base, 'two days');
	my $stats = retrieve("$base/$day2/pidstat_cpu_stat.bin")->{pidstat_cpu_stat};
	my @days = sort keys %{{ map { (gmtime($_/1000))[3] => 1 } keys %$stats }};
	is_deeply(\@days, [ 6 ], 'two days: the cache of the second day only has its own samples')
		or diag("days found: @days");
}

done_testing();
