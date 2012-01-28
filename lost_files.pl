#!/usr/bin/env perl
#===============================================================================
#
#         FILE: lost_files.pl
#
#        USAGE: ./lost_files.pl
#
#  DESCRIPTION: The program searches the lost files that do not belong to any package.
#
#      OPTIONS: [-i input_file] [-o output_file] [-d|--no-dir] [-t|--time] [-s|--statistics] [-h|--help]
# REQUIREMENTS: perl-list-moreutils (List::MoreUtils), perl-io-interactive (IO::Interactive)
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Piotr Rogoża (piecia), rogoza dot piotr at gmail dot com
#      COMPANY: dracoRP
#      VERSION: 1.0
#      CREATED: 19.01.2012 09:52:17
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use Carp;

use File::Find;
use English qw( -no_match_vars );
use List::MoreUtils qw(any apply);
use Time::HiRes qw(time);
use Getopt::Long;
use IO::Interactive qw(is_interactive);
use utf8;
binmode STDOUT, ':encoding(UTF-8)';

my $AUTHOR  = 'Piotr Rogoża';
my $NAME    = 'lost_files';
use version; our $VERSION = qv(0.1);

#-------------------------------------------------------------------------------
#  Configuration
#-------------------------------------------------------------------------------

#{{{ Search in directories, one per line
my @search_dirs = qw(
    /bin
    /boot
    /lib
    /opt
    /sbin
    /srv
    /usr
    /var
);

#}}}

#{{{ Exclude directories, one per line
my @exclude_dirs = qw(
    /boot
    /var/abs
    /var/cache
    /var/lock
    /var/log
    /var/run
    /var/tmp
    /var/yaourt
    /lib/modules
    /var/spool
    /var/lib
    /var/state
    /usr/share/mime
);

#}}}

#{{{ Extension with/without dot, one per line
my @exclude_exts = qw(
    keep
    pacsave
    pacnew
    pyc
    pyo
    keep
    db
    cache
    scale
    dir
);

#}}}

#{{{ Exclude files, full path of file name, one per line
my @exclude_files = qw(
    /usr/share/info/dir
    /sbin/mount.truecrypt
    /opt/kde/lib/kde3/plugins/styles/qtcurve.so
    /usr/lib/locale/locale-archive
    /usr/share/glib-2.0/schemas/gschemas.compiled
    /usr/share/vim/vimfiles/doc/tags
    /usr/share/vim/doc/tags
    /usr/share/vim/vim73/doc/tags-pl
);

#}}}

#-------------------------------------------------------------------------------
#  Other configuration
#  Edit if you know what you are doing
#-------------------------------------------------------------------------------
#{{{
my (%option);
Getopt::Long::Configure('bundling');
GetOptions(
    'd|no-dir'      =>  \$option{no_directory},
    'o=s'           =>  \$option{output_file},
    'i=s'           =>  \$option{input_file},
    't|time'        =>  \$option{measure_time},
    's|statistics'  =>  sub { $option{measure_time} = 1; $option{statistics} = 1; },
    'h|help'        =>  \&_help,
);

# List files of package, empty for all(Archlinux)
$option{package} = q{};

# for debian, not tested
#options{package} = `dpkg -l | awk '/^[a-z][a-z]\ / {print $2}' 2>/dev/null| tr '\n' ' '`;

# Program to list all files of the package, and options for it
# for Archlinux
$option{program_option} = q{};
$option{program} = "pacman -Qlq $option{package} $option{program_option}";

# for Debian
#$option{program_option} = q{| fgrep -v '/.'};  # skip line with /.
#$option{program} = "dpkg -L $option{package} $option{program_option}";

# Global variables
my ($list_all_files, $exclude_dirs, $exclude_files, $exclude_exts);

# dla pomiaru czasu
my ($time_start, $time_stop, $time_measure);

# dla statystyk
my ($number_unmatched_files, $number_all_founded_files) = (0,0);

#}}}

#-------------------------------------------------------------------------------
#  Subroutines
#-------------------------------------------------------------------------------
sub _help { #{{{
    print <<"HELP";
Usage: $NAME [-i input_file] [-o output_file] [-d|--no-dir] [-t|--time] [-h|--help] [-s|--statistics]

    -i input file or use $NAME < input_file or cat input_file | $NAME: 
        list of all files belongs to packages

    -o output file or use $NAME > output_file
    
    -d|--no-dir
        check only files, this options can slow down your search
    
    -t|--time
        show search time
    
    -s|--statistics
        show statistics and search time
    
    -h|--help 
        show this help

At now you must edit this script to modify 'search directories', 'exclude directories', 'exclude extensions' and 'exclude files'.
HELP
    exit;
} ## --- end of sub _help }}}

sub _check_conf { ##{{{
    # Check does directories exist?
    @search_dirs =  apply {s/\/\z//xms} map { -d $_ ? ($_) : () } @search_dirs;
    if ( @search_dirs == 0 ){
        print {*STDERR} "List of searched directories is empty\n";
        exit 1;
    }
    @exclude_dirs =  apply {s/\/\z//xms} map { -d $_ ? ($_) : () } @exclude_dirs;

    # Remove a dot from beginning of extension
    @exclude_exts = apply {s/\A[.]//xms} @exclude_exts;

    # Check does files exist?
    @exclude_files = map { -f $_ ? ($_) : () } @exclude_files;

    return;
} ## --- end of sub _check_conf }}}

sub _get_all_files { ##{{{
    my ($fh, @list_all_files, $file_name);
    if ( $option{input_file} ){
        open $fh, q{<}, "$option{input_file}"
            or croak qq{Can't open the file $option{input_file}: $ERRNO};
    }
    elsif ( !is_interactive ){
        $fh = *STDIN;
    }
    else {
        open $fh, q{-|}, "$option{program}"
            or croak qq{Can't execute program($option{program}): $ERRNO};
    }
    @list_all_files = <$fh>;
    @list_all_files = apply {s/\/?\n\z//xms} @list_all_files;
    if ( $option{input_file} ){
        close $fh or croak qq{Can't close the file $option{input_file}: $ERRNO};
    }
    elsif ( !is_interactive ){
        close $fh or croak qq{Can't close STDIN: $ERRNO};
    }
    else{
        close $fh or croak qq{Can't close program($option{program}): $ERRNO};
    }

    # zwróc tablicę albo łańcuch z 'nową linią' jako separatorem
    return wantarray ? @list_all_files : join "\n", @list_all_files;
} ## --- end of sub _get_all_files }}}

sub _check_founded_file { #{{{ for File::Find
    my $dir_name    = $File::Find::dir;
    my $file_name   = $File::Find::name;
    my $curr_file   = $_;

    # tworzymy wzorzec do wyszukiwania dla aktualnego katalogu
    # \Q \E umożliwia wystapienie znakow specjalnych w nazwach plików

    # sprawdzam czy aktualny katalog jest na liście wykluczonych, jeśli tak to wyjdź z niego i zakończ przetwarzanie dla niego
    if ( $exclude_dirs && $exclude_dirs =~ m{^\Q$dir_name\E$}xms ){
        $File::Find::prune = 1;
        return;
    }

    # sprawdzamy czy przetwarzany plik w aktualnym katalogu to '.', czyli aktualny katalog
    if ( $curr_file eq q{.} ){
        return;
    }

    # sprawdź czy rozszerznie pliku nie znajduje się na liście wykluczonych ze sprawdzania
    if ($exclude_exts){
        my ($file_ext) = $file_name =~ m{
            \A                                  # początek łańcucha
            .*                                  # ścieżka
            [.]                                 # kropka
            ([^.]*)                             # rozszeżenie
        }xms;
        if ($file_ext){

            # zakotwiczam wzorzec do początku i końca łańcucha, $^ nie uwzględnia nowej linii
            if ( $exclude_exts =~ m{^\Q$file_ext\E$}xms ){
                $number_all_founded_files++;
                return;
            }
        }
    }

    # sprawdzamy czy aktualnie przetwarzany plik jest plikiem i czy nie jest na liście pliów do wykluczenia
    if ( $exclude_files && -f $file_name && $exclude_files =~ m{^\Q$file_name\E$}xms ){
        $number_all_founded_files++;
        return;
    }

    # sprawdź czy plik nie znajduje się na liście plików/katalogów pakietów zainstalowanych w systemie
    if ( $list_all_files !~ m{^\Q$file_name\E$}xms ){
        if ( !$option{no_directory} ){
            $number_unmatched_files++;
            print "$file_name\n";
        }
        elsif ( !-d $file_name ){
            $number_unmatched_files++;
            print "$file_name\n";
        }
    }
    $number_all_founded_files++;
    return;
} ## --- end of sub _check_founded_file }}}

#-------------------------------------------------------------------------------
#  Main program
#-------------------------------------------------------------------------------
if ( $EUID != 0 ){
    print {*STDERR} qq{You must run this script as root.\n};
    exit 1;
}
_check_conf;

$list_all_files = _get_all_files;
if ( !$list_all_files ){
    print {*STDERR} "The list of files is empty. I'm quit.\n";
    exit 1;
}

# change array into scalar, faster search
$exclude_dirs   = join "\n", @exclude_dirs;
$exclude_files  = join "\n", @exclude_files;
$exclude_exts   = join "\n", @exclude_exts;

# Find lost files
if ( $option{measure_time} ){
    $time_start = time;
}
if ( $option{output_file} ){
    open  STDOUT, q{>}, $option{output_file}
        or croak "Can't open file $option{outputfile} for write: $ERRNO\n";
}
find(\&_check_founded_file, @search_dirs);
if ( $option{outputfile} ){
    close STDOUT or croak "Can't file $option{outputfile}: $ERRNO\n";
}
if ( $option{measure_time} ){
    $time_stop = time;
    $time_measure = $time_stop - $time_start;
    print {*STDERR} "Time to search the system: $time_measure\n";
}
if ( $option{statistics} ){
    print {*STDERR} 'Number of input(model) files: ', scalar split("\n",$list_all_files), "\n";
    print {*STDERR}
        "Number of all found files: $number_all_founded_files, number of unmatched files: $number_unmatched_files\n";
}
