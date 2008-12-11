package AutoPagerize::Speculator::KeywordFilter;

use strict;

sub new {
	my $class = shift;
	$class = ref $class if ref $class;
	my $self = bless {}, $class;
	$self;
}

1;
