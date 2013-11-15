use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

use strict;

my @ALLOWED_ARGS = ('INSTALLDIRS','DESTDIR');

# Parse command line arguments and store them as environment variables
while ($_ = shift) {
	my ($k,$v) = split(/=/, $_, 2);
	if (grep(/^$k$/, @ALLOWED_ARGS)) {
		$ENV{$k} = $v;
	}
}
$ENV{DESTDIR} =~ s/\/$//;

# Default install path
my $DESTDIR = $ENV{DESTDIR} || '';
my $INSTALLDIRS = $ENV{INSTALLDIRS} || 'site';

WriteMakefile(
	'DISTNAME'	=> 'pgcluu',
	'NAME'		=> 'pgCluu',
	'VERSION_FROM'	=> 'pgcluu',
	'dist'  => {
			'COMPRESS'=>'gzip -9f', 'SUFFIX' => 'gz',
			'ZIP'=>'/usr/bin/zip','ZIPFLAGS'=>'-rl'
		   },
	'AUTHOR'       => 'Gilles Darold (gilles@darold.net)',
	'ABSTRACT'     => 'pgCluu - PostgreSQL performances auditing tool',
	'EXE_FILES'    => [ qw(pgcluu pgcluu_collectd) ],
	'MAN1PODS'     => { 'doc/pgCluu.pod' => 'blib/man1/pgcluu.1' },
	'DESTDIR'      => $DESTDIR,
	'INSTALLDIRS'  => $INSTALLDIRS,
	'clean'	       => {},
	'META_MERGE'   => {
		resources  => {
			homepage => 'http://pgcluu.darold.net/',
			repository  => {
				type => 'git',
				git => 'git@github.com:darold/pgcluu.git',
				web => 'http://pgcluu.darold.net/',
			},
		},
        }
);

