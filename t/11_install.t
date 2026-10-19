#!/usr/bin/perl
# Custom installation must activate the configuration inside the chosen tree.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Test::More;
use File::Copy qw(copy);
use File::Path qw(make_path);
use Cwd qw(getcwd);
use PgcluuTest;

my ($make_rc) = run_cmd('make', '--version');
plan skip_all => 'make is not installed' if ($make_rc != 0);

my $root = root_dir();
my $tmp = tmp_dir();
my $src = "$tmp/source";
my $dest = "$tmp/install";
make_path("$src/doc", "$src/cgi-bin/rsc", "$dest/data", "$dest/report", "$dest/pid");
foreach my $f (qw(Makefile.PL pgcluu pgcluu_collectd README LICENSE ChangeLog
    pgcluu.service pgcluu.timer pgcluu_collectd.service doc/pgCluu.pod
    cgi-bin/pgcluu.cgi)) {
    copy("$root/$f", "$src/$f") or die "copy $f: $!";
}
opendir(my $dh, "$root/cgi-bin/rsc") or die $!;
foreach my $f (grep { -f "$root/cgi-bin/rsc/$_" } readdir($dh)) {
    copy("$root/cgi-bin/rsc/$f", "$src/cgi-bin/rsc/$f") or die "copy $f: $!";
}
closedir($dh);

my $cwd = getcwd();
chdir($src) or die $!;
my ($rc, $out, $err) = run_cmd($^X, 'Makefile.PL', "DESTDIR=$dest",
    "CONFDIR=$dest/etc", "PIDDIR=$dest/pid", "STATDIR=$dest/data",
    "REPORTDIR=$dest/report", "RSCDIR=$dest/share/pgcluu", "CGIDIR=$dest/cgi-bin",
    "APACHECONF=$dest/apache/custom-available", "MANDIR=$dest/man",
    "DOCDIR=$dest/doc", "SYSTEMDDIR=$dest/systemd");
is($rc, 0, 'custom Makefile.PL succeeds') or diag($out . $err);
my $script = do { local $/; open(my $fh, '<', 'install_all.sh') or die $!; <$fh> };
# Do not execute an installer which could write to the host Apache directory.
my $confined = unlike($script, qr{/etc/apache2/conf-enabled}, 'Apache activation is not hardcoded to the host');
SKIP: {
    skip('installer is not confined to the custom Apache tree', 2) if (!$confined);
    ($rc, $out, $err) = run_cmd('make', 'install');
    is($rc, 0, 'custom make install succeeds') or diag($out . $err);
    ok(-l "$dest/apache/conf-enabled/pgcluu.conf" && -f "$dest/apache/conf-enabled/pgcluu.conf",
        'enabled Apache symlink resolves to the installed custom configuration');
}
chdir($cwd) or die $!;
done_testing();
