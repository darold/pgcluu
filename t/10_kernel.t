#!/usr/bin/perl
#------------------------------------------------------------------------------
# Kernel tuning parameters, postmaster limits and kernel statistics.
#
#   - cgroup files parsing and kernel_stats.csv format in pgcluu_collectd, on
#     a fake cgroup directory (no root privilege or cgroup v2 needed),
#   - formatting of the postmaster limits in pgcluu and pgcluu.cgi,
#   - kernel pages and system information generated from the PG18 fixture,
#   - kernel.shmmax and kernel.shmall are no longer shown.
#------------------------------------------------------------------------------
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Test::More;
use PgcluuTest;
use IO::File;

my $root = root_dir();
my $tmp = tmp_dir();

# Fake cgroup v2 directory of the postmaster
my $cg = "$tmp/cgroup";
mkdir($cg);
my %files = (
	'memory.max'      => "8589934592\n",
	'memory.high'     => "max\n",
	'cpu.max'         => "200000 100000\n",
	'io.max'          => "8:0 rbps=max wbps=104857600 riops=max wiops=max\n8:16 rbps=max wbps=max riops=1000 wiops=max\n",
	'memory.events'   => "low 0\nhigh 12\nmax 3\noom 2\noom_kill 1\noom_group_kill 0\n",
	'cpu.pressure'    => "some avg10=1.00 avg60=0.50 avg300=0.10 total=5000000\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=100\n",
	'memory.pressure' => "some avg10=0.00 avg60=0.00 avg300=0.00 total=2000\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=1000\n",
	'io.pressure'     => "some avg10=0.00 avg60=0.00 avg300=0.00 total=3000\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=1500\n",
);
foreach my $f (keys %files) {
	open(my $fh, '>', "$cg/$f") or die;
	print $fh $files{$f};
	close($fh);
}

# pgcluu_collectd functions
load_subs("$root/pgcluu_collectd", 'Collectd', 'run_os_command', 'get_cgroup_values',
	'collect_kernel_stats', 'get_current_timestamp', 'dprint');
no warnings 'once';
$Collectd::sshcmd = '';

my @lines = Collectd::get_cgroup_values($cg, 'memory.max', 'memory.high', 'memory.swap.max',
	'cpu.max', 'io.max', 'memory.events');
is_deeply(\@lines, [
	"memory.max: 8589934592\n",
	"memory.high: max\n",
	"cpu.max: 200000 100000\n",
	"io.max: 8:0 rbps=max wbps=104857600 riops=max wiops=max, 8:16 rbps=max wbps=max riops=1000 wiops=max\n",
	"memory.events oom: 2\n",
	"memory.events oom_kill: 1\n",
], 'cgroup values: missing files skipped, multi-line values joined, only OOM events');

$Collectd::POSTMASTER_CGROUP = $cg;
my $out = "$tmp/collect";
mkdir($out);
Collectd::collect_kernel_stats($out);
ok(-s "$out/kernel_stats.csv", 'kernel_stats.csv is written');
open(my $fh, '<', "$out/kernel_stats.csv") or die;
my @rows = <$fh>;
close($fh);
chomp(@rows);
my @bad = grep { !/^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d;(host|cgroup);\w+;\d+$/ } @rows;
is_deeply(\@bad, [], 'kernel_stats.csv lines are: timestamp;source;metric;value');
my %cgroup = map { (split(/;/))[2] => (split(/;/))[3] } grep { /;cgroup;/ } @rows;
is_deeply(\%cgroup, {
	psi_cpu_some => 5000000, psi_cpu_full => 100,
	psi_memory_some => 2000, psi_memory_full => 1000,
	psi_io_some => 3000, psi_io_full => 1500,
	memory_events_low => 0, memory_events_high => 12, memory_events_max => 3,
	memory_events_oom => 2, memory_events_oom_kill => 1,
}, 'cgroup pressure and memory events counters');
SKIP: {
	skip('no pressure stall information on this host', 1) if (!-e '/proc/pressure/cpu');
	ok(grep({ /;host;psi_cpu_some;\d+$/ } @rows), 'host pressure stall information collected');
}

# Formatting of the postmaster limits
my %scripts = ('pgcluu' => "$root/pgcluu");
$scripts{'pgcluu.cgi'} = "$root/cgi-bin/pgcluu.cgi" if (have_cgi_pm());
foreach my $name (sort keys %scripts)
{
	my $pkg = $name eq 'pgcluu' ? 'Report' : 'Cgi';
	load_subs($scripts{$name}, $pkg, 'format_postmaster_value', 'pretty_print_size');
	no strict 'refs';
	my $f = \&{"${pkg}::format_postmaster_value"};
	is($f->('memory.max', '8589934592'), '8.00 GB', "$name: memory.max formatted");
	is($f->('memory.high', 'max'), 'unlimited', "$name: max is unlimited");
	is($f->('memory.limit_in_bytes', '9223372036854771712'), 'unlimited', "$name: cgroup v1 no limit");
	is($f->('cpu.cfs_quota_us', '-1'), 'unlimited', "$name: no CPU quota");
	is($f->('cpu.max', '200000 100000'), '2.00 CPUs', "$name: cpu.max as a number of CPUs");
	is($f->('cpu.max', 'max 100000'), 'unlimited', "$name: cpu.max without quota");
	is($f->('limit locked memory', '8388608 / 8388608'), '8.00 MB / 8.00 MB', "$name: locked memory limits");
	is($f->('oom_score_adj', '-1000'), '-1000', "$name: other values unchanged");
}

# Reports generated from the PG18 fixture
my $report = tmp_dir();
my ($rc, $o, $err) = run_cmd($^X, "$root/pgcluu", '-S', '-o', $report, fixture_dir('pg18'));
is($rc, 0, 'pgcluu report generated') or diag($err);
my $pages = normalize_report_dir($report);
foreach my $p ('kernel-pressure.html', 'kernel-events.html') {
	ok(exists $pages->{$p}, "$p is generated");
}
my @psi = map { @{$_->{data}} } grep { $_->{ylabel} eq 'Percent' } @{$pages->{'kernel-pressure.html'}{graphs}};
my @vals = map { /,([\d.]+)\]/g } @psi;
ok(scalar @vals > 0, 'pressure stall values found');
is(scalar(grep { $_ < 0 || $_ > 100 } @vals), 0, 'pressure stall values are percentages');
is_deeply([ map { $_->{title} } @{$pages->{'kernel-pressure.html'}{graphs}} ], [
	'Host pressure stall: some tasks stalled', 'Host pressure stall: all tasks stalled',
	'PostgreSQL cgroup pressure stall: some tasks stalled', 'PostgreSQL cgroup pressure stall: all tasks stalled',
], 'host and cgroup pressure graphs');

my $index = do { local $/; open(my $f, '<', "$report/index.html") or die; <$f> };
like($index, qr/postmaster process limits/, 'postmaster limits shown in the system information');
like($index, qr/shmem_enabled/, 'transparent huge pages shmem_enabled shown');
like($index, qr/id="menu-kernel-pressure"/, 'kernel pages in the System menu without sar');

# shmmax and shmall from files collected by older versions are not shown
my $old = "$tmp/old";
copy_dir(fixture_dir('pg18'), $old);
my $sys = do { local $/; open(my $f, '<', "$old/sysinfo.txt") or die; <$f> };
ok($sys =~ s/^\[SYSTEM\]\n/[SYSTEM]\nkernel.shmmax = 18446744073692774399\nkernel.shmall = 18446744073692774399\n/m, 'old style sysinfo.txt with shmmax and shmall');
open($fh, '>', "$old/sysinfo.txt") or die;
print $fh $sys;
close($fh);
my $report2 = tmp_dir();
run_cmd($^X, "$root/pgcluu", '-S', '-o', $report2, $old);
$index = do { local $/; open(my $f, '<', "$report2/index.html") or die; <$f> };
unlike($index, qr/shmmax|shmall/, 'kernel.shmmax and kernel.shmall are not shown');

done_testing();
