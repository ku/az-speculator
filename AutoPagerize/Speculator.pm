package AutoPagerize::Speculator;

use strict;

use AutoPagerize::Utils;

use YAML;
use XML::LibXML;

use Lingua::LanguageGuesser;
use Digest::MD5  qw(md5 md5_hex md5_base64);

use URI;
use utf8;

use List::Util;

use Encode;
use AutoPagerize::Speculator::KeywordFilter::En;
use AutoPagerize::Speculator::KeywordFilter::Ja;

my $CACHEDIR = "./cache";

my $ua = AutoPagerize::Utils::ua;

#@accesskey="n"]

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

	$self->{scores} = {};

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

	if ( $self->{opts}->{debug} > 1 ) {
		open F, ">:utf8", "t.html";
		print F $html;
	}

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
		if ( $text =~ /[あ-んア-ン]/ ) {
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
#		q{ descendant::text()[contains(., ">>")]} => 4,
#		q{ descendant::text()[contains(., "<<")]} => 2,
		q{ ancestor-or-self::*[contains(@class,"current")]} => 0.9,
		q{ ancestor-or-self::*[contains(@id,"current")]} => 0.9,
		q{ ancestor-or-self::*[contains(@class,"next")]} => 5,
		q{ ancestor-or-self::*[contains(@id,"next")]} => 5,
		q{ ancestor-or-self::*[contains(@class,"old")]} => {score => 5, attr => 'class', word =>['old', 'older']},
		q{ ancestor-or-self::*[contains(@id,"old")]} => {score => 5, attr => 'id', word => ['old', 'older']},
		q{ contains(@href,'page=')} => 4,
		q{ contains(@href,'/page/')} => {score => 4, regex => '/page/\d+'},
		q{ descendant::img[contains(@src,'next')]} => {score => 4, img => 1},
		q{ descendant::img[contains(@src,'old')]} => {score => 2, img => 1},

		q{ descendant::text()[contains(., "comment")]} => 1/10,
		q{ descendant::text()[contains(., "next")]} => 10,
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
		},
		ja => {
			q{ descendant::text()[contains(., "→")]} =>4,
			q{ descendant::text()[contains(., "最")]} => 1/10,
			q{ descendant::text()[contains(., "次")]} => 5,
			#q{ descendant::text()[contains(., "次の")]} => 5,

			#q{ descendant::text()[contains(., "次へ")]} => 5,
			#q{ descendant::text()[contains(., "次のページ")]} => 5,
			q{ descendant::text()[contains(., "old")]} => 5,
		}
	};

	my $rules = {%{$language_depended_rules->{ $self->{lang} }}, %$common_rules};
	$rules;
}

sub _host_similarity {
	my $self = shift;
	my $url = shift;
	my $parts = shift;
	
	my $u = URI->new( $url );
	@_ = reverse split m!\.!, $u->host;

	my $factor = 1;
	my $n = List::Util::max(scalar @_, scalar @$parts);
	for ( my $i = 0; $i < $n; $i++ ) {
		if ( $parts->[$i] ne $_[$i] ) {
			# TODO www consideration.
			$factor *= 0.4;
		}
	}
	if ( $self->{opts}->{debug} > 1 ) {
		printf qq"  host: %s %s\n", 
			join ".", @$parts,
			$url->host
		;
	}

	$factor;
}

sub _path_similarity {
	my $self = shift;
	my $url = shift;
	my $parts = shift;

	@_ = split m!/+!, URI->new( $url )->path;
	shift @_;	# fist one is empty.

	my $factor = 1;
	my $n = List::Util::max(scalar @_, scalar @$parts);
	for ( my $i = 0; $i < $n; $i++ ) {
		if ( $parts->[$i] ne $_[$i] ) {
			if ( $i < @$parts ) {
				$factor *= 0.95;
			}
		}
	}
	if ( $self->{opts}->{debug} > 1 ) {
		printf qq"  path: %s %s\n", 
			join "/", @$parts,
			join "/", @_,
		;
	}
	$factor;
}

sub _url_based_filter {
	my $self = shift;
	my $candidates = shift;


	my @parts = split m!/+!, URI->new( $self->{base_uri} )->path;
	my @domain_parts = reverse split m!\.!, URI->new( $self->{base_uri} )->host;

	shift @parts;

	foreach ( @$candidates ) {
		my $factor = undef;
		my $url = $_->{url};
		
		my $factor = $self->_host_similarity($url, \@domain_parts);
		if ( $factor >= 1 ) {
			# in case that host is not match, path cannot be match.
			# path similarity check make no sence.
			$factor *= $self->_path_similarity($url, \@parts);
		}
		$self->_update_score_with_factor($url, $_->{node}, $factor);
	}
}



sub _keyword_based_filter {
	my $self = shift;
	my $candidates = shift;

	my $lang = $self->{lang};
	$lang =~ s/^./uc $&/e;

	my $klass = __PACKAGE__ . "::KeywordFilter::$lang";
	my $filter = $klass->new;


	foreach ( @$candidates ) {
		my $url = $_->{url};
		my $factor = $filter->score($_);
		$self->_update_score_with_factor($url, $_->{node}, $factor);
	}
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
				paginator
				pages
				navi
				nav
			)],
			penalty => 5,
		}
	};

	foreach my $candidate (@$candidates) {
		my $node = $candidate->{node};
		while ( not $node->isa('XML::LibXML::Document') ) {
# calendar/navigation filter.
			foreach my $filtername ( keys %$filters ) {
				my $definition = $filters->{$filtername};
				my @tests = @{$definition->{keywords}};
				foreach my $attr( qw(class id) ) {
					my $value = $node->getAttribute($attr);
					foreach my $testname ( @tests ) {
						my $regex = quotemeta $testname;
						if ( $value =~ m/$regex/i ) {
							my $factor = $definition->{penalty};

							if ( $self->{opts}->{debug} > 1 ) {
								#print STDERR "$testname got penalty. $filtername $factor\n";
							}
							#$candidate->{'@' . $attr} = 1;
							my $url = $candidate->{url};
							$self->_update_score_with_factor($url, $node, $factor);
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

	my @keys = keys %$rules;

	#print STDERR (scalar @keys) . " rules defined.\n";

if ( $self->{opts}->{debug} > 0 ) {
	print "----- expression based filter\n";
}
	foreach my $expression (@keys) {
		my $rule = $rules->{$expression};
		if ( ref $rule ne 'HASH' ) {
			my $n = $rule;
			$rule = {score => $n};
		}

		push @candidates, map {
			my $c = $_;
			my $rs = $c->{rs};
			my $node = $c->{node};
			my $url = URI->new_abs($c->{url}, $self->{base_uri});

			if ( $url eq $self->{base_uri} ) {
				();
			} else {
				my $score = 0;

				my $valid = 1;
				if ( $rule->{word} ) {
					if ( $self->_false_positive_keyword_filter($rs, $rule) ) {
						print "$c->{url}\n";
						print "$expression\n";
						print "false positive!\n";
						print YAML::Dump $rule;
						$valid = 0;
					}
				}
				if ( $rule->{regex} ) {
					my $regex = quotemeta $rule->{regex};
					$valid = $c->{url} =~ /$regex/;
				}

				if ( $valid ) {
					$score = $self->_update_score_with_factor($url, $node, $rule->{score}, $expression);
				}

				if ( $self->{opts}->{debug} > 2) {
					print "**$expression**";
					print "\n";
					print $score;
					print "\t";
					print $url;
					print "\n";
					print $c->{node}->textContent;
					print "\n";
				}
			
				{
					url => $url,
					node => $node,
					rule => $rule,
				# for debugging.
					expression => $expression,
					text => $node->textContent
				};
			}
		} map {
			my $a = $_;
			my $translated_expression = $expression;
			my $atoz = join "",('a'..'z');
			my $ATOZ = join "",('A'..'Z');
			$translated_expression =~ s/contains\s*\((.+?),/contains(translate($1,'$ATOZ','$atoz'),/;
			my $rs = $a->find($translated_expression);
			if ( $self->{opts}->{debug} > 2) {
				print $a->textContent ."$rs $translated_expression\n";;
			}
			if ( $rs ) {
				my $u = $a->getAttribute('href');
				$u = remove_common_url_param($u);
				$u ? ({ rs => $rs, node => $a, url => $u }) : ();
			} else {
				();
			}
		} @$anchors;
	}

# candidatesにある同じURLのものをフィルタする。
# expression basedでは同じURLをフィルタする必要はない。
# 複数のexpressionにマッチするということはそのぶんnextLinkの特徴を備えている。
# expression basedでdupeのURLがあると後のフィルタで複数回スコアボーナスがついて不当に高くなる。
	my $found = {};
	@candidates = grep {
		my $u = $_->{url};
		my $b = not $found->{$u};
		$found->{$u} = 1;
		$b;
	} @candidates;

if ( $self->{opts}->{debug} > 0 ) {
	print "----- _structure_based_filter\n";
}
	$self->_structure_based_filter(\@candidates);
if ( $self->{opts}->{debug} > 0 ) {
	print "----- _keyword_based_filter\n";
}
	$self->_keyword_based_filter(\@candidates);
if ( $self->{opts}->{debug} > 0 ) {
	print "----- _url_based_filter\n";
}
	$self->_url_based_filter(\@candidates);

	$self->_set_score_to_candidates(\@candidates);

	return \@candidates;
}

sub _update_score_with_factor {
	my $self = shift;
	my $url = shift;
	my $node = shift;
	my $factor = shift;

	if ( not $self->{scores}->{$url} ) {
		$self->{scores}->{$url} = {
			score => 1,
			node => $node,
			sibling => undef
		};
	}
	
	my $found = 0;
	my $anchor_info = $self->{scores}->{$url};
	my $lastOne = $anchor_info;
	while ( $anchor_info ) {
		my $a = $anchor_info->{node};
		if ( $a->isSameNode($node) ) {
			$found = $anchor_info;
			last;
		};
		$lastOne = $anchor_info;
		$anchor_info = $anchor_info->{sibling};
	}
	if ( not $found ) {
		$anchor_info = $lastOne->{sibling} = {
			score => 1,
			node => $node,
			sibling => undef
		};
	}

	my $score = $anchor_info->{score} ;

	if ( $self->{opts}->{debug} ) {
		printf "%.2f * %.2f \t$url @_\n", $score, $factor;
	}

	$anchor_info->{score} = $score * $factor;
}

sub remove_common_url_param {
	my $u = shift;
	$u =~ s/\#.*$//;
	$u =~ s/PHPSESSID=\w+&?//;
	$u =~ s/\?$//;
	$u;
}

sub _highest_score_in_siblings {
	my $self = shift;
	my $url = shift;
	my $highest = 0;

	my $anchor_info = $self->{scores}->{$url};
	
	while ( $anchor_info ) {
		my $score = $anchor_info->{score};
		$highest = List::Util::max($highest, $score);
		$anchor_info = $anchor_info->{sibling};
	}
	$highest;
}

sub _set_score_to_candidates {
	my $self = shift;
	my $candidates = shift;


	foreach ( @$candidates ) {
		my $url = $_->{url};
		delete $_->{rule};
		my $score = $self->_highest_score_in_siblings($url);
		$_->{score} = $score;
	}
}

sub _false_positive_keyword_filter {
	my $self = shift;
	my $rs = shift;
	my $rule = shift;

	# precise check for some words which are subject to be included other words.
	if ( $rs and $rule->{word} ) {
		while ( my $node = $rs->shift ) {
			my $attr = $rule->{attr};
			$attr or next;

			my $value = $node->getAttribute($attr);

			$value =~ s/[^a-z]/_/gi;
			if ( $value =~ /^([A-Z]+|[a-z]+)$/ ) {
				# TODO: implement dictionary based filter.
			} else {
				$value =~ s/([A-Z][a-z]+)/' ' . lc($1)/ge;
			}

			my $words = (ref $rule->{word} eq 'ARRAY') ? $rule->{word} : [$rule->{word}] ;

			my $meta = join "|", map { quotemeta $_ } @$words;

			if ( $value =~ /\b($meta)\b/i ) {
				return 0;
			}
			return 1;
		}
	}
	return 1;
}

sub mostPromising {
	my $self = shift;
	
	my $candidates = $self->find_candidates;

	@_ = sort {
		$a->{score} < $b->{score}
	} @$candidates;

	my $theOne = $_[0];
	if ( $self->{opts}->{debug} ) {
		print "mostPromising:";
		print YAML::Dump $theOne;;
	}
	$theOne;
}
sub nextLink {
	my $self = shift;
	$self->_init(@_);

	$self->detect_language;
	my $candidate = $self->mostPromising;

	$candidate or return undef;

	$candidate->{url};
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

