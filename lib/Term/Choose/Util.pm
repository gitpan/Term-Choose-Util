package Term::Choose::Util; # hide from PAUSE


use warnings;
use strict;
use 5.10.1;

our $VERSION = '0.000_01';
use Exporter 'import';
our @EXPORT_OK = qw( term_size util_readline insert_sep
                     choose_a_number choose_a_subset choose_multi choose_a_directory
                     unicode_trim unicode_sprintf );

#use Carp                  qw( croak );
use Encode                qw( decode encode );
use File::Basename        qw( dirname );
use File::Spec::Functions qw( catdir );
use List::Util            qw( sum );

use Encode::Locale;
use Term::Choose  qw( choose );
use Term::ReadKey qw( GetTerminalSize ReadKey ReadMode );
use Text::LineFold;
use Unicode::GCString;

#use if $^O eq 'MSWin32', 'Term::Size::Win32' => q( chars );
#use if $^O eq 'MSWin32', 'Win32::Console::ANSI';

END { ReadMode 0 }

BEGIN {
    if ( $^O eq 'MSWin32' ) {
        require Term::Size::Win32;
        Term::Size::Win32::->import( 'chars' );
        require Win32::Console::ANSI;
    }
}

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
    else {
        return( ( GetTerminalSize( $handle_out ) )[ 0, 1 ] );
    }
}


sub util_readline {
    my ( $prompt, $opt ) = @_;
    $opt->{no_echo} //= 0;
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
    print RESTORE_CURSOR_POSITION;
    print CLEAR_TO_END_OF_SCREEN;
    print $prompt . ( $opt->{no_echo} ? '' : $str );
}


sub choose_a_directory {
    my ( $dir, $opt ) = @_;
    $opt->{confirm}      //= '<OK>';
    $opt->{up}           //= '<UP>';
    $opt->{back}         //= '<<';
    $opt->{clear_screen} //= 1;
    $opt->{layout}       //= 1;
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
            [ undef, $opt->{confirm}, $opt->{up}, sort( @dirs ) ],
            { prompt => $prompt, undef => $opt->{back}, default => 0,
              layout => $opt->{layout}, clear_screen => $opt->{clear_screen} }
        );
        return if ! defined $choice;
        return $previous if $choice eq $opt->{confirm};
        $choice = encode( 'locale_fs', $choice );
        $dir = $choice eq $opt->{up} ? dirname( $dir ) : catdir( $dir, $choice );
        $previous = $dir;
    }
}


sub choose_a_number {
    my ( $digits, $opt ) = @_;
    $opt->{thsd_sep}   //= ',';
    $opt->{name}       //= '';
    $opt->{back}       //= 'BACK';
    $opt->{back_short} //= '<<';
    $opt->{confirm}    //= 'CONFIRM';
    $opt->{reset}      //= 'reset';
    my $tab        = '  -  ';
    my $gcs_tab    = Unicode::GCString->new( $tab );
    my $len_tab = $gcs_tab->columns;
    my $longest    = $digits;
    $longest += int( ( $digits - 1 ) / 3 ) if $opt->{thsd_sep} ne '';
    my @choices_range = ();
    for my $di ( 0 .. $digits - 1 ) {
        my $begin = 1 . '0' x $di;
        $begin = 0 if $di == 0;
        $begin = insert_sep( $begin, $opt->{thsd_sep} );
        ( my $end = $begin ) =~ s/^[01]/9/;
        unshift @choices_range, sprintf " %*s%s%*s", $longest, $begin, $tab, $longest, $end;
    }
    my $confirm = sprintf "%-*s", $longest * 2 + $len_tab, $opt->{confirm};
    my $back    = sprintf "%-*s", $longest * 2 + $len_tab, $opt->{back};
    my ( $term_width ) = term_size();
    my $gcs_longest_range = Unicode::GCString->new( $choices_range[0] );
    if ( $gcs_longest_range->columns > $term_width ) {
        @choices_range = ();
        for my $di ( 0 .. $digits - 1 ) {
            my $begin = 1 . '0' x $di;
            $begin = 0 if $di == 0;
            $begin = insert_sep( $begin, $opt->{thsd_sep} );
            unshift @choices_range, sprintf "%*s", $longest, $begin;
        }
        $confirm = $opt->{confirm};
        $back    = $opt->{back};
    }
    my %numbers;
    my $result;
    my $undef = '--';

    NUMBER: while ( 1 ) {
        my $new_result = $result // $undef;
        my $prompt = '';
        if ( exists $opt->{current} ) {
            $opt->{current} = defined $opt->{current} ? insert_sep( $opt->{current}, $opt->{thsd_sep} ) : $undef;
            $prompt .= sprintf "%s%*s\n",   'Current ' . $opt->{name} . ': ', $longest, $opt->{current};
            $prompt .= sprintf "%s%*s\n\n", '    New ' . $opt->{name} . ': ', $longest, $new_result;
        }
        else {
            $prompt = sprintf "%s%*s\n\n", $opt->{name} . '> ', $longest, $new_result;
        }
        # Choose
        my $range = choose(
            [ undef, @choices_range, $confirm ],
            { prompt => $prompt, layout => 3, justify => 1, clear_screen => 1, undef => $back }
        );
        return if ! defined $range;
        if ( $range eq $confirm ) {
            #return $undef if ! defined $result;
            return if ! defined $result;
            $result =~ s/\Q$opt->{thsd_sep}\E//g if $opt->{thsd_sep} ne '';
            return $result;
        }
        my $zeros = ( split /\s*-\s*/, $range )[0];
        $zeros =~ s/^\s*\d//;
        ( my $zeros_no_sep = $zeros ) =~ s/\Q$opt->{thsd_sep}\E//g if $opt->{thsd_sep} ne '';
        my $count_zeros = length $zeros_no_sep;
        my @choices = $count_zeros ? map( $_ . $zeros, 1 .. 9 ) : ( 0 .. 9 );
        # Choose
        my $number = choose(
            [ undef, @choices, $opt->{reset} ],
            { prompt => $prompt, layout => 1, justify => 2, order => 0, clear_screen => 1, undef => $opt->{back_short} }
        );
        next if ! defined $number;
        if ( $number eq $opt->{reset} ) {
            delete $numbers{$count_zeros};
        }
        else {
            $number =~ s/\Q$opt->{thsd_sep}\E//g if $opt->{thsd_sep} ne '';
            $numbers{$count_zeros} = $number;
        }
        $result = sum( @numbers{keys %numbers} );
        $result = insert_sep( $result, $opt->{thsd_sep} );
    }
}


sub choose_a_subset {
    my ( $available, $opt ) = @_;
    $opt->{layout}  //= 3;
    $opt->{confirm} //= 'CONFIRM';
    $opt->{back}    //= 'BACK';
    $opt->{confirm} = '  ' . $opt->{confirm};
    $opt->{back}    = '  ' . $opt->{back};
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
        my @pre = ( undef, $opt->{confirm} );
        # Choose
        my @choice = choose(
            [ @pre, map( "- $_", @$available ) ],
            { prompt => $prompt, layout => $opt->{layout}, clear_screen => 1, justify => 0, lf => [ 0, $len_key ],
            no_spacebar => [ 0 .. $#pre ], undef => $opt->{back} }
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
        if ( $choice[0] eq $opt->{confirm} ) {
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
    $opt->{in_place} //= 1;
    $opt->{back}     //= 'BACK';
    $opt->{confirm}  //= 'CONFIRM';
    $opt->{back}    = '  ' . $opt->{back};
    $opt->{confirm} = '  ' . $opt->{confirm};
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
        my @pre = ( undef, $opt->{confirm} );
        my $choices = [ @pre, @print_keys ];
        # Choose
        my $idx = choose(
            $choices,
            { prompt => 'Choose:', index => 1, layout => 3, justify => 0, clear_screen => 1, undef => $opt->{back} }
        );
        return if ! defined $idx;
        my $choice = $choices->[$idx];
        return if ! defined $choice;
        if ( $choice eq $opt->{confirm} ) {
            my $change = 0;
            if ( $count ) {
                for my $sub ( @$menu ) {
                    my $key = $sub->[0];
                    next if $val->{$key} == $tmp->{$key};
                    $val->{$key} = $tmp->{$key} if $opt->{in_place};
                    $change++;
                }
            }
            return if ! $change;
            return 1 if $opt->{in_place};
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

Version 0.000_01

=cut

=head1 SYNOPSIS

See L</SUBROUTINES>.

=head1 DESCRIPTION

This module provides some CLI related functions required by L<App::DBBrowser>, L<Term::TablePrint> and L<App::YTDL>.

=head1 EXPORT

Nothing by default.

=head1 SUBROUTINES

=head2 term_size

C<term_size> returns the current terminal width and the current terminal heigth.

    ( $width, $heigth ) = term_size()

If the OS is MSWin32 C<chars> from L<Term::Size::Win32> is used to get the terminal width and the terminal heigth else
C<GetTerminalSize> form L<Term::ReadKey> is used.

On windows, if it is written to the last column on the screen the cursor goes to the first column of the next line. To
prevent this newline C<term_size> subtracts 1 from the terminal width before returning the width if the OS is MSWin32.

As an argument it can be passed an filehandle. With no argument the filehandle defaults to C<STDOUT>.

=head2 util_readline

C<util_readline> reads a line.

    $string = util_readline( $prompt, { no_echo => 0 } )

The fist argument is the prompt string. The optional second argument is a reference to a hash. The only key/option is
C<no_echo> which can be set to C<0> or C<1>. It defaults to C<0>.

C<util_readline> returns C<undef> if C<Strg>-C<D> is pressed independently of whether the input buffer is empty or
filled.

It is not required to C<chomp> the returned string.

=head2 choose_a_number

    $chosen_number = choose_a_number( $digits, { thsd_sep => ',', name => 'Rows' } );

This function lets you choose/compose a number (unsigned integer) which is returned.

The fist argument is an integer and determines the range of numbers that can be chosen. For example setting the first
argument to C<6> would offer a range from 0 to 999999.

The second and optional argument is a reference to a hash:

=head4 thsd_sep

Sets the thousands separator.

Defaults to the comma (",").

=head4 name

Sets the name of the number seen in the prompt line.

Defaults to the empty string ("");

=head2 choose_a_subset

    $subset = choose_a_subset( \@available_items )

C<choose_a_subset> lets you choose a subset from a list.

As an argument it is required a reference to an array which provides the available list.

The subset is returned as an array reference.

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

The third argument is a reference to a hash. The only key of this hash is C<in_place>. It defaults to C<1>.

When C<choose_multi> is called it displays for each array entry as a line with the prompt string and the current value.
It is possible to scroll through the rows. If a row is selected the set and displayed value changes to the next. If the
end of the list of the values is reached it begins from the beginning of the list.

C<choose_multi> returns nothing if no changes are made. If the user has changed values C<choose_multi> modifies the hash
passed as the second argument in place and returns 1. With the option C<in_place> set to C<0> C<choose_multi> does no in
place modifications but returns the modified "key => value" pairs as a hash reference.

=head2 choose_a_directory

    $chosen_directory = choose_a_directory( $dir )

With C<choose_a_directory> the user can browse through the directory tree ( as far as the granted rights permit it ) and
choose a directory which is returned.

=head2 insert_sep

    $number = insert_sep( $number, $separator );

Inserts a thousands separator.

The following substitution is applied to the number passed with the first argument.

    $number =~ s/(\d)(?=(?:\d{3})+\b)/$1$separator/g;

After the substitution the number is returned.

If the first argument is not defined it is returned nothing immediately.

A thousands separator can be passed with a second argument.

The thousands separator defaults to a comma (",").

=head2 unicode_trim

    $unicode = unicode_trim( $unicode, $length )

The first argument is a correctly decoded string, the second argument is the length.

If the string is longer than passed length it is trimmed to that length and returned else the string is returned as it
is.

"Length" means here number of print columns as returned by the C<columns> method from  L<Unicode::GCString>.

=head2 unicode_sprintf

    $unicode = unicode_sprintf( $unicode, $available_width, $right_justify );

C<unicode_sprintf> expects 2 or 3 arguments: the first argument is a decoded string, the second the available width and the
third and optional argument tells how to justify the string.

If the length of the string is greater than the available width it is truncated to the available width. If the string is
equal the available width nothing is done with the string. If the string length is less than the available width,
C<unicode_sprintf> adds spaces to the string until the string length is equal to the available width. If the third argument
is set to a true value, the spaces are added at the beginning of the string else they are added at the end of the string.
"Length" or "width" means here number of print columns as returned by the C<columns> method from  L<Unicode::GCString>.

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
