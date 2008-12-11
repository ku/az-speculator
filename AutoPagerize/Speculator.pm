package AutoPagerize::Speculator;

use strict;

use AutoPagerize::Utils;

use YAML;
use XML::LibXML;

use Lingua::LanguageGuesser;
use Digest::MD5  qw(md5 md5_hex md5_base64);

use URI;
use utf8;

use Encode;
use AutoPagerize::Speculator::KeywordFilter::En;
use AutoPagerize::Speculator::KeywordFilter::Ja;

my $CACHEDIR = "./cache";

my $ua = AutoPagerize::Utils::ua;


my $RAQUO = '»';
my $LAQUO = '«';

my $CALENDAR_PENALTY = 5;

sub new {
	my $class = shift;
	$class = ref $class if ref $class;
	my $self = bless {}, $class;

	$self->{opts} = shift;

	$self;

}

sub _fetch_uri {
	my $u = shift;
	my $k = md5_hex($u);
	my $filename = "$CACHEDIR/$k.html";
	my $html;
	if ( -e $filename ) {
		open F, "<:utf8", $filename;
		$html = join "", <F>;
	} else {
		my $res = $ua->get($u);
		my $html = $res->content;
		my $charset;
		if ( ($charset) = $html =~ m!<meta[^<]+?\bcharset=([\w\-]+)"!i ) {
			$html = decode($charset, $html);
		}

		$html =~ s!<script.*?>.*?</script.*?>!!gs;
		$html =~ s!<noscript.*?>.*?</noscript.*?>!!gs;
		$html =~ s!<style.*?>.*?</style.*?>!!gs;
		$html =~ s!<frame.*?>.*?</frame.*?>!!gs;
		$html =~ s!<iframe.*?>.*?</iframe.*?>!!gs;

		open F, ">:utf8", $filename;
		print F $html;
	}
}

sub _init {
	my $self = shift;
	$_ = shift;

	if ( eval{ $_->isa( 'URI' ) } ) {
		$self->{base_uri} = $_;
		$self->{html} = _fetch_uri($_);
	} else {
		$self->{html} = $_;
		$self->{base_uri} = shift;
	}

	$self->_parse;

	$self;
}

sub _parse {
	my $self = shift;

	my $parser = XML::LibXML->new();
	$parser->recover(1);
	$parser->recover_silently(1);
	$parser->keep_blanks(0);
	$parser->expand_entities(1);

	my $html = $self->{html};
	$self->{doc} = eval {
		#$html = decode('utf-8', $html);
		#$html = encode('utf-8', $html);
		$parser->parse_html_string($html);
	};
	print $@;
}

sub detect_language {
	my $self = shift;

	my $shorten = {
		'english'				=> 'en',
		'japanese-utf8'			=> 'ja',
		'chinese_simple-utf8'	=> 'cn',
		'chinese_ZH-utf8'		=> 'cn-ZH'
	};
	my @langs = keys %$shorten;

	my $text = $self->{html};
	#$text = substr($text, 0, 4096);
	$text =~ s/<[a-z][^>]*?>/ /sg;

	my $lang;

	if ( 0 ) {

		@_ = Lingua::LanguageGuesser
			->guess($text)
			->eliminate()
			->suspect( @langs )
			->result_list();
		$lang = shift;

	} else {
		if ( $text =~ /の/ ) {
			$lang = 'japanese-utf8';
		} elsif ( 1 ) {
			$lang = 'english';
		}
	}

	#warn "lang: $lang\n";

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
		qq{descendant::text()[contains(., "$RAQUO")]} => 4,
		qq{descendant::text()[contains(., "$LAQUO")]} => 2,
		q{ descendant::text()[contains(., ">")]} => 5,
		q{ descendant::text()[contains(., "<")]} => 3,
		q{ descendant::text()[contains(., ">>")]} => 0.5,
		q{ descendant::text()[contains(., "<<")]} => 0.5,
		q{ ancestor-or-self::*[contains(@class,"next")]} => 5,
		q{ ancestor-or-self::*[contains(@id,"next")]} => 5,
		q{ ancestor-or-self::*[contains(@class,"old")]} => {score => 5, attr => 'class', word => 'old'},
		q{ ancestor-or-self::*[contains(@id,"old")]} => {score => 5, attr => 'id', word => 'old'},
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
			q{ descendant::text()[contains(., "→")]} => 4,
			q{ descendant::text()[contains(., "最")]} => 1/10,
			q{ descendant::text()[contains(., "次")]} => 2,
			q{ descendant::text()[contains(., "次の")]} => 5,

			q{ descendant::text()[contains(., "next")]} => 10,
			q{ descendant::text()[contains(., "次へ")]} => 5,
			q{ descendant::text()[contains(., "次のページ")]} => 5,
			q{ descendant::text()[contains(., "old")]} => 5,
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

							if ( $self->{opts}->{debug} > 1 ) {
								print STDERR "$_ got penalty. $filtername $factor\n";
							}
							#$candidate->{'@' . $attr} = 1;
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

	my @keys = keys %$rules;

	#print STDERR (scalar @keys) . " rules defined.\n";

	foreach my $expression (@keys) {
		my $rule = $rules->{$expression};
		if ( ref $rule ne 'HASH' ) {
			my $n = $rule;
			$rule = {score => $n};
		}

		push @candidates, map {
			my $node = $_->{node};
			my $score = $scores->{"$node"} || 1;

			$score *=  $rule->{score};
			$scores->{"$node"} = $score; 

			# print "**$expression**";
			# print "\n";
			# print $score;
			# print "\t";
			# print $_->textContent;
			# print "\n";
			
			{
				node => $node,
				score => $score,
				rule => $rule,
				rs => $_->{rs},
			# for debugging.
				expression => $expression,
				text => $node->textContent
			};
		} map {
			my $rs = $_->find($expression);
			($rs ? ({ rs => $rs, node => $_ }) : ());
		} @$anchors;
	}

	$self->_precise_markup_filter(\@candidates);
	$self->_structure_based_filter(\@candidates);
	$self->_keyword_based_filter(\@candidates);

	return \@candidates;
}

sub _precise_markup_filter {
	my $self = shift;
	my $candidates = shift;
	
	foreach  ( @$candidates ) {
		# precise check for some words which are subject to be included other words.
		if ( $_->{rs} and $_->{rule}->{word} ) {
			while ( my $node = $_->{rs}->shift ) {
				my $attr = $_->{rule}->{attr} or next;
				my $value = $node->getAttribute($attr);

				$value =~ s/[^a-z]/_/gi;
				if ( $value =~ /^([A-Z]+|[a-z]+)$/ ) {
					# TODO: implement dictionary based filter.
				} else {
					$value =~ s/([A-Z][a-z]+)/' ' . lc($1)/ge;
				}

				my $meta = quotemeta $_->{rule}->{word};
				
				#print "$attr = $value /$meta/\n";

				( $value =~ /\b$meta\b/ ) and next;

				$_->{rule}->{score} *= 0.1;
				last;
			}
		}
	}
}

sub mostPromising {
	my $self = shift;
	
	my $candidates = $self->find_candidates;

	if ( $self->{opts}->{debug} ) {
		print YAML::Dump $candidates;
	}

	@_ = sort {
		$a->{score} < $b->{score}
	} @$candidates;

	shift;
}
sub nextLink {
	my $self = shift;
	$self->_init(@_);

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

