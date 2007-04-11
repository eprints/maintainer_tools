#!/usr/bin/perl -w

# nb.
#
# cvs tag eprints2-2-99-0 system docs_ep2
#
# ./makepackage.pl  eprints2-2-99-0
#
# scp eprints-2.2.99.0-alpha.tar.gz webmaster@www:/home/www.eprints/software/files/eprints2/

=head1 NAME

B<makepackage.pl> - Make an EPrints tarball

=head1 SYNOPSIS

B<makepackage.pl> <version OR nightly>

=head1 ARGUMENTS

=over 4

=item I<version>

EPrints version to build or 'nightly' to build nightly version (current trunk HEAD).

=back

=head1 OPTIONS

=over 8

=item B<--help>

Print a brief help message and exit.

=item B<--branch>

Export from the branch version rather than tag (branches are major-version only).

=item B<--bzip>

Use Tar-Bzip as the packager (produces a tar.bz2 file).

=item B<--force>

Force a package build, even if it doesn't exist in versions.txt.

=item B<--license>

Filename to read license from (defaults to licenses/gpl.txt)

=item B<--license-summary>

Filename to read license summary from (defaults to licenses/gplin.txt) - gets embedded wherever _B<>_LICENSE__ pragma occurs.

=item B<--list>

List all available versions.

=item B<--man>

Print the full manual page and then exit.

=item B<--revision>

Append a revision to the end of the output name.

=item B<--zip>

Use Zip as the packager (produces a .zip file).

=back

=cut

use Cwd;
use Getopt::Long;
use Pod::Usage;
use strict;
use warnings;

my( $opt_revision, $opt_license, $opt_license_summary, $opt_list, $opt_zip, $opt_bzip, $opt_help, $opt_man, $opt_branch, $opt_force );

my @raw_args = @ARGV;

GetOptions(
	'help' => \$opt_help,
	'man' => \$opt_man,
	'revision' => \$opt_revision,
	'branch' => \$opt_branch,
	'license=s' => \$opt_license,
	'license-summary=s' => \$opt_license_summary,
	'list' => \$opt_list,
	'zip' => \$opt_zip,
	'bzip' => \$opt_bzip,
	'force' => \$opt_force,
) || pod2usage( 2 );

pod2usage( 1 ) if $opt_help;
pod2usage( -exitstatus => 0, -verbose => 2 ) if $opt_man;

my %codenames= ();
my %ids = ();
open( VERSIONS, "versions.txt" ) || die "can't open versions.txt: $!";
while(<VERSIONS>)
{
	chomp;
	$_ =~ s/\s*#.*$//;
	next if( $_ eq "" );
	$_ =~ m/^\s*([^\s]*)\s*([^\s]*)\s*(.*)\s*$/;
	$ids{$1} = $2;
	$codenames{$1} = $3;
}
close VERSIONS;

if( $opt_list )
{
	print "I can build the following versions:\n".join("\n",sort keys %codenames)."\n\n";
	print "To add a version edit 'versions.txt'\n";
	exit;
}

my $version_path;
my $package_file;
my $package_ext = '.tar.gz';
$package_ext = '.zip' if $opt_zip;
$package_ext = '.tar.bz2' if $opt_bzip;

pod2usage( 2 ) if( scalar @ARGV != 1 );

my( $type ) = @ARGV;

my $date = `date +%Y-%m-%d`;
chomp $date;

if( $type eq "nightly" ) 
{ 
	$version_path = "/trunk";
	$package_file = "eprints-build-$date";
	$opt_revision = 1;
}
else
{
	if( $opt_force and !defined $codenames{$type} )
	{
		$codenames{$type} = $ids{$type} = $type;
	}
	if( !defined $codenames{$type} )
	{
		print "Unknown codename\n";
		print "Available:\n".join("\n",sort keys %codenames)."\n\n";
		exit;
	}
	if( $opt_branch )
	{
		$version_path = "/branches/".$type;
		$package_file = "eprints-branch-$type";
		$opt_revision = 1;
	}
	else
	{
		$version_path = "/tags/".$type;
		$package_file = "eprints-".$ids{$type};
	}
	print "YAY - $ids{$type}\n";
}

erase_dir( "export" );

print "Exporting from SVN...\n";
my $originaldir = getcwd();

mkdir( "export" );

open( SVNINFO, "svn info http://trac.eprints.org/svn/eprints$version_path/system/|" ) || die "Could not run svn info";
my $revision;
while( <SVNINFO> )
{
	next unless( m/^Revision:\s*(\d+)/ );
	$revision = $1;
}
close SVNINFO;
if( !defined $revision ) 
{
	die 'Could not see revision number in svn info output';
}
cmd( "svn export http://trac.eprints.org/svn/eprints$version_path/release/ export/release/")==0 or die "Could not export system.\n";
cmd( "svn export http://trac.eprints.org/svn/eprints$version_path/system/ export/system/")==0 or die "Could not export system.\n";

if( $opt_revision )
{
	$package_file .= "-r$revision";
}

push @raw_args, 'export'; # The source
push @raw_args, 'package'; # The target
# Optional revision number (which is a pain because we *add* a value)
if( $opt_revision )
{
	for(my $i = 0; $i < @raw_args; $i++)
	{
		if( $raw_args[$i] eq '--revision' )
		{
			splice(@raw_args, $i+1, 0, $revision);
		}
		elsif( $raw_args[$i] eq '-r' )
		{
			splice(@raw_args, $i, 1, '--revision', $revision);
		}
		elsif( $raw_args[$i] =~ s/^-([a-z]*)r([a-z]*)$/-$1$2/i )
		{
			splice(@raw_args,$i,1) unless length($1) or length($2);
			unshift @raw_args, '--revision', $revision;
		}
		else
		{
			next;
		}
		last;
	}
}

cmd( "export/release/internal_makepackage.pl", @raw_args );

# stuff

print "Removing temporary directories...\n";
erase_dir( "export" );

my( $rpm_file, $srpm_file);

if( $< != 0 )
{
	print "Not running as root, won't build RPM!\n";
}
elsif( system('which rpmbuild') != 0 )
{
	print "Couldn't find rpmbuild in path, won't build RPM!\n";
}
else
{
	open(my $fh, "rpmbuild -ta $package_file$package_ext|")
		or die "Error executing rpmbuild: $!";
	while(<$fh>) {
		print $_;
		if( /^Wrote:\s+(\S+.src.rpm)/ )
		{
			$srpm_file = $1;
		}
		elsif( /^Wrote:\s+(\S+.rpm)/ )
		{
			$rpm_file = $1;
		}
	}
	close $fh;
}

print "Done.\n";
print "$package_file$package_ext\n";
if( $rpm_file )
{
	print "rpm --addsign $rpm_file $srpm_file\n";
	print "$rpm_file\n";
	print "$srpm_file\n";
}

exit;


sub erase_dir
{
	my( $dirname ) = @_;

	if (-d $dirname )
	{
		cmd( "/bin/rm -rf ".$dirname ) == 0 or 
			die "Couldn't remove ".$dirname." dir.\n";
	}
}


sub cmd
{
	print join(' ', @_)."\n";

	return system( @_ );
}

