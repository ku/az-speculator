package AutoPagerize::Speculator::KeywordFilter;

use strict;

sub new {
	my $class = shift;
	$class = ref $class if ref $class;
	my $self = bless {}, $class;
	$self;
}

sub score {
	my $self = shift;
	my $candidates = shift;

	foreach my $candidate (@$candidates) {
		$self->_score($candidate);
	}
}
1;
