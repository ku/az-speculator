package AutoPagerize::Speculator;

use strict;
use YAML;
use XML::LibXML;

use Lingua::LanguageGuesser;
use LWP;
use LWP::UserAgent;
use Digest::MD5  qw(md5 md5_hex md5_base64);

use URI;

use Encode;
use AutoPagerize::Speculator::KeywordFilter::En;

my $CACHEDIR = "./cache";

our $UASTRING = "Mozilla/5.0 (Windows; U; Windows NT 5.1; ja; rv:1.8.1.12) Gecko/20080201 Firefox/2.0.0.12";
our $ua;

my $ua = LWP::UserAgent->new();
$ua->agent($UASTRING);

my $RAQUO = '»';
my $LAQUO = '«';

my $CALENDAR_PENALTY = 5;

sub new {
	my $class = shift;
	$class = ref $class if ref $class;
	my $self = bless {}, $class;

}

sub _init {
	my $self = shift;
	$_ = shift;

	if ( eval{ $_->isa( 'URI' ) } ) {
		$self->{base_uri} = $_;
	} else {
		$self->{base_uri} = shift;
	}

	my $k = md5_hex($self->{base_uri});
	my $filename = "$CACHEDIR/$k.html";
	my $html;
	if ( -e $filename ) {
		open F, "<:utf8", $filename;
		$html = join "", <F>;
	} else {
		my $res = $ua->get($self->{base_uri});
		my $html = $res->content;
		my $charset;
		if ( ($charset) = $html =~ m!<meta[^<]+?\bcharset=([\w\-]+)"!i ) {
			$html = decode($charset, $html);
		}

		$html =~ s!<script.*?>.*?</script.*?>!!gs;
		$html =~ s!<style.*?>.*?</style.*?>!!gs;
		$html =~ s!<frame.*?>.*?</frame.*?>!!gs;
		$html =~ s!<iframe.*?>.*?</iframe.*?>!!gs;

		open F, ">:utf8", $filename;
		print F $html;
	}
	
	$self->_parse($html);

	$self;
}

sub _parse {
	my $self = shift;
	my $html = shift;

	$html = $self->{html} = lc $html;

	my $parser = XML::LibXML->new();
	$parser->recover(1);
	$parser->recover_silently(1);
	$parser->keep_blanks(0);
	$parser->expand_entities(1);
	$self->{doc} = eval {
		$parser->parse_html_string($html);
	};
}

sub detect_language {
	my $self = shift;

	my $shorten = {
		'english'				=> 'en',
		'japanese-utf8'			=> 'ja',
		'chinese_simple-utf8'	=> 'cn',
		'chinese_ZH-utf8'		=> 'cn-ZH'
	};

	@_ = Lingua::LanguageGuesser
		->guess($self->{html})
		->eliminate()
		->suspect( keys %$shorten )
		->result_list();
	my $lang = shift;

	$self->{lang} = $shorten->{$lang};

}

sub _anchors {
	my $self = shift;
	my $nodes = $self->{doc}->find( q{//a[@href and not(starts-with(@href, 'javascript:')) and not(starts-with(@href, 'mail:'))]} );

	my $anchors = [];
	while ( $_ = $nodes->shift ) {
		my $href = $_->getAttribute('href');
		if ( my($protocol) = $href =~ /^([a-z]):/i ) {
			$protocol =~ /https?/ or next;
		}
		push @$anchors, $_;
	}
	$anchors;
}

sub get_rules {
	my $self = shift;

	my $common_rules = {
		qq{descendant::text()[contains(., "$RAQUO")]} => 2,
		qq{descendant::text()[contains(., "$LAQUO")]} => 1,
		q{ descendant::text()[contains(., ">")]} => 2,
		q{ descendant::text()[contains(., "<")]} => 1,
		q{ descendant::text()[contains(., ">>")]} => 5,
		q{ descendant::text()[contains(., "<<")]} => 2,
		q{ ancestor-or-self::*[contains(@class,"next")]} => 5,
		q{ ancestor-or-self::*[contains(@id,"next")]} => 5,
		q{ ancestor-or-self::*[contains(@class,"old")]} => 5,
		q{ ancestor-or-self::*[contains(@id,"old")]} => 5,
		q{ contains(@href,'page=')} => 2,
		q{ descendant::img[contains(@src,'next')]} => {score => 4, img => 1},
		q{ descendant::img[contains(@src,'old')]} => {score => 2, img => 1},
	};

	my $language_depended_rules = {
		en => {
			q{ descendant::text()[contains(., "old")]} => 2,
			q{ descendant::text()[contains(., "new")]} => 2,
			q{ descendant::text()[contains(., "older")]} => 4,
			q{ descendant::text()[contains(., "newer")]} => 4,
			q{ descendant::text()[contains(., "oldest")]} => 1/10,
			q{ descendant::text()[contains(., "newest")]} => 1/10,
			q{ descendant::text()[contains(., "last")]} => 1/10,
			q{ descendant::text()[contains(., "comment")]} => 1/10,
		},
		ja => {
			q{//a[contains(descendant::text(), "→")]} => 4,
			q{//a[contains(descendant::text(), "最")]} => 1/10,
			q{//a[contains(descendant::text(), "次")]} => 2,
			q{//a[contains(descendant::text(), "次の")]} => 5,

			q{//a[contains(descendant::text(), "next")]} => 10,
			q{//a[contains(descendant::text(), "次へ")]} => 5,
			q{//a[contains(descendant::text(), "次のページ")]} => 5,
			q{//a[contains(descendant::text(), "old")]} => 5,
		}
	};

	my $rules = {%{$language_depended_rules->{ $self->{lang} }}, %$common_rules};
	$rules;
}

sub _keyword_based_filter {
	my $self = shift;
	my $candidates = shift;

	my $lang = $self->{lang};
	$lang =~ s/^./uc $&/e;

	my $klass = __PACKAGE__ . "::KeywordFilter::$lang";
	my $filter = $klass->new;

	$filter->score($candidates);

}

sub _structure_based_filter {
	my $self = shift;
	my $candidates = shift;

	my $filters = {
		calendar => {
			keywords => [qw(
				calendar
			)],
			penalty => 1/5,
		},
		navigation => {
			keywords => [qw(
				navigation
				pagination
				navi
				nav
			)],
			penalty => 5,
		}
	};

	foreach my $candidate (@$candidates) {
		my $node = $candidate->{node};
		while ( not $node->isa('XML::LibXML::Document') ) {
# calendar filter.
			foreach my $filtername ( keys %$filters ) {
				my $definition = $filters->{$filtername};
				my @tests = @{$definition->{keywords}};
				foreach my $attr( qw(class id) ) {
					my $value = $node->getAttribute($attr);
					foreach ( @tests ) {
						my $regex = quotemeta $_;
						if ( $value =~ m/$regex/i ) {
							my $factor = $definition->{penalty};
							print "$_ got penalty. $filtername $factor\n";
							$candidate->{score} *= $factor;
						}
						last;
					}
				}
			}
			$node = $node->parentNode;
		}
	}
}

sub find_candidates {
	my $self = shift;

	my $anchors = $self->_anchors;
	my $rules = $self->get_rules;

	my @candidates = ();

	my $scores = {};

	foreach my $expression (keys %$rules) {
		push @candidates, map {
			my $rule = $rules->{$expression};
			my $score = $scores->{"$_"} || 1;

			$score *= ( ref $rule eq 'HASH' ) ?  $rule->{score} : $rule;

			$scores->{"$_"} = $score; 

#			print "**$expression**";
#			print "\n";
#			print $score;
#			print "\t";
#			print $_->textContent;
#			print "\n";

			{
				node => $_,
				score => $score,
				rule => $rule,
			# for debugging.
				expression => $expression,
				text => $_->textContent
			};
		} grep {
			$_->find($expression);
		} @$anchors;
	}

	$self->_structure_based_filter(\@candidates);
	$self->_keyword_based_filter(\@candidates);

	return \@candidates;
}
sub mostPromising {
	my $self = shift;
	
	my $candidates = $self->find_candidates;
	@_ = sort {
		$a->{score} < $b->{score}
	} @$candidates;

	shift;
}
sub nextLink {
	my $self = shift;
	my $url = shift;

	$self->_init($url);

	$self->detect_language;
	my $candidate = $self->mostPromising;
	$candidate or return undef;

	my $relative_path = $candidate->{node}->getAttribute('href');
	my $u = URI->new_abs($relative_path, $self->{base_uri});
	$u =~ s/#.*//;
	$u;
}


sub linkurl {
	my $node = shift;
	my $v;
	if ( $node->isa( 'XML::LibXML::Element' ) ) {
		my $name =  $node->nodeName ;
		if ( $name eq 'a' ) {
			$v = $node->getAttribute('href');
		} elsif ($name eq 'img' )  {
			$v = $node->getAttribute('src');
		} else {
			$v = $node->textContent;
		}
	}
	if ( $node->isa( 'XML::LibXML::Attr' ) ) {
		$v = $node->nodeValue;
	} elsif ( $node->isa( 'XML::LibXML::Text' ) ) {
		$v = $node->nodeValue;
	}
	return $v;
}
1;

