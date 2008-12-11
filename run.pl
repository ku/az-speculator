#!/usr/bin/perl

use strict;
binmode STDOUT => ":utf8";
binmode STDERR => ":utf8";
	
use Encode;

use JSON;
use YAML;
use utf8;

use AutoPagerize::Schema;
use AutoPagerize::Speculator;

$ENV{DBIC_TRACE} = 0;

my $DEBUG = 1;
my $SET_RESULT = 1;

my $conds;
my $opts;

if ($DEBUG) {
	$conds =  {
		ok => 0,
	};
	$opts = {
		rows => 1
	};
} else {
	#close STDERR;
	$conds =  {
		
	};
	$opts = {
		#id => \'> 25724'
	};
}
$conds->{testable} = 1;
$conds->{skip} = 0;
$opts->{order_by} = 'id desc';

my $schema = AutoPagerize::Schema::get_connection;
my $rs = $schema->resultset('Rules')->search( $conds, $opts);

sub main () {
	while (my $rule = $rs->next ) {
		my $id = $rule->id;
		my $name =decode('utf-8',$rule->name); 
		my $base_uri = $rule->exampleurl;
		print STDERR "$id $name";
		print STDERR "\t$base_uri\n";

		my $html = $rule->html;
		if ( not $html ) {
			$html = update_html($rule, $base_uri);
		} else {
			$html = decode('utf-8', $html);
		}
		
		my $res = run($html, $base_uri);

		my $show = 0;

		my @sorted_keys = sort {
			$res->{$a} < $res->{$b}
		} keys %$res;
		if ( $show ) {
			map {
				printf "*%f\t%s\n", $res->{$_}, $_;
			} @sorted_keys;
		} else {
			my $nextPageURL = $rule->nextpageurl;
			my $u = shift @sorted_keys;
			my $estimated = URI->new_abs($u, $base_uri);

			$nextPageURL =~ s/#.*//;
			$estimated =~ s/#.*//;

			my $b = ( lc $nextPageURL eq lc $estimated ) ? 1:0;

			if ( $SET_RESULT ) {
				$rule->update({ok => $b});
			}

			
			if ( $b ) {
				if ( $DEBUG ) {
				print "ok $name\n";
				}
			} else {
				print "ng $name\n";
				print "  estimated: $estimated\n";
				print "  correct  : $nextPageURL\n";
			};
		}
		#exit;
	}
}

#main();


#sub update_html {
#	my $rule = shift;
#	my $u = shift;
#
#	my $res = $ua->get($u);
#	my $html = $res->content;
#	
#	my $code;
#	if ( ($code) = $html =~ m!<meta[^<]+?\bcharset=([\w\-]+)"!i ) {
#		$html = decode($code, $html);
#	}
#	$rule->update( { html => $html } );
#	$html;
#}

#25926 foobar2000 Wiki Uploader  http://foobar2000.xrea.jp/up/
# 構造解析が必要。もしくはpage=の最小をとるとかせこい技。

#25860 iタウンページ（基本検索） http://itp.ne.jp/servlet/jp.ne.itp.sear.SGSSVWebDspCtrl?Gyoumu_cate=3&]nit_word=%8B%8F%8E%F0%89%AE&init_addr=%90%CE%90%EC%8C%A7%8B%E0%91%F2%8Es&Media_cate=populer&svc=1201&navi=search&cont_id=a00&proc_id=search
#間違う。

#25791 FOB 画像掲示板    http://red-bbs.com/cgi-bin/bbs/
# R18

#25749 Blip.fm   http://blip.fm/all?p=1
# 原因不明

#25736 PicVi     http://picvi.com/

my $u = shift || 'http://gadgets.boingboing.net/';

print YAML::Dump [
AutoPagerize::Speculator->new(  )->nextLink(URI->new($u))
]

