#!/usr/bin/perl
#------------------------------------------------------------------------------
# Parsing of the PostgreSQL version stored in sysinfo.txt and version checks
# with backend_minimum_version(), in pgcluu and in pgcluu.cgi. The version
# decides which reports or graphs are generated.
#------------------------------------------------------------------------------
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Test::More;
use PgcluuTest;

# version string => expected major version
my %versions = (
	'PostgreSQL 18.4 on x86_64-pc-linux-gnu, compiled by gcc (Ubuntu 7.5.0-3ubuntu1~18.04) 7.5.0, 64-bit' => '18.4',
	'PostgreSQL 16.14 on x86_64-pc-linux-gnu, compiled by gcc (GCC) 11.4.1, 64-bit' => '16.14',
	'PostgreSQL 19beta4 on x86_64-pc-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit' => '19.0',
	'PostgreSQL 19devel on x86_64-pc-linux-gnu, compiled by gcc 14.2.0, 64-bit' => '19.0',
	'PostgreSQL 18rc1 on aarch64-unknown-linux-gnu, compiled by clang 17.0.6, 64-bit' => '18.0',
	'PostgreSQL 9.6.24 on x86_64-pc-linux-gnu, compiled by gcc 4.8.5, 64-bit' => '9.6',
);

my $tmp = tmp_dir();
my %scripts = ('pgcluu' => root_dir() . '/pgcluu');
$scripts{'pgcluu.cgi'} = root_dir() . '/cgi-bin/pgcluu.cgi' if (have_cgi_pm());

foreach my $name (sort keys %scripts)
{
	my $pkg = $name eq 'pgcluu' ? 'Report' : 'Cgi';
	load_subs($scripts{$name}, $pkg, 'read_sysinfo_file', 'open_filehdl',
		'is_compressed', 'pretty_print_size', 'backend_minimum_version');
	no strict 'refs';
	no warnings 'once';
	foreach my $v (sort keys %versions)
	{
		open(my $fh, '>', "$tmp/sysinfo.txt") or die;
		print $fh "[PGVERSION]\n$v\n";
		close($fh);
		%{"${pkg}::sysinfo"} = &{"${pkg}::read_sysinfo_file"}("$tmp/sysinfo.txt");
		my $major = ${"${pkg}::sysinfo"}{PGVERSION}{major};
		is($major, $versions{$v}, "$name: major version of '" . substr($v, 0, 25) . "...'");
		my $num = $versions{$v};
		ok(&{"${pkg}::backend_minimum_version"}(int($num)), "$name: backend_minimum_version(" . int($num) . ") is true");
		ok(!&{"${pkg}::backend_minimum_version"}(int($num) + 1), "$name: backend_minimum_version(" . (int($num) + 1) . ") is false");
	}
}

# The fixtures must contain the version collected by pgcluu_collectd
foreach my $fixture (fixtures())
{
	my $f = fixture_dir($fixture) . '/sysinfo.txt';
	my $content = do { local $/; open(my $fh, '<', $f) or die; <$fh> };
	my ($num) = $fixture =~ /(\d+)$/;
	like($content, qr/^\[PGVERSION\]\nPostgreSQL $num\./m, "$fixture: sysinfo.txt contains the PostgreSQL version");
}

done_testing();
