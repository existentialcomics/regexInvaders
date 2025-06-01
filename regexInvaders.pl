#!/usr/bin/perl
#
use strict; use warnings;
use POSIX;
use Cwd qw( abs_path );
use File::Basename qw( dirname );
use lib dirname(abs_path($0));
#use utf8;

#binmode(STDOUT, ":utf8");
use RegexInvader::Game;

#export LD_PRELOAD=/lib/x86_64-linux-gnu/libncursesw.so.5

my $ship = shift;
my $socket = '/tmp/captainAscii.sock';
my $color = shift;

my @allowedColors = qw(red  green  yellow  blue  magenta  cyan  white);

$SIG{__DIE__} = \&log_die;
$SIG{__WARN__} = \&log_warn;

sub log_die
{
    write_log(@_);
    die @_;
}

sub log_warn
{
    write_log(@_);
}

sub write_log
{
    open LOG,">>",'error-warn.log';
    print LOG @_,"\n";
    close LOG;
}

if ($color){
	if (! grep { $_ eq $color } @allowedColors){
		print "color $color not allowed\n";
		print "allowed colors: " . (join ", ", @allowedColors) . "\n";
		exit;
	}
}

my $client = RegexInvader::Game->new();
