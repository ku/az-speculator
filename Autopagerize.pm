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
