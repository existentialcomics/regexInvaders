use strict;
use warnings;
use utf8;
package RegexInvader::Game;

BEGIN {
    use POSIX qw(floor ceil);
    my $loc = POSIX::setlocale(&POSIX::LC_ALL, "");
    $Curses::OldCurses = 1;
    $Curses::UI::utf8 = 1;
}

use Term::ANSIColor 4.00 qw(RESET color :constants256 colorstrip);
require Term::Screen;
use Time::HiRes qw( usleep ualarm gettimeofday tv_interval nanosleep time);
use Data::Dumper;
use JSON::XS qw(encode_json decode_json);
use IO::Socket::UNIX;
use Math::Trig ':radial';
use Text::Wrap;
use POSIX qw(floor ceil);
my $loc = POSIX::setlocale(&POSIX::LC_ALL, "");

use Curses;

use constant {
	ASPECTRATIO => 0.66666666,
	PI => 3.1415
};

my %colors = ();
my %cursesColors = ();
my $starMapSize = 0;
my @starMap;
my @starMapStr;
my @lighting;
my $lastFrame = time();
my %lights = ();
my $lightsKey = 1;

my $useCurses = 1;
my $cursesColorCount = 1;

my %colorCodes = (
    BOLD    => 1,
    BLACK   => 0,
    RED     => 1,
    GREEN   => 2,
    YELLOW  => 3,
    BLUE    => 4,
    MAGENTA => 5,
    CYAN    => 6,
    WHITE   => 7,
    ON_BLACK   => 0,
    #ON_BLACK   => 16,
    ON_RED     => 1,
    ON_GREEN   => 2,
    ON_YELLOW  => 3,
    ON_BLUE    => 4,
    ON_MAGENTA => 5,
    ON_CYAN    => 6,
    ON_WHITE   => 7,
    DARKGREY     => 8,
    LIGHTRED     => 9,
    LIGHTGREEN   => 10,
    LIGHTYELLOW  => 11,
    LIGHTBLUE    => 12,
    LIGHTMAGENTA => 13,
    LIGHTCYAN    => 14,
    LIGHTWHITE   => 15,
    ON_DARKGREY     => 8,
    ON_LIGHTRED     => 9,
    ON_LIGHTGREEN   => 10,
    ON_LIGHTYELLOW  => 11,
    ON_LIGHTBLUE    => 12,
    ON_LIGHTMAGENTA => 13,
    ON_LIGHTCYAN    => 14,
    ON_LIGHTWHITE   => 15,
);

# The first 16 256-color codes are duplicates of the 16 ANSI colors,
# included for completeness.
foreach (0 .. 15){
    $colorCodes{"ANSI$_"} = $_;
    $colorCodes{"ON_ANSI$_"} = $_;
}

# 256-color RGB colors.  Red, green, and blue can each be values 0 through 5,
# and the resulting 216 colors start with color 16.
for my $r (0 .. 5) {
    for my $g (0 .. 5) {
        for my $b (0 .. 5) {
            my $code = 16 + (6 * 6 * $r) + (6 * $g) + $b;
            $colorCodes{"RGB$r$g$b"}    = $code;
            $colorCodes{"ON_RGB$r$g$b"} = $code;
        }
    }
}

# The last 256-color codes are 24 shades of grey.
for my $n (0 .. 23) {
    my $code = $n + 232;
    $colorCodes{"GREY$n"}    = $code;
    $colorCodes{"ON_GREY$n"} = $code;
}

sub new {
	my $class = shift;

	my $self = {};
	bless( $self, $class );

	if ($self->_init(@_)){
		return $self;
	} else {
		return undef;
	}
}

sub _init {
	my $self = shift;
	my $ship_file = shift;
	my $socket = shift;
	my $color = shift;

	$self->{'regex'} = '';
	$self->{msgs} = ();
	$self->{chatWidth} = 60;
	$self->{chatOffset} = 0;

    $self->{destroyedWords} = {};
    $self->{destroyedShields} = {};

    $self->{levels} = [
        {}, ### so we start at one
        {
            'name' => 'The First Level',
            'solution' => '/[a-z]/',
            'words' => ['moose', 'cow', 'octopus', 'dog', 'beaver', 'rat', 'cat', 'ant', 'zebra', 'donkey'],
            'shields' => ['DO', 'NOT', 'MATCH', 'THESE', 'WORDS'],
        },
        {
            'name' => 'aaaAAAAAAAA!',
            'solution' => '/(^|[^a])a{3}([^a]|$)/',
            'words' => ['Saaadin', 'mamaaados', 'humaaan', 'aaabbbccc', 'AAAaaaAAA', 'abaabbaaabbb', 'baaad', '|   aaa   |', 'zaaap', 'taaaco'],
            'shields' => ['We must know aaaaaaaaah!', 'AAAAaaaaAAAA', 'I waant to live', 'Hahahahahaha', 'AAaaAAaaAAaaAA'],
        },
        {
            'name' => 'abba',
            'solution' => '/(.)(.)\2\1/',
            'words' => ['baccab', 'orgaagro', 'dddd', 'monnom', 'zzzzzzzzzzz', 'MmMMmM', '__--__', 'jjjjjjjj', 'AAAA', '123321'],
            'shields' => ['Eliminate', 'the', 'alien', 'race', 'forever'],
        },
        {
            'name' => 'domain knowledge',
            'solution' => '/[a-z][a-z0-9\-]*[a-z]?\.)+[a-z]$/',
            'words' => ['kung-fu-chess.org', 'kungfuchess.org', 'regex.pl', 'example-123.com', 'football.co.uk', 'kiwi.kiwi.kiwi', 'philosophy.sexy', 'existentialcomics.com', 'a.b.c.d.e.f.co.uk'],
            'shields' => ['example', '-kungfuchess-.org', 'localhost', 'kungfuchess..org', 'top-level-domain'],
        },
        {
            'name' => 'string matching is easy',
            'solution' => '/^[\'"]([^"\']|(\\[\'"])+\1$',
            'words' => ['\'surely this is a string\'', '"double the fun"', "'don\\'t forget apostrophies'", '"don\'t forget this"', '"\'"', '"it was hard \\"writing\\" these"'],
            'shields' => ['don"t try to be perfect"', "'what'is'this'", 'close"', '"too"many"', '"open'],
        },
        {
            'name' => 'Logic is key',
            'solution' => '/^(and|or)+$/',
            'words' => ['andorandandandor', 'orororor', 'andand', 'oror', 'andorandor', 'andororand', 'andor', 'orand', 'or'],
            'shields' => ['orandr', 'orandorando', 'rando', 'norandorand', 'orandandroand'],
        },
        {
            'name' => 'Leaders and followers',
            'solution' => '/follower(?!->leader)|leader/',
            'words' => ['leader->follower', 'leader', 'follower', 'leader->leader', 'follower->follower', 'leader->leader->follower', 'follower->follower->follower', 'leader->leader->leader', 'leader->leader->follower->follower'],
            'shields' => ['leader->follower->leader', 'leader->leader->follower->leader', 'follower->leader', 'follower->follower->leader', 'follower->leader->leader'],
        },
        {
            'name' => 'Tic Tac Toe',
            'solution' => '/^(tic(tac)?(toe?))+/',
            'words' => ['tictactoe', 'tictoe', 'tiktak', 'tiktaktoetoe', 'tiktiktik', 'tiktaktiktak', 'tik', 'tak', 'toe'],
            'shields' => ['toetiktak', 'taktik', 'toetik', 'taktoe', 'tiktaktoetoetaktic'],
        },
        {
            'name' => 'Always look at what is in front of you',
            'solution' => '/Running\s(?!Pothole)/',
            'words' => ['Potholes Walking Running', 'Running Walking', 'Running Walking', 'Walking Potholes Running', 'Walking Walking Potholes', 'Potholes Potholes', 'Running Running Walking', 'Walking Potholes Running Walking', 'Running Running Running'],
            'shields' => ['Walking Running Potholes Walking', 'Running Potholes Running', 'Running Running Potholes', 'Running Potholes Walking', 'Running Potholes'],
        },
        {
            'name' => 'Watch your back',
            'solution' => '/(?<!Thief)\\s\\w+/',
            'words' => ['Wizard Warrior', 'Priest Warrior', 'Wizard Thief', 'Priest Thief', 'Ranger Paladin', 'Paladin Thief', 'Warrior Paladin', 'Wizard Sorceror', 'Wizard Priest'],
            'shields' => ['Thief Warrior', 'Thief Priest', 'Thief Ranger', 'Thief Paladin', 'Thief Sorceror'],
        },
        {
            'name' => 'regex in your regex',
            'solution' => '/^([\/#]).+\\(\w*)(?<!\\)\\).*(\1/$',
            'words' => ['/(in)valid/', '/(global)/g', '/(http:\\/\\/.*)/', '/(?<!foo)bar/', '#(http://.*)#', '/(this|that)/', '/([Rr]e[Ge]ex)/', '/^(start)/', '/(end)$/'],
            'shields' => ['/)backwards(/', '/(escape\\)/', '/beginAndEnd#', '/(closed/', '/open)/'],
        },
    ];

	$self->{zoom} = 1;
	$self->resizeScr();

    ### curses init
    initscr();
    curs_set(0);
	start_color();
    attrset(COLOR_PAIR(16));
	noecho();

    #my $res = $self->{_curses_info}      = newwin($self->{height}, 0, 10, 40);
	# *newwin(int nlines, int ncols, int begin_y, int begin_x);
    $self->{_curses_info} = newwin($self->{termHeight} - $self->{height}, $self->{termWidth}, $self->{height}, 0);
    $self->{_curses_side} = newwin($self->{height}, $self->{termWidth} - $self->{width} , 0, $self->{width});

    setCursesWinColor($self->{_curses_info}, 'WHITE', 'ON_BLACK');
    setCursesWinColor($self->{_curses_side}, 'WHITE', 'ON_BLACK');

	$self->_generateStarMap();

	$self->{lastFrame} = time();
	$self->{lastInfoPrint} = time();

	$self->{username} = getpwuid($<);

	$self->{debug} = "";
	$self->{maxFps} = 40;
	$self->{maxBackgroundFps} = 6;
	$self->{maxInfoFps} = 6;
	$self->{fps} = 40;
	$self->{mode} = 'waitingToBegin';

	$self->{cursorx} = 0;
	$self->{cursory} = 0;

	$self->loop();

	return 1;
}

sub _generateStarMap {
	my $self = shift;
	my $size = shift;
	if (!defined($size)){ $size = 300; }

	print "loading maps...\n";

	$starMapSize = $size;
    #$self->{_curses_map}      = newpad($self->{height}, $self->{width});
    $self->{_curses_map} = newpad($size * 2, $size * 2);
    setCursesWinColor($self->{_curses_map}, 'WHITE', 'ON_BLACK');
    $self->{_curses_mapBlank} = newpad($size * 2, $size * 2);
    setCursesWinColor($self->{_curses_mapBlank}, 'WHITE', 'ON_BLACK');
    $self->{_curses_mapBlankNS} = newpad($size * 2, $size * 2);
    setCursesWinColor($self->{_curses_mapBlankNS}, 'WHITE', 'ON_BLACK');
    $self->{_curses_mapBlankNS2} = newpad($size * 2, $size * 2);
    setCursesWinColor($self->{_curses_mapBlankNS2}, 'WHITE', 'ON_BLACK');
    $self->{_curses_mapBlankNS3} = newpad($size * 2, $size * 2);
    setCursesWinColor($self->{_curses_mapBlankNS3}, 'WHITE', 'ON_BLACK');
    $self->{_curses_mapBlankNS4} = newpad($size * 2, $size * 2);
    setCursesWinColor($self->{_curses_mapBlankNS4}, 'WHITE', 'ON_BLACK');
    $self->{_curses_mapBlankEW} = newpad($size * 2, $size * 2);
    setCursesWinColor($self->{_curses_mapBlankEW}, 'WHITE', 'ON_BLACK');
    $self->{_curses_mapBlankEW2} = newpad($size * 2, $size * 2);
    setCursesWinColor($self->{_curses_mapBlankEW2}, 'WHITE', 'ON_BLACK');
    $self->{_curses_mapBlankEW3} = newpad($size * 2, $size * 2);
    setCursesWinColor($self->{_curses_mapBlankEW3}, 'WHITE', 'ON_BLACK');
    $self->{_curses_mapBlankEW4} = newpad($size * 2, $size * 2);
    setCursesWinColor($self->{_curses_mapBlankEW4}, 'WHITE', 'ON_BLACK');
    $self->{_curses_mapBlankNeSw} = newpad($size * 2, $size * 2);
    setCursesWinColor($self->{_curses_mapBlankNeSw}, 'WHITE', 'ON_BLACK');
    $self->{_curses_mapBlankNeSw2} = newpad($size * 2, $size * 2);
    setCursesWinColor($self->{_curses_mapBlankNeSw2}, 'WHITE', 'ON_BLACK');
    $self->{_curses_mapBlankNeSw3} = newpad($size * 2, $size * 2);
    setCursesWinColor($self->{_curses_mapBlankNeSw3}, 'WHITE', 'ON_BLACK');
    $self->{_curses_mapBlankNeSw4} = newpad($size * 2, $size * 2);
    setCursesWinColor($self->{_curses_mapBlankNeSw4}, 'WHITE', 'ON_BLACK');
    $self->{_curses_mapBlankNwSe} = newpad($size * 2, $size * 2);
    setCursesWinColor($self->{_curses_mapBlankNwSe}, 'WHITE', 'ON_BLACK');
    $self->{_curses_mapBlankNwSe2} = newpad($size * 2, $size * 2);
    setCursesWinColor($self->{_curses_mapBlankNwSe2}, 'WHITE', 'ON_BLACK');
    $self->{_curses_mapBlankNwSe3} = newpad($size * 2, $size * 2);
    setCursesWinColor($self->{_curses_mapBlankNwSe3}, 'WHITE', 'ON_BLACK');
    $self->{_curses_mapBlankNwSe4} = newpad($size * 2, $size * 2);
    setCursesWinColor($self->{_curses_mapBlankNwSe4}, 'WHITE', 'ON_BLACK');
	foreach my $x (0 .. $size){
		push @starMap, [ (' ') x $size ];
		push @starMapStr, '';
		foreach my $y (0 .. $size){
			my $rand = rand();
			if ($rand > 0.03){
				$starMapStr[$x] .= ' ';
				#putCursesChr($self->{_curses_mapBlank}, $x, $y, ' ', 'WHITE', 'ON_BLACK');
                next;
			}
			my $starRand = rand();
			my $chr = '.';
			my $col = "";
            my $fore = 'GREY4';
            my $back = 'ON_BLACK';
			if ($starRand < 0.02){
				$chr = '*';
				if ($starRand < 0.002){
                    $fore = 'YELLOW';
				} elsif ($starRand < 0.012){
				    $fore = "GREY" . int(rand(22));
                }
			} elsif ($starRand < 0.5){
				$fore = "GREY" . int(rand(22));
			} elsif ($starRand < 0.10){
                $fore = 'YELLOW';
			} elsif ($starRand < 0.30){
                $fore = 'GREY2';
			}
            $col = getColor($fore, $back);
			$starMap[$x]->[$y] = $col . $chr;
			$starMapStr[$x] .= $chr;
			putCursesChr($self->{_curses_mapBlank}, $x, $y, $chr, $fore, 'ON_BLACK');
			putCursesChr($self->{_curses_mapBlank}, $x + $size, $y + $size, $chr, $fore, 'ON_BLACK');
			putCursesChr($self->{_curses_mapBlank}, $x, $y + $size, $chr, $fore, 'ON_BLACK');
			putCursesChr($self->{_curses_mapBlank}, $x + $size, $y, $chr, $fore, 'ON_BLACK');

			putCursesChr($self->{_curses_mapBlankNS}, $x, $y, '│', $fore, 'ON_BLACK');
			putCursesChr($self->{_curses_mapBlankNS}, $x + $size, $y + $size, '│', $fore, 'ON_BLACK');
			putCursesChr($self->{_curses_mapBlankNS}, $x, $y + $size, '│', $fore, 'ON_BLACK');
			putCursesChr($self->{_curses_mapBlankNS}, $x + $size, $y, '│', $fore, 'ON_BLACK');

			putCursesChr($self->{_curses_mapBlankEW}, $x, $y, '─', $fore, 'ON_BLACK');
			putCursesChr($self->{_curses_mapBlankEW}, $x + $size, $y + $size, '─', $fore, 'ON_BLACK');
			putCursesChr($self->{_curses_mapBlankEW}, $x, $y + $size, '─', $fore, 'ON_BLACK');
			putCursesChr($self->{_curses_mapBlankEW}, $x + $size, $y, '─', $fore, 'ON_BLACK');

            for my $i (-1 .. 1){
                putCursesChr($self->{_curses_mapBlankNS2}, $x + $i, $y, '│', $fore, 'ON_BLACK');
                putCursesChr($self->{_curses_mapBlankNS2}, $x + $i + $size, $y + $size, '│', $fore, 'ON_BLACK');
                putCursesChr($self->{_curses_mapBlankNS2}, $x + $i, $y + $size, '│', $fore, 'ON_BLACK');
                putCursesChr($self->{_curses_mapBlankNS2}, $x + $i + $size, $y, '│', $fore, 'ON_BLACK');
           
                putCursesChr($self->{_curses_mapBlankEW2}, $x, $y + $i, '─', $fore, 'ON_BLACK');
                putCursesChr($self->{_curses_mapBlankEW2}, $x + $size, $y + $i + $size, '─', $fore, 'ON_BLACK');
                putCursesChr($self->{_curses_mapBlankEW2}, $x, $y + $i + $size, '─', $fore, 'ON_BLACK');
                putCursesChr($self->{_curses_mapBlankEW2}, $x + $size, $y + $i, '─', $fore, 'ON_BLACK');
            }
            for my $i (-3 .. 3){
                putCursesChr($self->{_curses_mapBlankNS3}, $x + $i, $y, '│', $fore, 'ON_BLACK');
                putCursesChr($self->{_curses_mapBlankNS3}, $x + $i + $size, $y + $size, '│', $fore, 'ON_BLACK');
                putCursesChr($self->{_curses_mapBlankNS3}, $x + $i, $y + $size, '│', $fore, 'ON_BLACK');
                putCursesChr($self->{_curses_mapBlankNS3}, $x + $i + $size, $y, '│', $fore, 'ON_BLACK');
           
                putCursesChr($self->{_curses_mapBlankEW3}, $x, $y + $i, '─', $fore, 'ON_BLACK');
                putCursesChr($self->{_curses_mapBlankEW3}, $x + $size, $y + $i + $size, '─', $fore, 'ON_BLACK');
                putCursesChr($self->{_curses_mapBlankEW3}, $x, $y + $i + $size, '─', $fore, 'ON_BLACK');
                putCursesChr($self->{_curses_mapBlankEW3}, $x + $size, $y + $i, '─', $fore, 'ON_BLACK');
            }
            for my $i (-4 .. 4){
                putCursesChr($self->{_curses_mapBlankNS3}, $x + $i, $y, '│', $fore, 'ON_BLACK');
                putCursesChr($self->{_curses_mapBlankNS3}, $x + $i + $size, $y + $size, '│', $fore, 'ON_BLACK');
                putCursesChr($self->{_curses_mapBlankNS3}, $x + $i, $y + $size, '│', $fore, 'ON_BLACK');
                putCursesChr($self->{_curses_mapBlankNS3}, $x + $i + $size, $y, '│', $fore, 'ON_BLACK');
           
                putCursesChr($self->{_curses_mapBlankEW3}, $x, $y + $i, '─', $fore, 'ON_BLACK');
                putCursesChr($self->{_curses_mapBlankEW3}, $x + $size, $y + $i + $size, '─', $fore, 'ON_BLACK');
                putCursesChr($self->{_curses_mapBlankEW3}, $x, $y + $i + $size, '─', $fore, 'ON_BLACK');
                putCursesChr($self->{_curses_mapBlankEW3}, $x + $size, $y + $i, '─', $fore, 'ON_BLACK');
            }
		}
	}
}

sub sprite {
	my $array = shift;
	if (ref($array) ne 'ARRAY'){ return $array; }
	my $length = time() - $lastFrame;
	if ($length > 1){ $length = 1 }
	if ($length < 0){ $length = 0 }
	my $chr = $array->[$length * @{$array}];
	if (!$chr){ $chr = $array->[0] }
	return $chr;
}

sub loop {
	my $self = shift;

	my $lastTime  = time();
	my $frames = 0;
	#my $startTime = time();
	my $time = time();
	my $fps = $self->{maxFps};

	my $scr = new Term::Screen;
	$scr->clrscr();
	$scr->noecho();
    #
	$self->{scr} = $scr;
	my $lastPing = time();

	$self->setHandlers();
	$self->printBorder();

    $self->_resetLighting($self->{width} * $self->{zoom}, $self->{height} * $self->{zoom});

	my $playing = 1;
	while ($playing){
		if ((time() - $time) < (1 / $fps)){
			my $sleep = 1_000_000 * ((1 / $fps) - (time() - $time));
			if ($sleep > 0){
				usleep($sleep);
			}
			next;
		}
		$lastTime = $time;
		$time = time();
        my $timeElapsed = $time - $self->{gameStart};
		$frames++;
		if ($time - $lastFrame > 1){
			$lastFrame = $time;
			$self->{fps} = $frames;
			$frames = 0;
			$self->{lastFrame} = $time;
		}
		$self->{'map'} = $self->_resetMap($self->{width} * $self->{zoom}, $self->{height} * $self->{zoom});

		$self->_resetLighting($self->{width} * $self->{zoom}, $self->{height} * $self->{zoom});

        if ($self->{mode} eq 'waitingToBegin') {
            my $msg = '/press enter to begin/';
            $self->putMapStr(
                $self->{height} / 2,
                $self->{width} / 2 - (length($msg)/2),
                $msg,
                'WHITE',
                'BLACK',
            );
        }
        if ($self->{mode} eq 'wonRound') {
            my $msg = '/press enter to begin/';
            $self->putMapStr(
                $self->{height} / 2,
                $self->{width} / 2 - (length($msg)/2),
                $msg,
                'WHITE',
                'BLACK',
            );
            $msg = '/level completed/';
            $self->putMapStr(
                ($self->{height} / 2) - 1,
                $self->{width} / 2 - (length($msg)/2),
                $msg,
                'WHITE',
                'BLACK',
            );
        }
        if ($self->{mode} eq 'gameOver') {
            my $msg = '/game over. [Yy]ou suck at regex/';
            $self->putMapStr(
                $self->{height} / 2,
                $self->{width} / 2 - (length($msg)/2),
                $msg,
                'WHITE',
                'BLACK',
            );
        }
        $self->putMapStr(
            1,
            1,
            " " x 75,
            'WHITE',
            'BLACK',
        );
        $self->putMapStr(
            1,
            1,
            "level $self->{level}: " . (int  $timeElapsed),
            'WHITE',
            'BLACK',
        );

        if ($self->{mode} eq 'playing') {
            my $words = $self->{levels}->[$self->{level}]->{words};
            $self->{words} = $words;
            # words you want to match
            $self->_drawWords($words, $timeElapsed);
            my $shields = $self->{levels}->[$self->{level}]->{shields};
            $self->{shields} = $shields;
            # i.e. the words you don't want to match
            $self->_drawDefenses($shields);
        }

        if ($timeElapsed > 60 && $self->{mode} eq 'playing') {
            $self->{mode} = 'gameOver';
        }

        $self->_getKeystrokes($self->{scr});
        $self->printInfo();
        $self->printScreen($scr);
		$self->printSide();
	    $self->_resetLighting($self->{width} * $self->{zoom}, $self->{height} * $self->{zoom});
	}
}

sub printCursesScreen {
    my $self = shift;
    $self->{_curses_map}->prefresh(0, 0, 0, 0, $self->{height}, $self->{width});
    $self->{_curses_info}->refresh();
    $self->{_curses_side}->refresh();
    setCursesWinColor($self->{_curses_info}, 'WHITE', 'ON_BLACK');
    setCursesWinColor($self->{_curses_side}, 'WHITE', 'ON_BLACK');

    # copywin(*srcwin, *dstwin, sminrow, smincol, dminrow, dmincol, dmaxrow, dmaxcol, overlay)
	my $copyWin = $self->{_curses_mapBlank};
    my $warp = $self->{warp};
	if ($warp){
		if ($warp->{end} - time() < 0.2){
			$copyWin = $self->{_curses_mapBlankNS4};
        } elsif ($warp->{end} - time() < 0.35){
			$copyWin = $self->{_curses_mapBlankNS3};
        } elsif ($warp->{end} - time() < 0.55){
			$copyWin = $self->{_curses_mapBlankNS2};
		} else {
			$copyWin = $self->{_curses_mapBlankNS};
		}
	}
    if ($warp->{end} < time()) {
        delete $self->{warp};
    }
    my $r = copywin(
        $copyWin,
        $self->{_curses_map},
        #0, # starmap location, % time to move
        #time() % 20,
        0,
        (time() * 2) % $starMapSize,
        1,
        1,
        $self->{height} - 2,
        $self->{width} - 2,
        0
    );
}

sub printScreen {
	my $self = shift;
	if ($useCurses) { return $self->printCursesScreen(); }
	my $scr = shift;
	my $map = $self->{map};

	### draw the screen to Term::Screen
	foreach my $i (0 .. $self->{height}){
		my $iZ = (int($i * $self->{zoom}));
		my $row = '';
		foreach (0 .. $self->{width}){
			my $jZ = (int($_ * $self->{zoom}));
			my $lighting = $lighting[$iZ]->[$jZ];
			my $color = getColor('', 'ON_GREY' . ($lighting <= 23 ? $lighting : 23 ));
            $row .= (defined($map->[$iZ]->[$jZ]) ? $color . $map->[$iZ]->[$jZ] : $color . $self->getStar($i, $_));
		}
        $self->putStr(
            $i + 1, 1,
            $row
        );
	}
}

sub getStar {
    #my $self = shift;
    #my ($x, $y) = @_;
	# Do not assign variables for performance
	return substr($starMapStr[
		int($_[1] + $_[0]->{ship}->{y}) % $starMapSize],
		int($_[2] + $_[0]->{ship}->{x}) % $starMapSize,
		1); 
}

sub putTermChr {
    my $self = shift;
    my ($window, $col, $row, $str, $color, $backColor) = @_;

    my $colorBack = undef;
    if (!defined($color)){ $color = 'WHITE'; }
    if (!defined($colorBack)){ $colorBack = 'ON_BLACK'; }
    $col += $self->{height};
    $self->{scr}->at($col, $row);
    $self->{scr}->puts(getColor($color, $colorBack) . $str);
}

sub putStr {
    if ($useCurses){
        my $self = shift;
        if ($self->{zoom} == 1){
            return putCursesChr($self->{_curses_map}, @_);
        } else {
            return putCursesChr($self->{_curses_map}, $_[0] / $self->{zoom}, $_[1] / $self->{zoom}, $_[2], $_[3], $_[4]);
        }
    } else {
        return putTermChr(@_);
    }
}

sub putInfoStr {
    my $self = shift;
    if ($useCurses){
        return putCursesChr($self->{_curses_info}, @_);
    } else {
        return putTermChr(@_);
    }
}

sub putSideStr {
    my $self = shift;
    if ($useCurses){
        return putCursesChr($self->{_curses_side}, @_);
    } else {
        return putTermChr(@_);
    }
}

sub putCursesChr {
    my ($window, $col, $row, $str, $color, $backColor) = @_;
    if (defined($color) && defined($backColor)){
        setCursesColor($window, $color, $backColor);
    }
	$str = sprite($str);
    $window->addstr($col, $row, $str);
    $window->attrset(A_NORMAL);
}

sub putMapStr {
	if ( ! onMap($_[0], $_[1], $_[2]) ){ return 0; }
    putStr(@_);
}

sub printSide {
	my $self = shift;
	my $options = shift;

	my $ship = $self->{ship};
	#my $height = (defined($options->{height}) ? $options->{height} : $self->{height} + 1);
	my $height = $self->{height} + 1;

    for my $line (1 .. $height){
        $self->putSideStr(
            $line, 3,
            ' ' x ($self->{chatWidth} - 4)
        );
    }
    my $lastMsg = $#{ $self->{msgs} } + 1 + $self->{chatOffset};
    my $term = $lastMsg - $height - 4;
    my $count = 2;
    if ($term < 0){ $term = 0; }
    while ($lastMsg > $term){
        $count++;
        $lastMsg--;
        my $msgLine = $self->{msgs}->[$lastMsg];
        if ($msgLine){
            $self->putSideStr(
                $height - $count - 1,
                4,
                sprintf('%-' . $self->{chatWidth} . 's', $msgLine->{'regex'}),
                $msgLine->{color} // 'GREEN',
                'ON_BLACK'
            );
        }
    }
    my $boxColor = 'ON_BLACK';
    if ($self->{mode} eq 'type'){ $boxColor = 'ON_GREY4'; }
    $self->putSideStr(
        $height - 3,
        0,
        sprintf('%-' . $self->{chatWidth} . 's', "> " . substr($self->{'regex'}, -($self->{chatWidth} -3))),
        "WHITE",
        $boxColor
    );
}

sub printInfo {
	my $self = shift;
	my $options = shift;

	if ((time() - $self->{lastInfoPrint}) < (1 / $self->{maxInfoFps})){
		return;
	}
    $self->printBorder();

	#my $height = (defined($options->{height}) ? $options->{height} : $self->{height} + 1);
	my $height = $self->{height} + 1;
	my $width = $self->{width};
	my $left = 2;

    my $keyLen = 30;
	$self->putInfoStr(
        0, 52,
        '┌──' . '─' x ($keyLen-2) . '──┐'
    );
    my $i = 0;
    $i++;
    $self->putInfoStr(
        0 + $i, 52,
        sprintf('│ %-' . $keyLen . 's │', "/$self->{regex}/g")
    );
	$self->putInfoStr(
        1 + $i, 52,
        '└──' . '─' x ($keyLen-2) . '──┘'
    );

	$self->printStatusBar(
		'power',
        $self->{power},
		$self->{powerMax},
		50,
		0,
		0,
		'5',
		'x',
		0
	);

    ### debug info
    #$self->putInfoStr(0, 100, "debug: $self->{debug}  ", 'GREEN', "ON_BLACK");
    #$self->putInfoStr(10, 100, "debug: $self->{ship}->{debug}  ", 'GREEN', "ON_BLACK");
    return 0; 
}

sub _resetMap {
	my $self = shift;
	my ($width, $height) = @_;
	my @map = ();

	if ($useCurses){
		return [];
	}

	foreach my $x (0 .. $height){
		push @map, [(undef) x $width];
	}

	return \@map;
}

sub _resetLighting {
	my $self = shift;
	my ($width, $height) = @_;
	@lighting = ();
	foreach my $x (0 .. $height + 1){
		push @lighting, [(0) x ($width + 1)];
	}
}

sub setHandlers {
	my $self = shift;
	$SIG{WINCH} = sub { $self->resizeScr() };
}

sub resizeScr {
	my $self = shift;
    use Term::ReadKey;
	my ($wchar, $hchar, $wpixels, $hpixels) = GetTerminalSize();
	$self->{width} = $wchar - $self->{chatWidth};
	$self->{height} = $hchar - 5;
	$self->{termWidth}  = $wchar;
	$self->{termHeight} = $hchar;

	if (defined($self->{scr})){
		$self->{scr}->clrscr();
		$self->printBorder();
	}
}

sub printBorder {
	my $self = shift;

	my ($fore, $back) = $self->borderColor();
	if ($useCurses){
		putCursesChr(
			$self->{_curses_map},
			0, 0,
			"╔" . "═" x ($self->{width} - 2) . "╦",
			$fore, $back
		);
		putCursesChr(
			$self->{_curses_map},
			$self->{height} - 1, 0,
			"╚" . "═" x ($self->{width} - 2) . "╩",
			$fore, $back
		);
		putCursesChr($self->{_curses_side}, 0, 0,
			"═" x ($self->{chatWidth} - 1). "╗",
			$fore, $back
		);
		putCursesChr($self->{_curses_side},
			$self->{height} - 1, 0,
			"═" x ($self->{chatWidth} - 1). "╝",
			$fore, $back
		);

	} else {
		$self->putStr(
			0, 0,
			#"╔" . "═" x ($self->{width} - 2) . "╦",
			"╔" . "═" x ($self->{width} + 1) . "╦" . "═" x ($self->{chatWidth} - 4). "╗",
			$fore, $back
		);
		$self->putStr(
			$self->{height} - 1, 0,
			#"╚" . "═" x ($self->{width} - 2) . "╩",
			"╚" . "═" x ($self->{width} + 1) . "╩" . "═" x ($self->{chatWidth} - 4). "╝",
			$fore, $back
		);

	}
	foreach my $i (1 .. $self->{height} - 2){
		if ($useCurses){
			putCursesChr(
				$self->{_curses_side},
				$i, $self->{chatWidth} - 1,
				"║",
				$fore, $back
			);
			putCursesChr(
				$self->{_curses_map},
				$i, 0,
				"║",
				$fore, $back
			);
			putCursesChr(
				$self->{_curses_map},
				$i, $self->{width} - 1,
				"║",
				$fore, $back
			);
		} else {
			$self->putStr(
				$i, 0,
				"║",
				$fore, $back
			);
			$self->putStr(
				$i, $self->{width} - 1,
				"║",
				$fore, $back
			);
			$self->putStr(
				$i, $self->{width} + $self->{chatWidth},
				"║",
				$fore, $back
			);
		}
	}
}

sub borderColor {
	my $self = shift;
    return ('WHITE', 'ON_BLACK');
}

sub setMapString {
    # TODO enable
	if ($useCurses){ return putStr(@_); }
	my $self = shift;
	my ($string, $x, $y, $color) = @_;
	my @ar = split("", $string);
	my $dy = 0;
	foreach my $chr (@ar){
		$self->setMap($x, $y + $dy, $chr, $color);
		$dy++;
	}
}

sub _drawLighting {
	my $self = shift;	

	my $offx = shift;
	my $offy = shift;

	my $time = time();

    foreach my $light ($self->_getLights()){
		my $level = int($light->{level} - ((time() - $light->{start}) * $light->{decay}));
		if ($level < 1){
			delete $lights{$light->{'key'}};
		} else {
			$self->addLighting($light->{x} + $offy, $light->{y} + $offx, $light->{level});
		}
    }
}

sub _getLights {
    my $self = shift;
	return values %lights;
}

sub _drawDefenses {
    my $self = shift;
    my $defenses = shift;
    my $posX = $self->{height} - 5;
    my $posY = 3;

    my $regex = $self->{'regex'};
    $regex =~ s/^\///;
    foreach my $word (@{$defenses}) {
        my $len = 30;
        my $fore = 'WHITE';
        my $back = 'BLACK';
        eval {
            if (defined($regex) && $regex ne '' && $word =~ m/$regex/) {
                $fore = 'RED';
                $back = 'BLACK';
            }
        };
        if (! defined($self->{destroyedShields}->{$word})) {
            $self->putMapStr(
                $posX,
                $posY,
                '╭' . '─' x $len . '╮',
                $fore,
                $back
            );
            my $padLen1 = ($len - length($word)) / 2;
            my $padLen2 = ($len - length($word)) / 2;
            if (length($word) % 2 == 1) {
                $padLen2++;
            }
            #while (($padLen1 + length($word) + $padLen2) < $len) {
                #$padLen2++;
            #}
            my $pad1 = " " x $padLen1;
            my $pad2 = " " x $padLen2;
            $self->setMapString(
                $posX + 1,
                $posY,
                "│" . $pad1 . $word . $pad2 . "│",
                $fore,
                $back
            );
            $self->putMapStr(
                $posX + 2,
                $posY,
                '╰' . '─' x $len . '╯',
                $fore,
                $back
            );
        }
        $posY += $len;
        $posY += 5;
        if ($posY + $len > $self->{width}) {
            $posY = 20;
            $posX -= 3;
        }
    }
}

sub inputRegex {
    my $self = shift;
    my $regex = $self->{'regex'};
    $regex =~ s/^\///;

    return 0 if $regex eq '';

    my $powerUsed = length($regex) + 10;
    if ($powerUsed > $self->{power}) {
        my $bell = chr(7);
        print $bell;
        return 0;
    }
    $self->{power} -= $powerUsed;

    push @{$self->{msgs}}, {
        'regex' => "/$regex/g",
        'color' => "WHITE",
    };

    my $wordsMatched = 0;
    my $wordsTotal = 0;
    foreach my $word (@{$self->{'words'}}) {
        $wordsTotal++;
        eval {
            if (defined($regex) && $regex ne '' && $word =~ m/$regex/) {
                $wordsMatched++;
                $self->{destroyedWords}->{$word} = 1;
                push @{$self->{msgs}}, {'regex' => " $word destroyed"};
            }
        };
    };

    my $shieldsMatched = 0;
    my $shieldsTotal = 0;
    foreach my $word (@{$self->{'shields'}}) {
        $shieldsTotal++;
        eval {
            if (defined($regex) && $regex ne '' && $word =~ m/$regex/) {
                $shieldsMatched++;
                $self->{destroyedShields}->{$word} = 1;
                push @{$self->{msgs}}, {
                    'regex' => " $word destroyed",
                    'color' => "RED",
                };
            }
        };
    };
    $shieldsTotal = $#{$self->{'shields'}} + 1;
    $wordsTotal = $#{$self->{'words'}} + 1;
    $shieldsMatched = keys %{$self->{'destroyedShields'}};
    $wordsMatched = keys %{$self->{'destroyedWords'}};
    #push @{$self->{msgs}}, {'regex' => "$wordsTotal vs $wordsMatched"};

    if ($shieldsMatched == $shieldsTotal) {
        push @{$self->{msgs}}, {
            'regex' => "ROUND $self->{level} LOST!",
            'color' => 'RED',
        };
        $self->{mode} = "gameOver";
        $self->{level} = 1;
        $self->{destroyedWords} = {};
        $self->{destroyedShields} = {};
        return 1;
    } elsif ($wordsMatched == $wordsTotal) {
        push @{$self->{msgs}}, {'regex' => "ROUND $self->{level} WON!"};
        $self->{score} = $self->{power};
        $self->{mode} = "wonRound";
        $self->{level}++;
        $self->{destroyedWords} = {};
        $self->{destroyedShields} = {};
        return 1;
    }
}

sub printStatusBar {
    my $self = shift;
    my ($name, $value, $max, $width, $col, $row, $r, $g, $b) = @_;

    my $statBar = '';
	my $ratio = 0;
	if ($max != 0){
		$ratio = $value / $max;
	}
	if ($ratio > 1){ $ratio = 1; }
	if ($ratio < 0){ $ratio = 0; }
	my $fullWidth = $width * $ratio;
	my $emptyWidth = ($width - $fullWidth + 1);
	
	if ($r eq 'x'){ $r = int($ratio * 5); }
	if ($g eq 'x'){ $g = int($ratio * 5); }
	if ($b eq 'x'){ $b = int($ratio * 5); }
	if ($r eq '-x'){ $r = int((1 - $ratio) * 5); }
	if ($g eq '-x'){ $g = int((1 - $ratio) * 5); }
	if ($b eq '-x'){ $b = int((1 - $ratio) * 5); }

    if ($max < 1000){
        $statBar = sprintf('|' x int($width / 3) . '%3d' . ' ' x int($width / 3) . '%3d' . ' ' x int($width / 3), $max * 0.33, $max * 0.66);
    } else {
        $statBar = sprintf('=' x int($width / 3) . '%3d' . ' ' x int($width / 3) . '%3d' . ' ' x int($width / 3), $max * 0.33, $max * 0.66);
    }

	my $nameDisplay = sprintf('%s %' . length(int $max) . 's / %'. length(int $max) . 's',
		uc($name),
		int($value),
		int($max)
	);
    
    my $widthStatus = $width - length($nameDisplay);
    $self->putInfoStr(
        $col, $row,
        '╭' . '─' x floor($widthStatus / 2) . $nameDisplay . '─' x ceil($widthStatus / 2) . '╮'
    );

    $self->putInfoStr(
        $col + 1, 0,
        "│"
    );
    $self->putInfoStr(
        $col + 1, $row + 1,
        ' ' x $fullWidth,
		'WHITE',
		'ON_RGB' . $r . $g . $b
    );
    $self->putInfoStr(
        $col + 1, $row + $fullWidth + 1,
        ' ' x $emptyWidth
    );
    $self->putInfoStr(
        $col + 1, $width + 1,
        "│"
    );
    $self->putInfoStr(
        $col + 2, $row,
        '╰' . '─' x $width . '╯'
    );
}

sub _drawWords {
	my $self = shift;	
    my $words = shift;
	my $timeElapsed = shift;
    $timeElapsed *= 3;
    my $shiftDown = $timeElapsed / 7;
    my $shiftRight = ($shiftDown % 2 == 0) ? ($timeElapsed % 7) : 6 - ($timeElapsed % 7); 
    my $posX = 1 + $shiftDown;
    my $posY = 1 + $shiftRight;
    foreach my $word (@{$words}) {
        my $len = length($word);
        my $fore = 'WHITE';
        my $back = 'BLACK';
        my $regex = $self->{'regex'};
        $regex =~ s/^\///;
        eval {
            if (defined($regex) && $regex ne '' && $word =~ m/$regex/) {
                $fore = 'GREEN';
                $back = 'BLACK';
            }
        };
        if (! defined($self->{destroyedWords}->{$word})) {
            $self->putMapStr(
                $posX,
                $posY,
                '╭' . '─' x $len . '╮',
                $fore,
                $back
            );
            $self->setMapString(
                $posX + 1,
                $posY,
                "│" . $word . "│",
                $fore,
                $back
            );
            $self->putMapStr(
                $posX + 2,
                $posY,
                '╰' . '─' x $len . '╯',
                $fore,
                $back
            );
        }
        $posY += $len;
        $posY += 3;
    }
}

sub beginLevel {
    my $self = shift;
    $self->{gameStart} = time();
    my $solution = $self->{levels}->[$self->{level}]->{solution};
    #push @{$self->{msgs}}, {'regex' => "solution: " . $solution};
    $solution =~ s#^/##g;
    $solution =~ s#/$##g;
    $self->{solution} = $solution;
    $self->{powerMax} = 100;
    $self->{power} = 100;
    $self->{warp} = { end => time() + 0.75 };
}

sub _getKeystrokes {
	my $self = shift;	
	my $scr = shift;

	# send keystrokes
    while ($scr->key_pressed()){ 
        {
            local $/ = undef;
            my $chr = $scr->getch();
            if ($self->{mode} eq 'waitingToBegin') {
                if ($chr eq "\r"){
                    $self->{level} = 1;
                    $self->{mode} = 'playing';
                    $self->beginLevel();
                }
            }
            if ($self->{mode} eq 'wonRound') {
                if ($chr eq "\r"){
                    $self->{mode} = 'playing';
                    $self->beginLevel();
                }
            }
            if ($self->{mode} eq 'gameOver') {
                if ($chr eq "\r"){
                    $self->{level} = 1;
                    $self->{mode} = 'playing';
                    $self->beginLevel();
                }
            }
            if ($self->{mode} eq 'playing') {
                if ($chr eq "~"){
                    $self->{regex} = $self->{solution};
                }
                if ($chr eq "\r"){
                    if ($self->{'regex'} eq '/exit'){
                        endwin;
                        exit;
                    }
                    $self->inputRegex();
                    $self->{'regex'} = '';
                } elsif($chr eq "\b" || ord($chr) == 127){ # 127 is delete
                    chop($self->{'regex'});
                } else {
                    $self->{'regex'} .= $chr;
                }
            }
        }
    }
}

sub exitGame {
	my $self = shift;
	my $msg = shift;
    $self->putStr(
        $self->{height} / 2, $self->{width} / 2,
        $msg
    );
	print "\r\n" . "\n" x ($self->{height} / 3);
	exit;
}

sub setCursesColor {
	# Do not assign variables for performance
    #my ($window, $foregroundColor, $backgroundColor) = @_;
    my $colorId = $cursesColors{$_[1]}->{$_[2]};
    if (!defined($colorId)){
        $colorId = $cursesColorCount++;
        init_pair($colorId, $colorCodes{$_[1]}, $colorCodes{$_[2]});
        $cursesColors{$_[1]}->{$_[2]} = $colorId;
    }
    $_[0]->attrset(COLOR_PAIR($colorId));
    return undef;
}

sub setCursesWinColor {
	# Do not assign variables for performance
    #my ($window, $foregroundColor, $backgroundColor) = @_;
    my $colorId = $cursesColors{$_[1]}->{$_[2]};
    if (!defined($colorId)){
        $colorId = $cursesColorCount++;
        init_pair($colorId, $colorCodes{$_[1]}, $colorCodes{$_[2]});
        $cursesColors{$_[1]}->{$_[2]} = $colorId;
    }
    $_[0]->wbkgd(COLOR_PAIR($colorId));
    return undef;
}

sub getColor {
    #my ($foreground, $background) = @_;
	# Do not assign variables for performance
    if (!defined($colors{$_[0]})){
        $colors{$_[0]} = color($_[0]);
    }
    return $colors{$_[0]};
}

sub setMap {
	# $self->onMap($x, $y);
	if ( ! onMap($_[0], $_[1], $_[2]) ){ return 0; }
    my $lighting = 'ON_GREY' . $lighting[$_[1]]->[$_[2]];
	if ($useCurses){ return putStr(@_, $lighting); }

	my ($self, $x, $y, $chr, $color) = @_;
	if (!defined($color)){ $color = 'RESET' }
	$chr = sprite($chr);
	$self->{map}->[$x]->[$y] = getColor($color) . $chr;
}

sub addLight {
	my $light = shift;
	my $key = $lightsKey++;
	$light->{'key'} = $lightsKey;
	$light->{'start'} = time();
	$lights{$lightsKey} = $light;
}

sub addLighting {
	my $self = shift;
	my ($x, $y, $level) = @_;
	if ( ! $self->onMap($x, $y) ){ return 0; }
	my $newLevel = $lighting[$x]->[$y] + $level;
    if ($newLevel < 23){
	    $lighting[$x]->[$y] = $newLevel;
		if ($useCurses){
            if ($self->{zoom} == 1){
			    putCursesChr($self->{_curses_map}, $x, $y, ' ', 'WHITE', 'ON_GREY' . $newLevel);
            } else {
			    putCursesChr($self->{_curses_map}, $x / $self->{zoom}, $y / $self->{zoom}, ' ', 'WHITE', 'ON_GREY' . $newLevel);
            }
		}
    }
}

sub onMap {
	my $self = shift;
	my ($x, $y) = @_;
	return ($x > 0 && $y > 0 && $x < ($self->{height} - 2) * $self->{zoom} && $y < ($self->{width} - 2) * $self->{zoom});
}

1;
