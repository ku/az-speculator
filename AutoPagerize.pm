package AutoPagerize;

use Encode;

use AutoPagerize::Schema;

use Encode;
use Encode::Guess;

use AutoPagerize::Speculator;

use strict;

sub new {
	my $class = shift;
	$class = ref $class if ref $class;
	my $self = bless {}, $class;
	$self;
}

sub testAll {
	my $self = shift;
	my $opts = shift;
	$self->{schema} = AutoPagerize::Schema::get_connection;

	my $conds = {
		testable => 1,
		skip => 0,
		olduglyhtml => 0
	};
	my $attrs = {
		order_by => 'id DESC'
	};

	if ($opts->{debug}) {
		$conds->{ok} = 0;
		$attrs->{rows} = 1;
	} else {
	}

	my $total = 0;
	my $success = 0;
	
	my $rs = $self->{schema}->resultset('Rules')->search( $conds, $attrs);
	while ( my $rule = $rs->next ) {
		my $html = undef;
		if ( $opts->{disableCache} ) {
			$html = update_html($rule, $rule->exampleurl);
		}

		my $b = $self->_test($rule, $html, $opts);
		
		$b and $success++;
		$total++;

		printf "%d/%d(%.2%%)\n", $success, $total, ($success/$total*100);


		if ( $opts->{set_result} ) {
			my $url = $b;
			$b = $url ? 1 : 0;
			my $d = { ok => $b};
			if ( $b ) {
				$d->{nextpageurl} = ${url};
			}
			$rule->update( $d );

		}

	}
}

sub _test {
	my $self = shift;
	my $rule = shift;
	my $html = shift;
	my $opts = shift;

	my $id = $rule->id;
	my $name =decode('utf-8',$rule->name); 

	my $base_uri = $rule->exampleurl;
	#print STDERR "$id $name\t";
	#print STDERR "\t$base_uri\n";

	if (not $html ) {
		$html = $rule->html;
		$html = decode('utf-8', $html);
	}

	my $spec = AutoPagerize::Speculator->new( $opts );

	my $speculated = $spec->nextLink($html, $base_uri);
	#my $res = AutoPagerize($html, $base_uri);
	#my @sorted_keys = sort {
	#	$res->{$a} < $res->{$b}
	#} keys %$res;

	my $nextPageURL = $rule->nextpageurl;

	if ( not $nextPageURL ) {
my $expression = decode('utf-8', $rule->nextlink);
	print "$id $name\t";
print "nextlink not in db. fetching with xpath $expression\n";
		eval { 
			my $node = $spec->{doc}->find( $expression );
			my $v = $node->shift;
			$nextPageURL = getURLFromNode($v);
			$nextPageURL = URI->new_abs($nextPageURL, $base_uri);
		};
		if ( $@ ) {
			die "nextLink not available. please set it by hand. $@";
		}
	}

	#my $u = shift @sorted_keys;
	#my $estimated = URI->new_abs($u, $base_uri);

	$nextPageURL = AutoPagerize::Speculator::remove_common_url_param($nextPageURL);
	#$estimated =~ s/#.*//;

	my $b = ( $nextPageURL eq $speculated ) ? 1:0;

	if ( $b ) {
		print STDERR "ok\n";
		$b = $nextPageURL;
	} else {
		print STDERR "ng $id $name\n";
		print STDERR "  exampleUrl: $base_uri\n";
		print STDERR "  speculated: $speculated\n";
		print STDERR "  correct   : $nextPageURL\n";
	};
	return $b;
}

sub update_html {
	my $rule = shift;
	my $u = shift;

	my $res = AutoPagerize::Utils::ua->get($u);
	my $html = $res->content;
	
	my $code;
	if ( ($code) = $html =~ m!<meta[^<]+?\bcharset=([\w\-]+)"!i ) {
		$html = decode($code, $html);
	} else {
		my $enc = guess_encoding($html, qw/euc-jp shiftjis 7bit-jis/);
		ref($enc) or die "Can't guess: $enc"; # trap error this way
		$html = $enc->decode($html);
	}

	$rule->update( { html => $html } );
	$html;
}
sub getURLFromNode {
	my $node = shift;
	my $v = undef;

	if ( $node->isa( 'XML::LibXML::Element' ) ) {
		my $name = lc $node->nodeName ;
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

=cooment
sub import_from_wedata {
	my $file ='items.bin';

	my $json = [];
	{
		open F, '<:utf8', 'items.json';
		my $content = join "", <F>;
		my $d = from_json($content);

		push @$json, map {
			my $d = {
				name => $_->{name},
				exampleurl => $_->{exampleUrl},
				nextlink => $_->{nextLink},
				pageelement => $_->{pageElement},
				id => $_->{id}
			};

			$_->{exampleUrl} and $schema->resultset('Rules')->update_or_create($d);
		} map {
			my $id = $_->{resource_url};
			$id =~ s/\D//g;
			$_->{data}->{id} = $id;
			$_->{data}->{name} = $_->{name};
			$_->{data}
		} @$d;
	}
}

sub get_nextLink_from_siteinfo  {
	my $rule = shift;

	print decode('utf-8',$rule->name);
	print "\n";

	my $html = $rule->html;

	if ( not $html ) {
		my $res = $ua->get($u);
		$html = $res->content;
		
		my $code;
		if ( ($code) = $html =~ m!<meta[^<]+?\bcharset=([\w\-]+)"!i ) {
			$html = decode($code, $html);
		} else {
			
		}
		$rule->update( { html => $html } );
	} else {
		$html = decode('utf-8', $html);
	}
	
	my $parser = XML::LibXML->new();
	$parser->recover(1);
	$parser->recover_silently(1);
	$parser->keep_blanks(0);
	$parser->expand_entities(1);
	my $dom = eval {
		$parser->parse_html_string($html);
	};
	if ( $@ ) {
		print $@;
		print $u;
	}

	my $nextLink = decode('utf-8', $rule->nextlink);

	my $nodes = $dom->find($nextLink);
	while ( my $node = $nodes->shift ) {
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
		
		my $uri = URI->new_abs($v, $u);
		
		print "$uri\n";
		$rule->update( { nextpageurl => $uri } );
		last;
	}
}
=cut


1;
	
