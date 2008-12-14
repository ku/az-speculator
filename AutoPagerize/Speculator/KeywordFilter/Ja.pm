package AutoPagerize::Speculator::KeywordFilter::Ja;

use strict;
use utf8;

use base qw(AutoPagerize::Speculator::KeywordFilter);

use YAML;

my $dic = {};
foreach ( qw(
→
↓
ページ
件
次
Previous
Entries
読
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
	my $candidate = shift;

	my $node = $candidate->{node};
	my $text = $node->textContent;

	my $factor = 1;

	map {
		if ( /^\p{InHiragana}$/ ) {
		} else {
			my $v = $dic->{$_};
			print "$factor $v $_\n";
			$factor *= (($v) ? $v : 0.9);
		}
	} grep {
		not /^\d+$/
	} split /([あ-ん]+|\b)/, $text ;


	#@_ = $a =~ m/(\p{InHiragana}+)(\p{InCJKUnifiedIdeographs})?/;


	#print "JaFilter: $factor $text\n";
	$factor;
}

1;
