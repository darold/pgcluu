#!/usr/bin/env perl
#-----------------------------------------------------------------------------
#
# Script used to update javascript and css files embedded into pgcluu.
# It will replace all content after the __DATA__ in the right order with
# the files content stored into the resources/min/ directory.
#
# This script must be executed from the main source repository as follow:
# 	
# This script must be executed from the main source repository as follow:
# 	./tools/updt_embedded_rsc.pl
#
# The fontawesome.css must also embedded the TrueType font, this is done
#-----------------------------------------------------------------------------
use strict;

my $RSC_DIR       = 'resources';
my $PGCLUU_PROG = 'pgcluu';
my $DEST_TMP_FILE = 'pgcluu.new';
my $CGI_DEST_DIR = 'cgi-bin/rsc';

# Ordered resources files list
my @rsc_list = qw(jquery.jqplot.css jquery.js jquery.jqplot.js jqplot.pieRenderer.js jqplot.barRenderer.js jqplot.dateAxisRenderer.js jqplot.canvasTextRenderer.js jqplot.categoryAxisRenderer.js jqplot.canvasAxisTickRenderer.js jqplot.canvasAxisLabelRenderer.js jqplot.highlighter.js jqplot.highlighter.js jqplot.cursor.js jqplot.pointLabels.js bean.js underscore.js bootstrap.css bootstrap-datetimepicker.css fontawesome.css bootstrap.js bootstrap-datetimepicker.js pgcluu_slide.js pgcluu.css pgcluu.js sorttable.js w3.js);
my @min_rsc_list = ();

if (!-d $RSC_DIR) {
	die "FATAL: can't find directory: $RSC_DIR.\n";
}

# Apply patch on jquery.jqplot.js to fix infinite loop
# May be removed with next jqplot release update
`patch -r - -s  -N resources/jquery.jqplot.js -i resources/patch-jquery.jqplot.js`;

# Apply patch on sorttable.js to allow sort on human size
# and always start sort in reverse order
`patch -r - -s  -N resources/sorttable.js -i resources/patch-sorttable.js`;

# Generate all minified resources files
mkdir "$RSC_DIR/min";
foreach my $f (@rsc_list) {
	my $dest = $f;
	$dest =~ s/\.(js|css)$/.min.$1/;
	push(@min_rsc_list, $dest);
	# minify resources files
	`yui-compressor $RSC_DIR/$f -o $RSC_DIR/min/$dest`;
}

# Embedded fontawesome webfont into the CSS file as base64 data
print `base64 -w 0 $RSC_DIR/font/FontAwesome.otf > $RSC_DIR/font/FontAwesome.otf.b64`;
open(IN, "$RSC_DIR/font/FontAwesome.otf.b64") or die "FATAL: can't open file $RSC_DIR/font/FontAwesome.otf.b64, $!\n";
my $b64_font = <IN>;
close(IN);

# Update minimized fontawesome.css file
open(IN, "$RSC_DIR/min/fontawesome.min.css") or die "FATAL: can't open file $RSC_DIR/min/fontawesome.min.css\n";
my @content = <IN>;
close(IN);
open(OUT, ">$RSC_DIR/min/fontawesome.min.css") or die "FATAL: can't write to file $RSC_DIR/min/fontawesome.min.css\n";
foreach my $l (@content) {
	$l =~ s|;src:url.* format.* format\('svg'\);|;src: url('data:font\/opentype;charset=utf-8;base64,$b64_font') format('truetype');|;
	print OUT $l;
}
close(OUT);

if (!-e $PGCLUU_PROG) {
	die "FATAL: can't find pgcluu script: $PGCLUU_PROG\n";
}

# Extract content of pgcluu script until __DATA__ is found
my $content = '';
open(IN, $PGCLUU_PROG) or die "FATAL: can't open file $PGCLUU_PROG, $!\n";
while (<IN>) {
	last if (/^__DATA__$/);
	$content .= $_;
}
close(IN);

# Write script base to destination file
open(OUT, ">$DEST_TMP_FILE") or die "FATAL: can't write to file $DEST_TMP_FILE, $!\n";
print OUT $content;
print OUT "__DATA__\n";

# Append each minified resources file
foreach my $f (@min_rsc_list) {
	print OUT "\nWRFILE: $f\n\n";
	open(IN, "$RSC_DIR/min/$f") or die "FATAL: can't open file $RSC_DIR/min/$f, $!\n";
	my @tmp = <IN>;
	close(IN);
	print OUT @tmp;
}
close(OUT);

# Clobber original pgcluu file.
rename($DEST_TMP_FILE, $PGCLUU_PROG) or die "FATAL: can't rename $DEST_TMP_FILE into $PGCLUU_PROG\n";

# Move minified resources files in the CGI directory
`mv $RSC_DIR/min/* $CGI_DEST_DIR/`;

# Change attibut of the script
`chmod 755 $PGCLUU_PROG`;

exit 0;
