use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

use strict;

my @ALLOWED_ARGS = ('INSTALLDIRS','DESTDIR','PREFIX','RSCDIR','REPORTDIR','CGIDIR','CONFDIR','PIDDIR','STATDIR','APACHECONF','MANDIR','DOCDIR','SYSTEMDDIR','RETENTION', 'BINDIR');

# Parse command line arguments and store them as environment variables
while ($_ = shift) {
	my ($k,$v) = split(/=/, $_, 2);
	if (grep(/^$k$/, @ALLOWED_ARGS)) {
		$ENV{$k} = $v;
	}
}
$ENV{DESTDIR} =~ s/\/$//;

# Perform some checks
if (exists $ENV{INSTALLDIRS} && $ENV{INSTALLDIRS} !~ /^(site|vendor)$/) {
	die "ERROR: INSTALLDIRS value must be 'site' or 'vendor'.\n";
}

# Default install path
my $DESTDIR = $ENV{DESTDIR} || '';
my $PREFIX  = $ENV{PREFIX} || '/usr/local';
my $INSTALLDIRS = $ENV{INSTALLDIRS} || 'site';
my $CONFDIR = $ENV{CONFDIR} || "$DESTDIR$PREFIX/etc";
my $CONFDIR_SRVC = $ENV{CONFDIR} || "$PREFIX/etc";
if ($INSTALLDIRS eq 'vendor') {
	$PREFIX = $ENV{PREFIX} || '/usr';
	$CONFDIR = $ENV{CONFDIR} || "$DESTDIR/etc";
	$CONFDIR_SRVC = $ENV{CONFDIR} || "/etc";
}
my $BINDIR = $ENV{BINDIR} || "$DESTDIR$PREFIX/bin";
my $PIDDIR = $ENV{PIDDIR} || "$DESTDIR/var/run/postgresql";
my $STATDIR = $ENV{STATDIR} || "$DESTDIR/var/lib/pgcluu/data";
my $REPORTDIR = $ENV{REPORTDIR} || "$DESTDIR/var/lib/pgcluu/report";
my $RSCDIR = $ENV{RSCDIR} || "$DESTDIR$PREFIX/share/pgcluu";
my $CGIDIR = $ENV{CGIDIR} || "$DESTDIR$PREFIX/lib/cgi-bin";
my $APACHECONF = $ENV{APACHECONF} || "$CONFDIR/apache2/conf-available";
my $MANDIR = $ENV{MANDIR} || "$DESTDIR$PREFIX/share/man";
my $DOCDIR = $ENV{DOCDIR} || "$DESTDIR$PREFIX/share/doc";
my $SYSTEMDDIR = $ENV{SYSTEMDDIR} || "$DESTDIR/lib/systemd/system";
my $RETENTION = $ENV{RETENTION} || 30;
my $STATDIR_SRVC = $ENV{STATDIR} || "/var/lib/pgcluu/data";
my $REPORTDIR_SRVC = $ENV{REPORTDIR} || "/var/lib/pgcluu/report";
my $PIDDIR_SRVC = $ENV{PIDDIR} || "/var/run/postgresql";
my $BINDIR_SRVC = $ENV{BINDIR} || "$PREFIX/bin";

# Try to detect RPM specific directory installation
my $RPM_LIKE = 0;
if ($SYSTEMDDIR eq '/usr/lib/systemd/system' && ! -d '/usr/lib/systemd/system') {
	$SYSTEMDDIR = $ENV{SYSTEMDDIR} || '/lib/systemd/system';
}

# Setup ok. generating sendmailanalyzer.conf config file
unless(open(OUTCFG, ">pgcluu.conf")) {
	print "\nError: can't write config file pgcluu.conf, $!\n";
	exit 0;
}

print OUTCFG qq{
#-----------------------------------------------------------------------------
# Configuration file for pgCluu scripts. Most of the directives are used by
# the CGI script execpt those starting by STATS_COLLECTD_ or STATS_REPORT_
#-----------------------------------------------------------------------------

# Defined the base URL where resources files are stored
# Resources files are css and javascript files.
# Default is to automatically set the relative path.
RSC_BASE	/pgcluu/rsc/

# Path to the main pgCluu data directory. This path
# must be readable by the user running your httpd server.
INPUT_DIR	$STATDIR_SRVC

# Space or comma separated list of database that must be reported.
# Value can be any valid perl regexp
#INCLUDE_DB	[^p].*

# Space or comma separated list of table that must be reported.
# Value can be any valid perl regexp
#INCLUDE_TB	tmp.*

# Space or comma separated list of network device that must be reported.
# Value can be any valid perl regexp
#INCLUDE_IFACE	lo

# Space or comma separated list of disk device that must be reported.
# Value can be any valid perl regexp
#INCLUDE_DEV    sda

# By default pgcluu look at mm/dd/yy format in header line of sar file.
# When enabled pgcluu will look at dd/mm/yy format.
REVERT_DATE	0

# Max number of days in a graph. Using default pgcluu_collectd 1 minute
# interval each, daily graph will have 1440 points. Having too much data
# to render is not a good point for performances with the current code.
# The user can set is own graph period, we are limit it to the first seven
# days of the selected period. This mean a maximum of 10080 points for one
# week, this seems a safe limit. Feel free to increase or reduce the limit
# following the server and client resources.
MAX_RENDERED_DAYS	7

# Retention limit in the statistics directory expressed in number of days.
# This directive is only used by pgcluu_collectd in incremental mode. Only
# the last number of days will be preserved, obsolete directories will be
# removed. It can be used to preserved disk space. Default store 30 days.
STATS_COLLECTD_RETENTION	$RETENTION

# Retention limit in the report directory (static html) expressed in number
# of days. This directive is only used by pgcluu in incremental mode. Only
# the last number of days will be preserved, obsolete directories will be
# removed. It can be used to preserved disk space. Default store 30 days.
STATS_REPORT_RETENTION	$RETENTION

# This directive must be enabled in CGI mode. In this case pgcluu must be
# run periodically at least each 5 minutes to build and update cached stats.
STATS_REPORT_CACHING	0

# Directory where the pgCluu reports must be saved
STATS_REPORT_OUTDIR	$REPORTDIR_SRVC
};
close(OUTCFG);

unless(open(INST, ">install_all.sh")) {
	print "\nError: can't write post install file install_all.sh, $!\n";
	exit 0;
}
print INST qq{#!/bin/sh
if [ ! -d "$DESTDIR/bin" ]; then
	mkdir -p $DESTDIR/bin
fi
if [ ! -d "$CONFDIR" ]; then
	mkdir -p $CONFDIR
fi
if [ ! -d "$RSCDIR/rsc" ]; then
	mkdir -p $RSCDIR/rsc
fi
if [ ! -d "$MANDIR/man1" ]; then
	mkdir -p $MANDIR/man1
fi
if [ ! -d "$DOCDIR/pgcluu" ]; then
	mkdir -p $DOCDIR/pgcluu
fi
if [ ! -d "$DOCDIR/pgcluu/examples" ]; then
	mkdir -p $DOCDIR/pgcluu/examples
fi
if [ ! -d "$CGIDIR" ]; then
	mkdir -p $CGIDIR
fi
if [ ! -d "$APACHECONF" ]; then
	mkdir -p $APACHECONF
fi
if [ ! -d "$SYSTEMDDIR" ]; then
	mkdir -p $SYSTEMDDIR
fi
if [ ! -d "$STATDIR" ]; then
	mkdir -p $STATDIR
	chown postgres: $STATDIR
fi
if [ ! -d "$REPORTDIR" ]; then
	mkdir -p $REPORTDIR
	chown postgres: $REPORTDIR
fi
if [ ! -d "$PIDDIR" ]; then
	mkdir -p $PIDDIR
	chown postgres: $PIDDIR
fi

# Do not override existing Apache configuration file
if [ ! -f "$APACHECONF/pgcluu.conf" ]; then
	echo "
Alias /pgcluu $RSCDIR/
<Directory $RSCDIR/>
    Options FollowSymLinks MultiViews
    AllowOverride None
    Require local
    #Require ip 192.1.168.0/24
</Directory>" > $APACHECONF/pgcluu.conf
fi

install -m 755 pgcluu_collectd    $DESTDIR/bin/
install -m 755 pgcluu	     $DESTDIR/bin/
install -m 755 cgi-bin/pgcluu.cgi $CGIDIR/
install -m 644 cgi-bin/rsc/*      $RSCDIR/rsc/
install -m 644 LICENSE	    $DOCDIR/pgcluu/
install -m 644 README	     $DOCDIR/pgcluu/
install -m 644 ChangeLog	     $DOCDIR/pgcluu/changelog
install -m 644 pgcluu_collectd.service $DOCDIR/pgcluu/examples/
install -m 644 pgcluu.service	  $DOCDIR/pgcluu/examples/
install -m 644 pgcluu.timer	    $DOCDIR/pgcluu/examples/
install -m 644 pgcluu.conf	     $DOCDIR/pgcluu/examples/pgcluu.conf.dist
# Do not override existing configuration file
if [ ! -f "$CONFDIR/pgcluu.conf" ]; then
	install -m 644 pgcluu.conf $CONFDIR/pgcluu.conf
fi
gzip -f $DOCDIR/pgcluu/changelog
if [ ! -e "$MANDIR/man1/pgcluu.1p.gz" ]; then
	gzip -f $MANDIR/man1/pgcluu.1p
fi
install -m 644 pgcluu_collectd.service $SYSTEMDDIR/
install -m 644 pgcluu.service $SYSTEMDDIR/
install -m 644 pgcluu.timer $SYSTEMDDIR/
if [ ! -e "/etc/apache2/conf-enabled/pgcluu.conf" ]; then
	cd /etc/apache2/conf-enabled/
	ln -s ../conf-available/pgcluu.conf pgcluu.conf
fi
cd $MANDIR/man1/
ln -s pgcluu.1p.gz pgcluu_collectd.1p.gz
};
close(INST);
`chmod 755 install_all.sh`;

`perl -p -i -e 's#my \\\$CONFIG_FILE .*#my \\\$CONFIG_FILE     = "$CONFDIR_SRVC/pgcluu.conf";#' cgi-bin/pgcluu.cgi pgcluu_collectd pgcluu`;
`perl -p -i -e 's#my \\\$PIDFILE .*=.*#my \\\$PIDFILE     = "$PIDDIR_SRVC/pgcluu_collectd.pid";#' pgcluu_collectd`;
`perl -p -i -e 's#/var/lib/pgcluu/data#$STATDIR_SRVC#' pgcluu.service pgcluu_collectd.service`;
`perl -p -i -e 's#/var/lib/pgcluu/report#$REPORTDIR_SRVC#' pgcluu.service`;
`perl -p -i -e 's#/usr/bin#$BINDIR_SRVC#' pgcluu.service pgcluu_collectd.service`;
`perl -p -i -e 's#/var/run/postgresql#$PIDDIR_SRVC#' pgcluu_collectd.service`;

my %merge_compat = ();
if ($ExtUtils::MakeMaker::VERSION >= 6.46) {
	%merge_compat = (
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
}

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
	'MAN1PODS'     => { 'doc/pgCluu.pod' => 'blib/man1/pgcluu.1p' },
	'DESTDIR'      => $ENV{DESTDIR},
	'INSTALLDIRS'  => $ENV{INSTALLDIRS},
	'clean'	       => {FILES => "install_all.sh"},
	%merge_compat
);

sub MY::install {
	my $self = shift;

	my $string = $self->MM::install;
	$string =~ s/(pure_install\s+)(.*)/$1 install_all $2/;

	return $string;
}

sub MY::postamble {
	my $postamble = <<'END';
install_all: install_all.sh
	sh install_all.sh
END
	return $postamble;
}

if (!$ENV{QUIET}) {
	print "Done...\n\n";
	print "Now type 'make && make install'\n\n";
}

