#!/usr/bin/perl -w

my $package = $ARGV[0];

my $base = "/tmp/ep_testing";

# step one clean up any old install

clean_up();

run( "mkdir $base" );

run( "mkdir $base/src/" );

run( "mkdir $base/install/" );

run( "cp $package $base/src/eprints.tgz" );

test_chdir( "$base/src" );

run( "tar xzvf eprints.tgz" );

my $dh;
opendir( $dh, "$base/src" );
my $dir;
while( my $file = readdir( $dh ) )
{
	next unless -d "$base/src/$file";
	next if $file eq ".";
	next if $file eq "..";
	$dir = "$base/src/$file";
}
closedir( $dh );

if( !defined $dir )
{
	die( "Could not find untar'd eprints distribution." );
}

test_chdir( $dir );

my $group = getgrgid($));
my $user = getpwuid($>);

run( "./configure --prefix=$base/install --with-user=$user --with-group=$group" );

run( "./install.pl" );

# Installed!







test_chdir( "$base/install" );

my $id = "ep_auto_test";
my $bin = "$base/install/bin";
run( "(".<<END.") | $bin/epadmin create" );
echo ep_auto_test; 
echo '';
hostname;
echo '';
echo '';
echo cjg\@ecs.soton.ac.uk;
echo My Archive;
echo '';

echo ''; # conf db?
echo '';
echo '';
echo '';
echo '';
echo '';
echo Secret23;
echo '';

echo ''; # create db?
echo ''; # root pass?
echo ''; # create tables

echo ''; # init user
echo ''; 
echo ''; 
echo 'admin';  #password
echo 'chris\@totl.net'; 

echo ''; 
echo ''; 
echo ''; 

END

run( "$base/install/testdata/bin/import_test_data ep_auto_test --verbose" );
run( "$bin/generate_views ep_auto_test --verbose" );
run( "$bin/generate_abstracts ep_auto_test --verbose" );

run( "$bin/indexer start" );
run( "$bin/indexer stop" );

#clean_up();

exit 0;






sub clean_up
{
	run( "rm -rf $base", 1 );
	run( "mysqladmin drop ep_auto_test -u root --force", 1 );
}


sub run
{
	my( $cmd, $dont_check ) = @_;

	print "% $cmd\n";

	open( CMD, "$cmd|" ) || die "Couldn't run: $cmd";
	while( <CMD> ) 
	{ 
		print ": $_"; 
	}
	close CMD;

	if ($? == -1) 
	{
		print "failed to execute: $!\n";
		exit( 1 ) unless( $dont_check );
	}
	elsif ($? & 127) 
	{
		printf( "child died with signal %d, %s coredump\n",
			($? & 127),  ($? & 128) ? 'with' : 'without' );
		exit( 1 ) unless( $dont_check );
	}
	else 
	{
		my $v = $? >> 8;
		if( $v ) 
		{
			printf( "child exited with value %d\n", $v );
			exit( 1 ) unless( $dont_check );
		}
	}

}

sub test_chdir
{
	my( $dir ) = @_;

	print "Changing dir to: $dir\n";
	chdir( $dir );
}
