#!/usr/bin/perl

use strict;
binmode STDOUT => ":utf8";
binmode STDERR => ":utf8";
	

use JSON;
use YAML;
use utf8;

use AutoPagerize;
use AutoPagerize::Speculator;

$ENV{DBIC_TRACE} = 0;

my $DEBUG = 1;
my $SET_RESULT = 1;


#25926 foobar2000 Wiki Uploader  http://foobar2000.xrea.jp/up/
# 構造解析が必要。もしくはpage=の最小をとるとかせこい技。

#25860 iタウンページ（基本検索） http://itp.ne.jp/servlet/jp.ne.itp.sear.SGSSVWebDspCtrl?Gyoumu_cate=3&]nit_word=%8B%8F%8E%F0%89%AE&init_addr=%90%CE%90%EC%8C%A7%8B%E0%91%F2%8Es&Media_cate=populer&svc=1201&navi=search&cont_id=a00&proc_id=search
#間違う。

#25791 FOB 画像掲示板    http://red-bbs.com/cgi-bin/bbs/
# R18

#25749 Blip.fm   http://blip.fm/all?p=1
# 原因不明

#25736 PicVi     http://picvi.com/



 my $u = shift;
if ( $u ) {
	 print YAML::Dump [
		 AutoPagerize::Speculator->new(  )->nextLink(URI->new($u))
	];
} else {

	my $az = AutoPagerize->new;
	$az->testAll({
		disableCache => 0,
		debug => 1,
		set_result => 1,
	});
}
