use 5.010001;
use warnings;
use strict;
use File::Find;
use Test::More;
use Perl::PrereqScanner;


my %prereqs_make;
open my $fh_m, '<', 'Makefile.PL' or die $!;
while ( my $line = <$fh_m> ) {
    if ( $line =~ /^\s*'([^']+)'\s+=>\s+(?:'(?:[<>=]{2}\s?)?\d\.\d\d\d(?:_\d\d)?'|0),/ ) {
        $prereqs_make{$1} = $1;
    }

}
close $fh_m or die $!;


my @files;
for my $dir ( 'lib', 't' ) {
    find( {
        wanted => sub {
            my $file = $File::Find::name;
            return if ! -f $file;
            push @files, $file;
        },
        no_chdir => 1,
    }, $dir );
}
my %modules;
for my $file ( @files ) {
    my $scanner = Perl::PrereqScanner->new;
    my $prereqs = $scanner->scan_file( $file );
    for my $module ( keys %{$prereqs->{requirements}} ) {
        next if $module eq 'perl';
        $modules{$module} = $module;
    }
}

my %all_keys = ( %modules, %prereqs_make );

for my $module ( sort keys %all_keys ) {
    is( $prereqs_make{$module}, $modules{$module}, ( $prereqs_make{$module} // 'make_undef' ) . ' : ' .  ( $modules{$module} // 'module_undef' ) );
}

cmp_ok( keys %modules, '==', keys %prereqs_make, 'keys %modules == keys %prereqs_make' );

done_testing();
