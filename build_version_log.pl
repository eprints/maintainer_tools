#!/usr/bin/perl -w

use strict;

use Getopt::Long;
use Pod::Usage;
use XML::LibXML;

my $opt_version;
my $opt_branch;

GetOptions(
	"version=s" => \$opt_version,
	"branch=s" => \$opt_branch,
) or pod2usage(1);

our %HACKERS = (
	cjg => 'Christopher Gutteridge <cjg@ecs.soton.ac.uk>',
	tmb => 'Timothy Miles-Board <tmb@ecs.soton.ac.uk>',
	tdb01r => 'Timothy David Brody <tdb01r@ecs.soton.ac.uk>',
	dct05r => 'Dave Tarrant <davetaz@ecs.soton.ac.uk>',
	'af05v@ecs.soton.ac.uk' => 'Adam Field <af05v@ecs.soton.ac.uk>',
	moj199 => 'Mike Jewel',
);

our @VERSIONS = &read_versions( $opt_version );

our $TAGS = "https://svn.eprints.org/eprints/tags";
our $BRANCHES = "https://svn.eprints.org/eprints/branches";
our $TRUNK = "https://svn.eprints.org/eprints/trunk";

&main;

sub main
{
	my @infos;
	foreach my $i (0..$#VERSIONS)
	{
		push @infos, info( "$TAGS/".$VERSIONS[$i]->{tag} );
		print STDERR "Pass 1 of 2: version $i of ".@VERSIONS."  \r";
	}

	if( $opt_branch )
	{
		my $branch_info = info( "$BRANCHES/$opt_branch" );
		print "EPrints (r".$branch_info->{last_changed_rev}.")\n";
		print "-" x 79, "\n\n";

		foreach my $i (0..$#VERSIONS)
		{
			if( $infos[$i]->{last_changed_rev} > $branch_info->{last_changed_rev} )
			{
				splice(@VERSIONS,$i);
				splice(@infos,$i);
				last;
			}
		}

		my $prev_info = $infos[$#infos];
		my $range = $branch_info->{last_changed_rev} . ":" . $prev_info->{last_changed_rev};
		my $revisions = revisions( "$BRANCHES/$opt_branch", $range );
		print_by_author( $revisions );
		print "\n";
	}
	elsif( !$opt_version || $opt_version eq "nightly" )
	{
		my $nightly_info = info( $TRUNK );
		print "EPrints (r".$nightly_info->{last_changed_rev}.")\n";
		print "-" x 79, "\n\n";
		my $prev_info = $infos[$#infos];
		my $range = $nightly_info->{last_changed_rev} . ":" . $prev_info->{last_changed_rev};
		my $revisions = revisions( $TRUNK, $range );
		print_by_author( $revisions );
		print "\n";
	}

	foreach my $i (reverse 0..$#VERSIONS)
	{
		print STDERR "Pass 2 of 2: version ".(@VERSIONS-$i)." of ".@VERSIONS."  \r";
		my $version = $VERSIONS[$i];
		my $info = $infos[$i];
		print "EPrints (".$version->{version}.")\n";
		print "-" x 79, "\n\n";
		if( $i != 0 )
		{
			my $prev_info = $infos[$i-1];
			my $range = $info->{last_changed_rev} . ":" . $prev_info->{last_changed_rev};
			my $revisions = revisions( "$TAGS/".$version->{tag}, $range );
			print_by_author( $revisions );
			print "\n";
		}
		print_tag_line( $info );
		print "\n";
	}
}

sub read_versions
{
	my( $upto_version ) = @_;

	my @versions;

	my $filename = "versions.txt";
	open(my $fh, "<", $filename) or die "Error opening $filename: $!";
	while(<$fh>)
	{
		chomp;
		next if /^\s*#/;
		next if /^\s*$/;
		my( $tag, $version, $name ) = split /\s+/, $_, 3;
		next if !defined $name;
		push @versions, {
			tag => $tag,
			version => $version,
			name => $name,
		};
		last if defined $upto_version && $version eq $upto_version;
	}
	close($fh);

	return @versions;
}

sub info
{
	my( $url ) = @_;

	my $info = {};

	my $cmd = "svn info ".quotemeta($url);

	open(my $fh, "$cmd|") or die "Error opening $cmd: $!";
	while(<$fh>)
	{
		chomp;
		next if $_ eq "";
		my( $key, $value ) = split /:\s*/, $_, 2;
		$key =~ s/ /_/g;
		$key = lc($key);
		$info->{$key} = $value;
	}
	close($fh);

	return $info;
}

sub revisions
{
	my( $url, $range ) = @_;

	my $revisions = [];

	my $cmd = "svn log -v --xml -r $range ".quotemeta($url);

	open(my $fh, "$cmd|") or die "Error opening $cmd; $!";
	my $xml = join "", <$fh>;
	close($fh);

	my $doc = XML::LibXML->new->parse_string( $xml );
	$xml = $doc->documentElement;

	foreach my $logentry ($xml->getElementsByTagName( "logentry" ))
	{
		my $revision = {};
		push @$revisions, $revision;
		$revision->{revision} = $logentry->getAttribute( "revision" );
		foreach my $node ($logentry->childNodes)
		{
			my $name = $node->nodeName;
			if( $name eq "author" )
			{
				$revision->{author} = $node->textContent;
			}
			elsif( $name eq "date" )
			{
				$revision->{date} = $node->textContent;
			}
			elsif( $name eq "msg" )
			{
				$revision->{msg} = $node->textContent;
			}
			elsif( $name eq "paths" )
			{
				$revision->{paths} = [];
				foreach my $path_node ($node->childNodes)
				{
					next if $path_node->nodeName ne "path";
					my $path = {};
					push @{$revision->{paths}}, $path;
					$path->{action} = $path_node->getAttribute( "action" );
					$path->{kind} = $path_node->getAttribute( "kind" );
					$path->{copyfrom_path} = $path_node->getAttribute( "copyfrom-path" );
					$path->{copyfrom_rev} = $path_node->getAttribute( "copyfrom-rev" );
					$path->{path} = $path_node->textContent;
				}
			}
		}
	}

	return $revisions;
}

sub print_tag_line
{
	my( $info ) = @_;

	print "-- tagged-by";

	my $author = $info->{last_changed_author};
	if( !defined $author )
	{
		$author = "cvs2svn";
	}
	if( exists $HACKERS{$author} )
	{
		print " $HACKERS{$author}";
	}
	else
	{
		print " $author";
	}
	print "  $info->{last_changed_date}\n";
}

sub print_by_author
{
	my( $revisions ) = @_;

	my %authors;
	foreach my $revision (@$revisions)
	{
		next if !defined $revision->{author};
		my $author = $revision->{author};
		push @{$authors{$author}||=[]}, $revision;
	}

	my $first = 1;
	foreach my $author (sort keys %authors)
	{
		print "\n" if !$first;
		$first = 0;
		if( exists $HACKERS{$author} )
		{
			print "$HACKERS{$author}\n";
		}
		else
		{
			print "$author\n";
		}
		my %SEEN;
		foreach my $revision (@{$authors{$author}})
		{
			my $msg = $revision->{msg};
			$msg =~ s/^(\d{4}[\-\/]\d\d[\-\/]\d\d( \w+)?)|\s+$//mg;
			$msg =~ s/\n+/\n/g;
			$msg =~ s/^\n+//;
			$msg =~ s/\s+$//;
			$msg =~ s/ *\n\s*([^\*\-\s])/ $1/g;
			$msg =~ s/^\s*[\*\-]?\s*/ * /mg;
			next if $SEEN{$msg};
			$SEEN{$msg} = 1;
			print "$msg\n";
		}
	}
}
