package AutoPagerize::Speculator::KeywordFilter::En;

use strict;

use base qw(AutoPagerize::Speculator::KeywordFilter);

use YAML;

my $dic = {};
foreach ( qw(
	continue
	reading
	older
	posts
) ) {
	$dic->{$_} = 1;
}

sub new {
	my $class = shift;

	$class = ref $class if ref $class;
	my $self = $class->SUPER::new();
	bless $self, $class;

	$self;
}


sub _score {
	my $self = shift;
}

sub score {
	my $self = shift;
	my $candidates = shift;

	foreach my $candidate (@$candidates) {
		my $node = $candidate->{node};
		my $text = $node->textContent;

		map {
			my $v = $dic->{$_};
			$candidate->{score} *= (($v) ? $v : 0.9);
		} grep {
			not /^\d+$/
		} split /\s+/, $text ;
	}
}

1;
