#!/usr/bin/perl

=head1 NAME

make_package.pl - build EPrints distribution packages

=head1 SYNOPSIS

make_package.pl [OPTIONS] <tag or branch>

=head1 OPTIONS

=over 8

=item --help

=item --rpm

Build an RPM package in addition to the tgz.

=item --deb

Build Debian packages in addition to the tgz.

=item --deb-unstable

=item --deb-stable

=item --package=eprints

The package name to use.

=item --source=git://github.com/eprints/eprints.git

The location to get the EPrints source from.

=item --prefix=/usr/share/eprints

The default installation path for EPrints.

=item --user=eprints

The default installation user for EPrints.

=item --group=eprints

The default installation group for EPrints.

=item --git

=item --gzip

=item --tar

=item --aclocal

=item --autoconf

=item --automake

=item --rpmbuild

Specify the location for the build tools.

=back

=cut

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;
use File::Temp;
use Cwd;
use File::Copy;
use File::Path qw( make_path );

my %opt = (
	git => 'git',
	gzip => 'gzip',
	tar => 'tar',
	aclocal => 'aclocal',
	autoconf => 'autoconf',
	automake => 'automake',
	rpmbuild => 'rpmbuild',
	debuild => 'dpkg-buildpackage',
	package => 'eprints',
	source => 'https://github.com/eprints/eprints3.4.git',
	prefix => ($ENV{PREFIX} || '/usr/share/eprints'),
	user => 'eprints',
	group => 'eprints',
);

GetOptions(\%opt,
	'git=s',
	'gzip=s',
	'tar=s',
	'aclocal=s',
	'autoconf=s',
	'automake=s',
	'rpmbuild=s',
	'debuild=s',
	'package=s',
	'source=s',
	'prefix=s',
	'user=s',
	'group=s',
	'rpm',
	'deb',
	'deb-stable',
	'deb-unstable',
	'help',
) or pod2usage(1);

pod2usage(0) if $opt{help};
pod2usage(1) if @ARGV != 1;

my $branch = shift @ARGV;

my $cwd = getcwd();
END {
	chdir($cwd) if defined $cwd;
};

make_path("$cwd/packages");

my $tmpdir = File::Temp->newdir;

chdir($tmpdir);

call(
	$opt{git},
	'clone',
	$opt{source},
	$opt{package},
);

chdir("$tmpdir/$opt{package}");

call(
	$opt{git},
	'checkout',
	$branch,
);

my $version;

open(my $fh, '<', 'perl_lib/EPrints.pm') or die "perl_lib/EPrints.pm: $!";
while(<$fh>)
{
	if (/\$VERSION/ && /(\d+\.\d+\.\d+)/)
	{
		$version = $1;
		last;
	}
}
close($fh);

my $package_name = "$opt{package}-$version";

call(
	$opt{aclocal},
);

call(
	$opt{autoconf},
);

call(
	$opt{automake},
	'--add-missing',
);

call(
	'./configure',
	'--prefix' => $opt{prefix},
	"--with-user=$opt{user}",
	"--with-group=$opt{group}",
	($opt{'deb-unstable'} ? '--with-debian-unstable' : ()),
	($opt{'deb-stable'} ? '--with-debian-stable' : ()),
);

call(
	'make',
	'dist-core',
);

call(
	'make',
	'dist-flavours',
);

if ($opt{rpm})
{
	call(
		$opt{rpmbuild},
		'-ta',
		"$package_name.tar.gz",
	);
}

if ($opt{deb})
{
	my $orig_tgz = "$opt{package}_$version.orig.tar.gz";

	mkdir("$tmpdir/build");
	chdir("$tmpdir/build");

	link("../$opt{package}/$package_name.tar.gz", $orig_tgz);

	call(
		$opt{tar},
		'-xzf',
		$orig_tgz,
	);

	chdir("$tmpdir/build/$package_name");
	call(
		$opt{debuild},
	);
	chdir("$tmpdir/build");

	copy("$opt{package}_${version}_all.deb", "$cwd/packages/");

	make_path("$cwd/packages/source");
	for(
		$orig_tgz,
		"$opt{package}_${version}_amd64.changes",
		"$opt{package}_${version}.debian.tar.gz",
		"$opt{package}_${version}.dsc"
	)
	{
		copy($_, "$cwd/packages/source/");
	}

	chdir("$tmpdir/$opt{package}");
}

unlink("$cwd/packages/$package_name.tar.gz");
unlink("$cwd/packages/$package_name-flavours.tar.gz");
copy("$package_name.tar.gz", "$cwd/packages/$package_name.tar.gz");
copy("$package_name-flavours.tar.gz", "$cwd/packages/$package_name-flavours.tar.gz");

chdir($cwd);

print "$package_name.tar.gz\n";
print "$package_name-flavours.tar.gz\n";

sub call
{
	my @cmd = @_;
	warn "@cmd\n";
	system(@cmd) == 0 or &cleanup;
}

sub cleanup
{
	chdir($cwd);
	die;
}
