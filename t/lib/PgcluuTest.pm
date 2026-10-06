package PgcluuTest;

#------------------------------------------------------------------------------
# Helpers for the pgCluu regression tests.
#
# The tests never modify pgcluu, pgcluu_collectd or pgcluu.cgi: the scripts are
# run as commands, or some of their functions are extracted from the source to
# be evaluated alone (see load_subs()).
#
# Expected results are stored as JSON files under t/expected/. When a change
# of a report is intended, set PGCLUU_REGEN=1 to rewrite the expected files
# and review the result with git diff.
#------------------------------------------------------------------------------

use strict;
use warnings;

use Exporter 'import';
use Cwd qw(abs_path);
use File::Basename qw(dirname basename);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use JSON::PP;
use Test::More;

our @EXPORT = qw(
	root_dir fixture_dir fixtures tmp_dir copy_dir run_cmd
	normalize_html html_pages normalize_report_dir
	check_expected load_subs
	cgi_setup cgi_run cgi_menu_actions
	have_cgi_pm have_node
);

# Data of the fixtures were collected the same day, the CGI needs a
# directory per day and a time range.
our $FIXTURE_DAY = '2026/10/05';
our $CGI_RANGE = 'start=2026-10-05&end=2026-10-06';

# Reports must not depend on the timezone of the host
$ENV{TZ} = 'UTC';
$ENV{LANG} = 'C';
$ENV{LC_ALL} = 'C';

sub root_dir
{
	return abs_path(dirname(__FILE__) . '/../..');
}

sub fixture_dir
{
	my $name = shift;
	return root_dir() . "/t/fixtures/$name";
}

# List of the fixtures, a fixture is a directory of statistics files
# produced by pgcluu_collectd for a PostgreSQL major version.
sub fixtures
{
	my $dir = root_dir() . '/t/fixtures';
	opendir(my $dh, $dir) or die "FATAL: can not read $dir, $!\n";
	my @list = sort grep { !/^\./ && -d "$dir/$_" } readdir($dh);
	closedir($dh);
	return @list;
}

sub tmp_dir
{
	return tempdir('pgcluu_test_XXXXXX', TMPDIR => 1, CLEANUP => !$ENV{PGCLUU_KEEP_TMP});
}

# Copy the files of a directory (not recursive) into an other one
sub copy_dir
{
	my ($src, $dst) = @_;

	make_path($dst);
	opendir(my $dh, $src) or die "FATAL: can not read $src, $!\n";
	foreach my $f (readdir($dh)) {
		next if (!-f "$src/$f");
		copy("$src/$f", "$dst/$f") or die "FATAL: can not copy $src/$f, $!\n";
	}
	closedir($dh);
}

# Run a command and return its exit code, stdout and stderr
sub run_cmd
{
	my @cmd = @_;

	my $dir = tmp_dir();
	my $pid = fork();
	die "FATAL: fork failed, $!\n" if (!defined $pid);
	if (!$pid)
	{
		open(STDOUT, '>', "$dir/stdout") or die;
		open(STDERR, '>', "$dir/stderr") or die;
		exec(@cmd) or die "FATAL: can not run $cmd[0], $!\n";
	}
	waitpid($pid, 0);
	my $rc = $? >> 8;
	my $out = _slurp("$dir/stdout");
	my $err = _slurp("$dir/stderr");

	return ($rc, $out, $err);
}

sub _slurp
{
	my $file = shift;
	local $/;
	open(my $fh, '<', $file) or return '';
	my $c = <$fh>;
	close($fh);
	return $c // '';
}

#------------------------------------------------------------------------------
# HTML normalization
#
# A report page is reduced to what must not change between two runs:
# panel titles, graph titles, series labels and data points, and the rows of
# the tables. Generation dates, graph numbering ($IDX) and the menu are not
# kept. Table rows are sorted because some reports list rows with equal
# values in hash order.
#------------------------------------------------------------------------------
sub normalize_html
{
	my $html = shift;

	my %page = ();

	# Remove the menu, it is common to all pages and tested elsewhere
	$html =~ s{<!-- Load navbar -->.*?<!--/\.nav-collapse -->}{}gs;

	my @titles = ($html =~ m{<h2>(.*?)</h2>}gs);
	s/\s+/ /g foreach (@titles);
	$page{titles} = \@titles;

	# Line graphs: data and series labels are declared in the same script
	my @graphs = ();
	foreach my $script ($html =~ m{/\* <!\[CDATA\[ \*/(.*?)/\* \]\]> \*/}gs)
	{
		my %g = ();
		if ($script =~ /create_linegraph\('[^']*', '([^']*)', '([^']*)'/) {
			$g{type} = 'line';
			$g{title} = $1;
			$g{ylabel} = $2;
			$g{labels} = [ ($script =~ /label: "([^"]*)"/g) ];
			$g{data} = [ ($script =~ /var graph_\d+_d\d+ = \[(.*?)\];/g) ];
		} elsif ($script =~ /create_piechart\('[^']*', '([^']*)'/) {
			$g{type} = 'pie';
			$g{title} = $1;
			($g{data}) = ($script =~ /var data_\d+ = \[(.*?)\];/s);
		} else {
			next;
		}
		push(@graphs, \%g);
	}
	$page{graphs} = \@graphs;

	# Rows of the html tables
	my @rows = ();
	foreach my $tr ($html =~ m{<tr[^>]*>(.*?)</tr>}gs)
	{
		my @cells = ($tr =~ m{<t[hd][^>]*>(.*?)</t[hd]>}gs);
		next if ($#cells < 0);
		foreach (@cells) { s/<[^>]+>//g; s/\s+/ /g; s/^ //; s/ $//; }
		push(@rows, join(' | ', @cells));
	}
	$page{rows} = [ sort @rows ];

	# Notices shown instead of a graph
	$page{notices} = [ ($html =~ m{<blockquote>(.*?)</blockquote>}gs) ];

	return \%page;
}

# List of html pages of a report directory
sub html_pages
{
	my $dir = shift;
	opendir(my $dh, $dir) or die "FATAL: can not read $dir, $!\n";
	my @pages = sort grep { /\.html$/ } readdir($dh);
	closedir($dh);
	return @pages;
}

# Normalize all pages of a pgcluu report directory
sub normalize_report_dir
{
	my $dir = shift;

	my %report = ();
	foreach my $p (html_pages($dir)) {
		$report{$p} = normalize_html(_slurp("$dir/$p"));
	}
	return \%report;
}

#------------------------------------------------------------------------------
# Compare a data structure with an expected JSON file, or rewrite the file
# when PGCLUU_REGEN is set. Each top level key is tested separately so that
# a failure points to the page or the action that changed.
#------------------------------------------------------------------------------
sub check_expected
{
	my ($got, $file, $name) = @_;

	my $json = JSON::PP->new->canonical(1)->pretty->utf8(0);
	my $path = root_dir() . "/t/expected/$file";

	if ($ENV{PGCLUU_REGEN})
	{
		make_path(dirname($path));
		open(my $fh, '>', $path) or die "FATAL: can not write $path, $!\n";
		print $fh $json->encode($got);
		close($fh);
		pass("$name: expected results written to t/expected/$file");
		return;
	}

	if (!-e $path) {
		fail("$name: no expected results in t/expected/$file, run with PGCLUU_REGEN=1");
		return;
	}
	my $expected = $json->decode(_slurp($path));

	my %keys = map { $_ => 1 } (keys %{$expected}, keys %{$got});
	foreach my $k (sort keys %keys)
	{
		if (!exists $got->{$k}) {
			fail("$name: $k is missing");
		} elsif (!exists $expected->{$k}) {
			fail("$name: $k is not expected");
		} else {
			is_deeply($got->{$k}, $expected->{$k}, "$name: $k");
		}
	}
}

#------------------------------------------------------------------------------
# Extract the code of some functions from a script and evaluate it into the
# given package, so they can be called without running the script. Both
# forms are supported:
#   sub name
#   {
#   ...
#   }
# and the one line form: sub name { ... };
#------------------------------------------------------------------------------
sub load_subs
{
	my ($script, $package, @names) = @_;

	my $src = _slurp($script);
	my $code = "package $package;\nno strict;\nno warnings;\n";
	foreach my $n (@names)
	{
		if ($src =~ /^(sub $n\s*\n\{.*?^\})/ms) {
			$code .= "$1\n";
		} elsif ($src =~ /^(sub $n\s*\{[^\n]*\};?)\s*$/m) {
			$code .= "$1\n";
		} else {
			die "FATAL: function $n not found in $script\n";
		}
	}
	$code .= "1;\n";
	eval $code or die "FATAL: can not evaluate functions from $script: $@\n";
}

#------------------------------------------------------------------------------
# CGI helpers
#
# pgcluu.cgi reads its configuration from a fixed path, so the script is
# copied into a temporary directory with the path of a test configuration
# file. The data directory uses the YYYY/MM/DD layout expected by the CGI.
#------------------------------------------------------------------------------
sub have_cgi_pm
{
	return eval { require CGI; 1 } ? 1 : 0;
}

sub have_node
{
	my ($rc) = run_cmd('node', '--version');
	return $rc == 0;
}

# Prepare a CGI installation for a fixture. Mode 'csv' uses the statistics
# files only, mode 'bin' adds the cache files built by pgcluu -C.
sub cgi_setup
{
	my ($fixture, $mode) = @_;

	my $tmp = tmp_dir();
	my $data = "$tmp/data/$FIXTURE_DAY";
	copy_dir(fixture_dir($fixture), $data);

	if ($mode eq 'bin')
	{
		# The cache must be built on the root directory as documented, the
		# offsets in the csv files are stored with the full path of the day.
		my ($rc, $out, $err) = run_cmd($^X, root_dir() . '/pgcluu', '-S', '-C', "$tmp/data");
		die "FATAL: pgcluu -C failed on $fixture: $err\n" if ($rc != 0);
	}

	open(my $fh, '>', "$tmp/pgcluu.conf") or die;
	print $fh "INPUT_DIR $tmp/data\n";
	close($fh);

	my $src = _slurp(root_dir() . '/cgi-bin/pgcluu.cgi');
	$src =~ s{^my \$CONFIG_FILE\s*=\s*"[^"]*";}{my \$CONFIG_FILE = "$tmp/pgcluu.conf";}m
		or die "FATAL: can not find \$CONFIG_FILE in pgcluu.cgi\n";
	open($fh, '>', "$tmp/pgcluu.cgi") or die;
	print $fh $src;
	close($fh);

	return "$tmp/pgcluu.cgi";
}

# Run the CGI with the given query and return its exit code, stdout, stderr
sub cgi_run
{
	my ($cgi, $query) = @_;

	return run_cmd($^X, $cgi, "$query&$CGI_RANGE");
}

# Actions linked from the menu of the CGI home page
sub cgi_menu_actions
{
	my $cgi = shift;

	my ($rc, $out, $err) = cgi_run($cgi, 'db=all&action=home');
	my %seen = ();
	my @actions = grep { !$seen{$_}++ } ($out =~ /\?(db=[^&']*&action=[^&']*)/g);
	return sort @actions;
}

1;
