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
(NOTE this is currently not used!)

=item B<--license-summary>

Filename to read license summary from (defaults to licenses/gplin.txt) - gets embedded wherever _B<>_LICENSE__ pragma occurs.
(NOTE this is currently not used!)

=item B<--list>

List all available versions.

=item B<--man>

Print the full manual page and then exit.

=item B<--win32>

Build a package that can be used to build a Win32 installer.

=item B<--revision>

Append a revision to the end of the output name.

=item B<--zip>

Use Zip as the packager (produces a .zip file).

=back

=cut

use Cwd;
use Getopt::Long;
use Pod::Usage;
use File::Path;
use File::Copy qw( cp move );

use strict;

my( $opt_revision, $opt_license, $opt_license_summary, $opt_list, $opt_zip, $opt_bzip, $opt_help, $opt_man, $opt_branch, $opt_force, $opt_win32 );

my $opt_svn = "https://svn.eprints.org/eprints";

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
	'svn' => \$opt_svn,
	'win32' => \$opt_win32,
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
my $package_version;
my $package_desc;
my $rpm_version;
my $package_ext = '.tar.gz';
$package_ext = '.zip' if $opt_zip;
$package_ext = '.tar.bz2' if $opt_bzip;
$package_ext = '.zip' if $opt_win32;

pod2usage( 2 ) if( scalar @ARGV != 1 );

my( $type ) = @ARGV;

my @date = gmtime();
my $date = sprintf( "%04d-%02d-%02d",
	$date[5] + 1900,
	$date[4] + 1,
	$date[3] );

if( $type eq "nightly" ) 
{ 
	$version_path = "/trunk";
	$package_version = "eprints-build-$date";
	$package_desc = "EPrints Nightly Build - $package_version";
	$opt_revision = 1;
	$rpm_version = "0.0.0";
}
elsif( $opt_branch )
{
	$version_path = "/branches/".$type;
	$package_version = "eprints-branch-$type-$date";
	$package_desc = "EPrints Branch Build - $package_version";
	$opt_revision = 1;
	my $result = `svn info $opt_svn$version_path/system/`;
	push @raw_args, "--force";
	if( !length( $result ) )
	{
		print "Could not find branch '$type'\n\n";
		print "Available branches:\n";
		print `svn ls $opt_svn/branches/`;
		print "\n";
		exit 1;
	}	
	$rpm_version = "0.0.0";
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
		exit 1;
	}
	$version_path = "/tags/".$type;
	$package_version = "eprints-".$ids{$type};
	$package_desc = "EPrints ".$ids{$type}." (".$codenames{$type}.") [Born on $date]";
	$rpm_version = $ids{$type};
	$rpm_version =~ s/-.*//; # Exclude beta/alpha/RC versioning
	$rpm_version ||= "0.0.0"; # Hmm, b0rked
}

erase_dir( "export" );

print "Exporting from SVN...\n";
my $originaldir = getcwd();

mkdir( "export" );

open( SVNINFO, "svn info $opt_svn$version_path/system/|" ) || die "Could not run svn info";
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
cmd( "svn export $opt_svn$version_path/release/ export/release/")==0 or die "Could not export system.\n";
cmd( "svn export $opt_svn$version_path/system/ export/system/")==0 or die "Could not export system.\n";

if( !-e "export/system/CHANGELOG" )
{
	# Still keep CHANGELOG when building pre-3.2 packages
	#
	if( $type eq "nightly" || $opt_branch )
	{
		cmd( "perl build_version_log.pl $opt_svn$version_path > export/system/CHANGELOG" )==0 or die "Could not build CHANGELOG.\n";
	}
	else
	{
		cmd( "perl build_version_log.pl --version $type > export/system/CHANGELOG" )==0 or die "Could not build CHANGELOG.\n";
	}
}

if( $opt_revision )
{
	$package_version .= "-r$revision";
}

if( $opt_win32 )
{
	$package_version .= "-win32";
}

my @args;
push @args, 'export'; # The source
push @args, 'package'; # The target
push @args, $package_version;
push @args, $package_desc;
push @args, $package_version;
push @args, $package_ext;
push @args, $rpm_version;

# I don't follow this code so it's commented out for now.
#
# Optional revision number (which is a pain because we *add* a value)
#if( $opt_revision )
#{
#	for(my $i = 0; $i < @raw_args; $i++)
#	{
#		if( $raw_args[$i] eq '--revision' )
#		{
#			splice(@raw_args, $i+1, 0, $revision);
#		}
#		elsif( $raw_args[$i] eq '-r' )
#		{
#			splice(@raw_args, $i, 1, '--revision', $revision);
#		}
#		elsif( $raw_args[$i] =~ s/^-([a-z]*)r([a-z]*)$/-$1$2/i )
#		{
#			splice(@raw_args,$i,1) unless length($1) or length($2);
#			unshift @raw_args, '--revision', $revision;
#		}
#		else
#		{
#			next;
#		}
#		last;
#	}
#}

if( $opt_win32 )
{
	cmd( "perl", "export/release/internal_makemsi.pl", @args );
}
else
{
	cmd( "perl", "export/release/internal_makepackage.pl", @args );
}

# stuff

print "Removing temporary directories...\n";
erase_dir( "export" );

my $filename = $package_version.$package_ext;
if( -e $filename )
{
	print "Moving package file into packages/ directory.\n";
	rename($filename, "packages/$filename");
}

my $cwd = getcwd();
if( $opt_win32 && $^O eq "MSWin32" && -e "srvany.exe" )
{
	chdir("packages");
	cmd("unzip","-oq","$package_version$package_ext");
	cp("../srvany.exe", "$package_version") or die "Missing srvany.exe?";
	chdir($package_version);
	cmd("candle","eprints.wsx");
	cmd("light","-ext","WixUIExtension","eprints.wixobj");
	move("eprints.msi","../$package_version.msi");
	chdir("$cwd/packages");
	erase_dir($package_version);
	print "$package_version.msi\n";
}
chdir($cwd);

print "$package_version$package_ext\n";

exit;


sub erase_dir
{
	my( $dirname ) = @_;

	if (-d $dirname )
	{
		rmtree($dirname) or
			die "Couldn't remove ".$dirname." dir.\n";
	}
}


sub cmd
{
	print join(' ', @_)."\n";

	return system( @_ );
}

