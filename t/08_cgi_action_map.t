#!/usr/bin/perl
#------------------------------------------------------------------------------
# In cache mode the CGI only loads the cache files of the requested report,
# given by %pg_action_map. For every graph of %DB_GRAPH_INFOS, the action
# (graph name, or page name for the pages grouping several graphs) must load
# the storage variable used by the report of its statistics file, and every
# variable of the map must be saved in the cache (@pg_to_be_stored).
#------------------------------------------------------------------------------
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Test::More;
use PgcluuTest;

my $script = root_dir() . '/cgi-bin/pgcluu.cgi';
my $src = do { local $/; open(my $fh, '<', $script) or die; <$fh> };

# Evaluate the data structures declared at the top of the CGI
our (%DB_GRAPH_INFOS, %pg_action_map, @pg_to_be_stored, @STAT_IO_PAGES, %STAT_IO_GRAPHS);
foreach my $re (
	qr/^our \@STAT_IO_PAGES = \(.*?^\);/ms,
	qr/^our \@pg_to_be_stored = \(.*?^\);/ms,
	qr/^our %pg_action_map = \(.*?^\);\n(?:#.*\n)*foreach my \$p \(\@STAT_IO_PAGES\) \{.*?^\}/ms,
	qr/^my %DB_GRAPH_INFOS = \(.*?^\);(?:\n\n# A graph that is part.*?^\})?/ms)
{
	my ($code) = $src =~ m{($re)};
	ok($code, "structure found in pgcluu.cgi: " . substr("$re", 0, 40)) or next;
	$code =~ s/^my /our /;
	eval "no strict; no warnings; $code; 1" or fail("evaluation of the structure: $@");
}

my %stored = map { $_ => 1 } @pg_to_be_stored;
ok(scalar keys %DB_GRAPH_INFOS > 30, 'graph definitions loaded');

# Storage variables used by the report of each statistics file. Most names are
# derived from the file name, the exceptions are listed.
my %storage = (
	'pg_hba.conf'             => 'all_pg_hba_conf',
	'pg_ident.conf'           => 'all_pg_ident_conf',
	'pg_stat_ext.csv'         => 'all_stat_extended_statistics',
	'pgbouncer.ini'           => 'all_pgbouncer_ini',
	'pgbouncer_req_stats.csv' => 'all_pgbouncer_req_stats',
);

foreach my $k (sort keys %DB_GRAPH_INFOS)
{
	my $need = $storage{$k};
	if (!$need)
	{
		$need = $k;
		$need =~ s/\.csv//;
		$need =~ s/\./_/g;
		$need =~ s/^pg_/all_/;
		$need = 'all_pgbouncer_stats' if ($need eq 'pgbouncer_stats');
		$need = "all_$need" if (($need =~ /_conf/) && ($need !~ /^all/));
		$need =~ s/_all_/_user_/;
	}
	ok($stored{$need}, "$k: storage $need is saved in the cache");

	foreach my $n (sort keys %{$DB_GRAPH_INFOS{$k}})
	{
		my $g = $DB_GRAPH_INFOS{$k}{$n};
		foreach my $action (grep { defined } ($g->{name}, $g->{page}))
		{
			my @loaded = split(/,/, $pg_action_map{$action} || $action);
			ok(grep({ $_ eq $need } @loaded), "$k: action $action loads $need")
				or diag("pg_action_map gives: " . join(',', @loaded));
			foreach my $v (@loaded) {
				ok($stored{$v}, "$k: action $action loads a stored variable ($v)") if (exists $pg_action_map{$action});
			}
		}
	}
}

done_testing();
