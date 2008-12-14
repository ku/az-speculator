package AutoPagerize::Utils;

use strict;

use LWP;
use LWP::UserAgent;

sub new {
	my $class = shift;
$class = ref $class if ref $class;
my $self = bless {}, $class;
$self;
}

our $UASTRING = "Mozilla/5.0 (Windows; U; Windows NT 5.1; ja; rv:1.8.1.12) Gecko/20080201 Firefox/2.0.0.12";
our $ua = LWP::UserAgent->new();
$ua->agent($UASTRING);

sub ua {$ua}

1;

