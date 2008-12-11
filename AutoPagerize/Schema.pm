package AutoPagerize::Schema;

#use DBIx::Class::Schema::Loader;

use strict;
use base qw/DBIx::Class::Schema::Loader/;

$ENV{DBIC_TRACE} = 0;

__PACKAGE__->loader_options(
		debug => 0,
		#moniker_map => sub { return $_[0] },
		#constraint => qr/^(images|pages|feeds)$/ 
	);

1;

my $dbdriver = 'mysql';
my $dbname = 'autopagerize';
#	my $dbhost = '127.0.0.1:13306';
my $dbhost = 'localhost';
my $dbuser = 'root';
my $dbpasswd = 'passwd';

sub connect {
	my $self = shift;
	my $dsn = join ":", 'DBI', $dbdriver, $dbname, $dbhost;
	$self->SUPER::connect(
		$dsn, 
		$dbuser,
		$dbpasswd,
	);
}

sub get_connection {
	my $self = shift;
	my $dsn = join ":", 'DBI', $dbdriver, $dbname, $dbhost;

	__PACKAGE__->connect($dsn, $dbuser, $dbpasswd) or die $!;
}

