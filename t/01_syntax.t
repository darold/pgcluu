#!/usr/bin/perl
#------------------------------------------------------------------------------
# Compilation of the scripts and command line options that do not need a
# PostgreSQL server.
#------------------------------------------------------------------------------
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Test::More;
use PgcluuTest;

my $root = root_dir();

foreach my $script ('pgcluu', 'pgcluu_collectd')
{
	my ($rc, $out, $err) = run_cmd($^X, '-c', "$root/$script");
	is($rc, 0, "$script compiles") or diag($err);
	unlike($err, qr/(?<!syntax OK)\n.*\S/s, "$script compiles without warning") or diag($err);
}

SKIP: {
	skip('CGI.pm is not installed', 1) if (!have_cgi_pm());
	my ($rc, $out, $err) = run_cmd($^X, '-c', "$root/cgi-bin/pgcluu.cgi");
	is($rc, 0, 'pgcluu.cgi compiles') or diag($err);
}

# --help and --version
foreach my $script ('pgcluu', 'pgcluu_collectd')
{
	# Note: pgcluu_collectd --help exits with code 1, only the output is tested
	my ($rc, $out, $err) = run_cmd($^X, "$root/$script", '--help');
	like($out, qr/usage: \S*$script/, "$script --help shows the usage");

	($rc, $out, $err) = run_cmd($^X, "$root/$script", '--version');
	is($rc, 0, "$script --version exits with 0");
	like($out, qr/\d+\.\d+/, "$script --version shows a version number");
}

# List of metrics: every metric must be listed and the I/O ones are there
my ($rc, $out, $err) = run_cmd($^X, "$root/pgcluu_collectd", '--list-metric');
is($rc, 0, 'pgcluu_collectd --list-metric exits with 0');
foreach my $m ('io', 'aio', 'bgwriter', 'database', 'archiver', 'slot') {
	like($out, qr/^\s+$m$/m, "metric $m is listed");
}

done_testing();
