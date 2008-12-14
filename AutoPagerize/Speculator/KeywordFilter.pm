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
	my $candidate = shift;

	my $text = $candidate->{node}->textContent ;

print "text: $text\n";
	if ( $text =~ /^\s*(\d+)\s*$/ ) {
print "  N: *$1*\n";
		if ( $1 == 1 ) {
			 #the label text of nextLink cant be "1" .
			return 0.5;
		} else {
			return 2;
		}
	}

	return $self->_score($candidate);
}
1;
