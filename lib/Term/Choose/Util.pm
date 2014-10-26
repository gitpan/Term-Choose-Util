package Term::Choose::Util;

use warnings;
use strict;
use 5.10.1;

our $VERSION = '0.000_02';
use Exporter 'import';
our @EXPORT_OK = qw( term_size print_hash util_readline insert_sep length_longest choose_a_number choose_a_subset
                     choose_multi choose_a_directory unicode_trim unicode_sprintf );

use Encode                qw( decode encode );
use File::Basename        qw( dirname );
use File::Spec::Functions qw( catdir );
use List::Util            qw( sum );

use Encode::Locale;
use Term::Choose  qw( choose );
use Term::ReadKey qw( GetTerminalSize ReadKey ReadMode );
use Text::LineFold;
use Unicode::GCString;

use if $^O eq 'MSWin32', 'Term::Size::Win32' => q( chars );
use if $^O eq 'MSWin32', 'Win32::Console::ANSI';

END { ReadMode 0 }

sub BSPACE                  () { 0x7f }
sub CLEAR_TO_END_OF_SCREEN  () { "\e[0J" }
sub CLEAR_SCREEN            () { "\e[1;1H\e[0J" }
sub SAVE_CURSOR_POSITION    () { "\e[s" }
sub RESTORE_CURSOR_POSITION () { "\e[u" }


sub term_size {
    my ( $handle_out ) = shift // \*STDOUT;
    if ( $^O eq 'MSWin32' ) {
        my ( $width, $heigth ) = chars( $handle_out );
        return $width - 1, $heigth;
    }
    return( ( GetTerminalSize( $handle_out ) )[ 0, 1 ] );
}


sub length_longest {
    my ( $list ) = @_;
    my $len = [];
    my $longest = 0;
    for my $i ( 0 .. $#$list ) {
        my $gcs = Unicode::GCString->new( $list->[$i] );
        $len->[$i] = $gcs->columns();
        $longest = $len->[$i] if $len->[$i] > $longest;
    }
    if ( wantarray ) {
        $longest, $len;
    }
    else {
        $longest;
    }
}


sub print_hash {
    my ( $hash, $opt ) = @_;
    $opt //= {};
    my $left_margin  = $opt->{left_margin}  // 1;
    my $right_margin = $opt->{right_margin} // 2;
    my $clear        = $opt->{clear_screen} // 1;
    my $mouse        = $opt->{mouse}        // 1;
    my $keys         = $opt->{keys}         // [ sort keys %$hash ];
    my $len_key      = $opt->{len_key}      // length_longest( $keys );
    my $maxcols      = $opt->{maxcols};
    #-----------------------------------------------------------------#
    my $line_fold    = $opt->{lf} // { Charset => 'utf-8', Newline => "\n",
                                       OutputCharset => '_UNICODE_', Urgent => 'FORCE' };
    my $term_width = ( term_size() )[0];
    if ( ! $maxcols || $maxcols > $term_width  ) {
        $maxcols = $term_width - $right_margin;
    }
    $len_key += $left_margin;
    my $s_tab = $len_key + length( ' : ' );
    my $lf = Text::LineFold->new( %$line_fold, ColMax => $maxcols );
    my @vals = ();
    for my $key ( @$keys ) {
        next if ! exists $hash->{$key};
        my $pr_key = sprintf "%*.*s : ", $len_key, $len_key, $key;
        my $text = $lf->fold( '' , ' ' x $s_tab, $pr_key . ( ref( $hash->{$key} ) ? ref( $hash->{$key} ) : $hash->{$key} ) );
        $text =~ s/\R+\z//;
        for my $val ( split /\R+/, $text ) {
            push @vals, $val;
        }
    }
    choose(
        [ @vals ],
        { layout => 3, justify => 0, mouse => $mouse, clear_screen => $clear }
    );
}


sub util_readline {
    my ( $prompt, $opt ) = @_;
    $opt //= {};
    my $str = '';
    local $| = 1;
    print SAVE_CURSOR_POSITION;
    _print_readline( $prompt, $str, $opt );
    ReadMode 'cbreak';
    while ( 1 ) {
        my $key = ReadKey;
        return if ! defined $key;
        if ( $key eq "\cD" ) {
            print "\n";
            return;
        }
        elsif ( $key eq "\n" or $key eq "\r" ) {
            print "\n";
            return $str;
        }
        elsif ( ord $key == BSPACE || $key eq "\cH" ) {
            $str =~ s/\X\z// if $str; # ?
            _print_readline( $prompt, $str, $opt );
            next;
        }
        elsif ( $key !~ /^\p{Print}\z/ ) {
            _print_readline( $prompt, $str, $opt );
            next;
        }
        $str .= $key;
        _print_readline( $prompt, $str, $opt );
    }
    ReadMode 0;
    return $str;
}

sub _print_readline {
    my ( $prompt, $str, $opt ) = @_;
    my $no_echo = $opt->{no_echo} // 0;
    print RESTORE_CURSOR_POSITION;
    print CLEAR_TO_END_OF_SCREEN;
    print $prompt . ( $no_echo ? '' : $str );
}


sub choose_a_directory {
    my ( $dir, $opt ) = @_;
    $opt //= {};
    my $clear  = $opt->{clear_screen} // 1;
    my $mouse  = $opt->{mouse}        // 1;
    my $layout = $opt->{layout}       // 1;
    #-------------------------------------------#
    my $confirm      = $opt->{confirm}      // '<OK>';
    my $up           = $opt->{up}           // '<UP>';
    my $back         = $opt->{back}         // '<<';
    my $curr     = $dir;
    my $previous = $dir;
    while ( 1 ) {
        my ( $dh, @dirs );
        if ( ! eval {
            opendir( $dh, $dir ) or die $!;
            1 }
        ) {
            print "$@";
            choose( [ 'Press Enter:' ], { prompt => '' } );
            $dir = dirname $dir;
            next;
        }
        while ( my $file = readdir $dh ) {
            next if $file =~ /^\.\.?\z/;
            push @dirs, decode( 'locale_fs', $file ) if -d catdir $dir, $file;
        }
        closedir $dh;
        my $prompt = 'Current dir: "' . decode( 'locale_fs', $curr ) . '"' . "\n";
        $prompt   .= '    New dir: "' . decode( 'locale_fs', $dir  ) . '"' . "\n\n";
        my $choice = choose(
            [ undef, $confirm, $up, sort( @dirs ) ],
            { prompt => $prompt, undef => $back, default => 0, mouse => $mouse,
              layout => $layout, clear_screen => $clear }
        );
        return if ! defined $choice;
        return $previous if $choice eq $confirm;
        $choice = encode( 'locale_fs', $choice );
        $dir = $choice eq $up ? dirname( $dir ) : catdir( $dir, $choice );
        $previous = $dir;
    }
}


sub choose_a_number {
    my ( $digits, $opt ) = @_;
    $opt //= {};
    #                $opt->{current}
    my $thsd_sep   = $opt->{thsd_sep}     // ',';
    my $name       = $opt->{name}         // '';
    my $clear      = $opt->{clear_screen} // 1;
    my $mouse      = $opt->{mouse}        // 1;
    #-----------------------------------------------#
    my $back       = $opt->{back}       // 'BACK';
    my $back_short = $opt->{back_short} // '<<';
    my $confirm    = $opt->{confirm}    // 'CONFIRM';
    my $reset      = $opt->{reset}      // 'reset';
    my $tab        = '  -  ';
    my $gcs_tab    = Unicode::GCString->new( $tab );
    my $len_tab = $gcs_tab->columns;
    my $longest    = $digits;
    $longest += int( ( $digits - 1 ) / 3 ) if $thsd_sep ne '';
    my @choices_range = ();
    for my $di ( 0 .. $digits - 1 ) {
        my $begin = 1 . '0' x $di;
        $begin = 0 if $di == 0;
        $begin = insert_sep( $begin, $thsd_sep );
        ( my $end = $begin ) =~ s/^[01]/9/;
        unshift @choices_range, sprintf " %*s%s%*s", $longest, $begin, $tab, $longest, $end;
    }
    my $confirm_tmp = sprintf "%-*s", $longest * 2 + $len_tab, $confirm;
    my $back_tmp    = sprintf "%-*s", $longest * 2 + $len_tab, $back;
    my ( $term_width ) = term_size();
    my $gcs_longest_range = Unicode::GCString->new( $choices_range[0] );
    if ( $gcs_longest_range->columns > $term_width ) {
        @choices_range = ();
        for my $di ( 0 .. $digits - 1 ) {
            my $begin = 1 . '0' x $di;
            $begin = 0 if $di == 0;
            $begin = insert_sep( $begin, $thsd_sep );
            unshift @choices_range, sprintf "%*s", $longest, $begin;
        }
        $confirm_tmp = $confirm;
        $back_tmp    = $back;
    }
    my %numbers;
    my $result;
    my $undef = '--';

    NUMBER: while ( 1 ) {
        my $new_result = $result // $undef;
        my $prompt = '';
        if ( exists $opt->{current} ) {
            $opt->{current} = defined $opt->{current} ? insert_sep( $opt->{current}, $thsd_sep ) : $undef;
            $prompt .= sprintf "%s%*s\n",   'Current ' . $name . ': ', $longest, $opt->{current};
            $prompt .= sprintf "%s%*s\n\n", '    New ' . $name . ': ', $longest, $new_result;
        }
        else {
            $prompt = sprintf "%s%*s\n\n", $name . ': ', $longest, $new_result;
        }
        # Choose
        my $range = choose(
            [ undef, @choices_range, $confirm_tmp ],
            { prompt => $prompt, layout => 3, justify => 1, mouse => $mouse,
              clear_screen => $clear, undef => $back_tmp }
        );
        return if ! defined $range;
        if ( $range eq $confirm_tmp ) {
            #return $undef if ! defined $result;
            return if ! defined $result;
            $result =~ s/\Q$thsd_sep\E//g if $thsd_sep ne '';
            return $result;
        }
        my $zeros = ( split /\s*-\s*/, $range )[0];
        $zeros =~ s/^\s*\d//;
        ( my $zeros_no_sep = $zeros ) =~ s/\Q$thsd_sep\E//g if $thsd_sep ne '';
        my $count_zeros = length $zeros_no_sep;
        my @choices = $count_zeros ? map( $_ . $zeros, 1 .. 9 ) : ( 0 .. 9 );
        # Choose
        my $number = choose(
            [ undef, @choices, $reset ],
            { prompt => $prompt, layout => 1, justify => 2, order => 0,
              mouse => $mouse, clear_screen => $clear, undef => $back_short }
        );
        next if ! defined $number;
        if ( $number eq $reset ) {
            delete $numbers{$count_zeros};
        }
        else {
            $number =~ s/\Q$thsd_sep\E//g if $thsd_sep ne '';
            $numbers{$count_zeros} = $number;
        }
        $result = sum( @numbers{keys %numbers} );
        $result = insert_sep( $result, $thsd_sep );
    }
}


sub choose_a_subset {
    my ( $available, $opt ) = @_;
    $opt //= {};
    #             $opt->{current}
    my $layout  = $opt->{layout}  // 3;
    my $clear   = $opt->{clear_screen} // 1;
    my $mouse   = $opt->{mouse}        // 1;
    #--------------------------------------#
    my $confirm = $opt->{confirm} // 'CONFIRM';
    my $back    = $opt->{back}    // 'BACK';
    $confirm = '  ' . $confirm;
    $back    = '  ' . $back;
    my $key_cur = 'Current > ';
    my $key_new = '    New > ';
    my $gcs_cur = Unicode::GCString->new( $key_cur );
    my $gcs_new = Unicode::GCString->new( $key_new );
    my $len_key = $gcs_cur->columns > $gcs_new->columns ? $gcs_cur->columns : $gcs_new->columns;
    my $new = [];

    while ( 1 ) {
        my $prompt = '';
        $prompt .= $key_cur . join( ', ', map { "\"$_\"" } @{$opt->{current}} ) . "\n"   if defined $opt->{current};
        $prompt .= $key_new . join( ', ', map { "\"$_\"" } @$new )              . "\n\n";
        $prompt .= 'Choose:';
        my @pre = ( undef, $confirm );
        # Choose
        my @choice = choose(
            [ @pre, map( "- $_", @$available ) ],
            { prompt => $prompt, layout => $layout, mouse => $mouse, clear_screen => $clear, justify => 0,
              lf => [ 0, $len_key ], no_spacebar => [ 0 .. $#pre ], undef => $back }
        );
        if ( ! @choice || ! defined $choice[0] ) {
            if ( @$new ) {
                $new = [];
                next;
            }
            else {
                return;
            }
        }
        if ( $choice[0] eq $confirm ) {
            shift @choice;
            push @$new, map { s/^-\s//; $_ } @choice if @choice;
            return $new if @$new;
            return;
        }
        push @$new, map { s/^-\s//; $_ } @choice;
    }
}


sub choose_multi {
    my ( $menu, $val, $opt ) = @_;
    $opt //= {};
    my $in_place = $opt->{in_place}     // 1;
    my $clear    = $opt->{clear_screen} // 1;
    my $mouse    = $opt->{mouse}        // 1;
    #-----------------------------------#
    my $back     = $opt->{back}     // 'BACK';
    my $confirm  = $opt->{confirm}  // 'CONFIRM';
    $back    = '  ' . $back;
    $confirm = '  ' . $confirm;
    my $longest = 0;
    my $tmp     = {};
    for my $sub ( @$menu ) {
        my ( $key, $prompt ) = @$sub;
        my $gcs = Unicode::GCString->new( $prompt );
        my $length = $gcs->columns();
        $longest = $length if $length > $longest;
        $tmp->{$key} = $val->{$key};
    }
    my $count = 0;

    while ( 1 ) {
        my @print_keys;
        for my $sub ( @$menu ) {
            my ( $key, $prompt, $avail ) = @$sub;
            my $current = $avail->[$tmp->{$key}];
            push @print_keys, sprintf "%-*s [%s]", $longest, $prompt, $current;
        }
        my @pre = ( undef, $confirm );
        my $choices = [ @pre, @print_keys ];
        # Choose
        my $idx = choose(
            $choices,
            { prompt => 'Choose:', index => 1, layout => 3, justify => 0,
              mouse => $mouse, clear_screen => $clear, undef => $back }
        );
        return if ! defined $idx;
        my $choice = $choices->[$idx];
        return if ! defined $choice;
        if ( $choice eq $confirm ) {
            my $change = 0;
            if ( $count ) {
                for my $sub ( @$menu ) {
                    my $key = $sub->[0];
                    next if $val->{$key} == $tmp->{$key};
                    $val->{$key} = $tmp->{$key} if $in_place;
                    $change++;
                }
            }
            return if ! $change;
            return 1 if $in_place;
            return $tmp;
        }
        my $key   = $menu->[$idx-@pre][0];
        my $avail = $menu->[$idx-@pre][2];
        $tmp->{$key}++;
        $tmp->{$key} = 0 if $tmp->{$key} == @$avail;
        $count++;
    }
}


sub insert_sep {
    my ( $number, $separator ) = @_;
    return if ! defined $number;
    $separator //= ',';
    $number =~ s/(\d)(?=(?:\d{3})+\b)/$1$separator/g;
    return $number;
}



# from https://rt.cpan.org/Public/Bug/Display.html?id=84549

sub unicode_trim {
    my ( $unicode, $len ) = @_;
    return '' if $len <= 0;
    my $gcs = Unicode::GCString->new( $unicode );
    my $pos = $gcs->pos;
    $gcs->pos( 0 );
    my $cols = 0;
    my $gc;
    while ( defined( $gc = $gcs->next ) ) {
        if ( $len < ( $cols += $gc->columns ) ) {
            my $ret = $gcs->substr( 0, $gcs->pos - 1 );
            $gcs->pos( $pos );
            return $ret->as_string;
        }
    }
    $gcs->pos( $pos );
    return $gcs->as_string;
}


sub unicode_sprintf {
    my ( $unicode, $avail_width, $right_justify ) = @_;
    my $gcs = Unicode::GCString->new( $unicode );
    my $colwidth = $gcs->columns;
    if ( $colwidth > $avail_width ) {
        my $pos = $gcs->pos;
        $gcs->pos( 0 );
        my $cols = 0;
        my $gc;
        while ( defined( $gc = $gcs->next ) ) {
            if ( $avail_width < ( $cols += $gc->columns ) ) {
                my $ret = $gcs->substr( 0, $gcs->pos - 1 );
                $gcs->pos( $pos );
                return $ret->as_string;
            }
        }
    }
    elsif ( $colwidth < $avail_width ) {
        if ( $right_justify ) {
            $unicode = " " x ( $avail_width - $colwidth ) . $unicode;
        }
        else {
            $unicode = $unicode . " " x ( $avail_width - $colwidth );
        }
    }
    return $unicode;
}





1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Term::Choose::Util - CLI related functions.

=head1 VERSION

Version 0.000_02

=cut

=head1 SYNOPSIS

See L</SUBROUTINES>.

=head1 DESCRIPTION

This module provides some CLI related functions required by L<App::DBBrowser>, L<Term::TablePrint> and L<App::YTDL>.

=head1 EXPORT

Nothing by default.

=head1 SUBROUTINES

Ensure the encoding layer for STDOUT, STDERR and STDIN are set to the correct value.

Values in brackets are default values.

=head2 choose_a_directory

    $chosen_directory = choose_a_directory( $dir, { layout => 1 } )

With C<choose_a_directory> the user can browse through the directory tree (as far as the granted rights permit it) and
choose a directory which is returned.

The first argument is the starting point directory. The second and optional argument are the options (a reference to a
hash). The options are:

=over

=item

C<layout>

See C<layout> at L<Term::Choose/OPTIONS>

Values: 0, [1], 2, 3.

=item

C<clear_screen>

If enabled, the screen is cleared before the output.

Values: 0, [1].

=item

C<mouse>

See C<mouse> at L<Term::Choose/OPTIONS>.

Values: [0], 1, 2, 3, 4.

=back

=head2 choose_a_number

    for ( 1 .. 5 ) {
        $current = $new
        $new = choose_a_number( 5, { current => $current, name => 'Testnumber' }  );
    }

This function lets you choose/compose a number (unsigned integer) which is returned.

The fist argument - digits - is an integer and determines the range of the available numbers. For example setting the
first argument to 6 would offer a range from 0 to 999999.

The second and optional argument is a reference to a hash with these keys (options):

=over

=item

C<current>

The current value. If set two prompt lines are displayed: one for the current number and one for the new number.

=item

C<name>

Sets the name of the number seen in the prompt line.

Default: empty string ("");

=item

C<thsd_sep>

Sets the thousands separator.

Default: comma (",").

=item

C<clear_screen>

If enabled, the screen is cleared before the output.

Values: 0, [1].

=item

C<mouse>

See C<mouse> at L<Term::Choose/OPTIONS>.

Values: [0], 1, 2, 3, 4.

=back

=head2 choose_a_subset

    $subset = choose_a_subset( \@available_items, { current => \@current_subset } )

C<choose_a_subset> lets you choose a subset from a list.

As the first argument it is required a reference to an array which provides the available list.

The optional second argument is a hash reference. The following option is available:

=over

=item

C<current>

This option expects the current subset as its value (a reference to an array). If set two prompt lines are displayed:
one for the current subset and one for the new subset.

The subset is returned as an array reference.

=item

C<layout>

See C<layout> at L<Term::Choose/OPTIONS>.

Values: 0, 1, 2, [3].

=item

C<clear_screen>

If enabled, the screen is cleared before the output.

Values: 0, [1].

=item

C<mouse>

See C<mouse> at L<Term::Choose/OPTIONS>.

Values: [0], 1, 2, 3, 4.

=back

=head2 choose_multi

    $tmp = choose_multi( $menu, $config, { in_place => 0 } )
    if ( defined $tmp ) {
        for my $key ( keys %$tmp ) {
            $config->{$key} = $tmp->{$key};
        }
    }

The first argument is a reference to an array of arrays which have three elements:

=over

=item

the key/option-name

=item

the prompt string

=item

an array reference with the possible values related to the key/option.

=back

The second argument is a hash reference:

=over

=item

the keys are the option names

=item

the values are the indexes of the current value of the respective key.

=back

    $menu = [
        [ 'enable_logging', "- Enable logging", [ 'NO', 'YES' ] ],
        [ 'case_sensitive', "- Case sensitive", [ 'NO', 'YES' ] ],
        ...
    ];

    $config = {
        'enable_logging' => 0,
        'case_sensitive' => 1,
        ...
    };

The optional third argument is a reference to a hash. The keys are

=over

=item

C<in_place>

If enabled the configurations hash (passed as second argument) is edited in place.

Values: 0, [1].

=item

C<clear_screen>

If enabled, the screen is cleared before the output.

Values: 0, [1].

=item

C<mouse>

See C<mouse> at L<Term::Choose/OPTIONS>.

Values: [0], 1, 2, 3, 4.

=back

When C<choose_multi> is called it displays for each array entry a row with the prompt string and the current value.
It is possible to scroll through the rows. If a row is selected the set and displayed value changes to the next. If the
end of the list of the values is reached it begins from the beginning of the list.

C<choose_multi> returns nothing if no changes are made. If the user has changed values C<choose_multi> modifies the hash
passed as the second argument in place and returns 1. With the option C<in_place> set to 0 C<choose_multi> does no in
place modifications but modifies a copy of the configuration hash. A refence to that copy is then returned.

=head2 insert_sep

    $number = insert_sep( $integer, $separator );

Inserts a thousands separator.

The following substitution is applied to the integer (or any Unicode string) passed with the first argument.

    $number =~ s/(\d)(?=(?:\d{3})+\b)/$1$separator/g;

After the substitution the number is returned.

If the first argument is not defined it is returned nothing immediately.

A thousands separator can be passed with a second argument.

The thousands separator defaults to a comma (",").

=head2 length_longest

C<length_longest> expects as its argument a list of decoded strings passed a an array reference.

    $longest = length_longest( \@elements );

    ( $longest, $length ) = length_longest( \@elements );


In scalar context C<length_longest> returns the length of the longest string - in list context it return a list where the
the first item is the length of the longest string and the second is a reference to an array where the elements are the
length of the corrensponding elements from array (reference) passed as the argument.

"Length" means here number of print columns as returned by the C<columns> method from  L<Unicode::GCString>.

=head2 print_hash

Prints a simple hash to STDOUT (or STDERR if the output is redirected). Nested hashes are not supported. If the hash
has more keys than the terminal rows the output is divided up on several pages. The user can scroll through the single
lines of the hash. The output of the hash is closed, when the user presses C<Return>.

The first argument is the hash passed as a reference. The optional second argument is also a hash reference which
allowes to set the following options:

=over

=item

C<keys>

The keys which should be printed in the given order. The keys are passed with an array reference. If not set it defaults
to

    [ sort keys %$hash ]

=item

C<len_key>

The value is the available width for printing the keys. The default value is the length (of print columns) of the
longest key.

=item

C<maxcols>

The maximum width of the output. If not set or set to 0 or set to a value higher than the terminal width the maximum
terminal width is used instead.

=item

C<left_margin>

C<left_margin> is added to C<len_key>. It defaults to 1.

=item

C<right_margin>

The C<right_margin> is subtracted from C<maxcols> if C<maxcols> is the maximum terminal width. The default value is 2.

=item

C<clear_screen>

If enabled, the screen is cleared before the output.

Values: 0, [1].

=item

C<mouse>

See C<mouse> at L<Term::Choose/OPTIONS>.

Values: [0], 1, 2, 3, 4.

=back

=head2 term_size

C<term_size> returns the current terminal width and the current terminal heigth.

    ( $width, $heigth ) = term_size()

If the OS is MSWin32 C<chars> from L<Term::Size::Win32> is used to get the terminal width and the terminal heigth else
C<GetTerminalSize> form L<Term::ReadKey> is used.

On MSWin32 OS,  if it is written to the last column on the screen the cursor goes to the first column of the next line.
To prevent this newline when writing to the terminal C<term_size> subtracts 1 from the terminal width before returning
the width if the OS is MSWin32.

As an argument it can be passed an filehandle. With no argument the filehandle defaults to C<STDOUT>.

=head2 util_readline

C<util_readline> reads a line.

    $string = util_readline( $prompt, { no_echo => 0 } )

The fist argument is the prompt string. The optional second argument is a reference to a hash. The only key/option is

=over

=item

C<no_echo>

Values: [0], 1.

=back

C<util_readline> returns C<undef> if C<Strg>-C<D> is pressed independently of whether the input buffer is empty or
filled.

It is not required to C<chomp> the returned string.

=head2 unicode_sprintf

    $unicode = unicode_sprintf( $unicode, $available_width, $rightpad );

C<unicode_sprintf> expects 2 or 3 arguments: the first argument is a decoded string, the second the available width and
the third and optional argument tells how to justify the string.

If the length of the string is greater than the available width it is truncated to the available width. If the string is
equal to the available width nothing is done with the string. If the string length is less than the available width,
C<unicode_sprintf> adds spaces to the string until the string length is equal to the available width. If the third
argument is set to a true value, the spaces are added at the beginning of the string else they are added at the end of
the string.

"Length" or "width" means here number of print columns as returned by the C<columns> method from L<Unicode::GCString>.

=head2 unicode_trim

    $unicode = unicode_trim( $unicode, $length )

The first argument is a decoded string, the second argument is the length.

If the string is longer than passed length it is trimmed to that length at the right site and returned else the string is returned as it
is.

"Length" means here number of print columns as returned by the C<columns> method from  L<Unicode::GCString>.

=head1 REQUIREMENTS

=head2 Perl version

Requires Perl version 5.10.1 or greater.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Term::TablePrint

=head1 AUTHOR

Matthäus Kiem <cuer2s@gmail.com>

=head1 CREDITS

Thanks to the L<Perl-Community.de|http://www.perl-community.de> and the people form
L<stackoverflow|http://stackoverflow.com> for the help.

=head1 LICENSE AND COPYRIGHT

Copyright 2014 Matthäus Kiem.

This library is free software; you can redistribute it and/or modify it under the same terms as Perl 5.10.0. For
details, see the full text of the licenses in the file LICENSE.

=cut
