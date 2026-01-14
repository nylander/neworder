#!/usr/bin/env perl
#===============================================================================
#
#  USAGE: neworder.pl --reps=100 data.nex
#
#  HELP:  Use 'neworder.pl --man' for more options and information
#
#===============================================================================

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use List::Util qw(shuffle);

Getopt::Long::Configure("no_ignore_case");

## Globals
my $SCRIPTNAME       = $0;
my $CHANGES          = '04/18/2007 01:15:28 AM CEST';
my $VERSION          = '0.1.0';
my $VERBOSE          = q{};
my $DEBUG            = 0;    # Set to 1 for debug printing
my $outfile          = q{};
my $paup             = q{};
my $nopaup           = q{};
my $paup_bin         = 'paup';
my $use_paup         = 0;
my $file_end         = '.paup.bat';
my $reps             = "100";
my $write_R          = 0;

my @ctype_numbers    = ();
my @paup_block       = ();
my @header           = ();
my %referenced_hash  = ();
my %charstate_hash   = ();
my %HoH              = ();
my $file             = q{};
my $nchar            = q{};


## Handle arguments
if (@ARGV < 1) {
    print "\n Try '$SCRIPTNAME --man' for more info\n\n";
    exit(0);
}
else {
    GetOptions(
        'help'      => sub { pod2usage(1); },
        'version'   => sub { print STDOUT "\n  $SCRIPTNAME version $VERSION\n  Last changes $CHANGES\n\n"; exit(0) },
        'man'       => sub { pod2usage(-exitstatus => 0, -verbose => 2); },
        'paup'      => \$paup,
        'nopaup'    => \$nopaup,
        'reps:i'    => \$reps,
        'write-R'   => \$write_R,
        'outfile:s' => \$outfile,
        'VERBOSE!'  => \$VERBOSE,
        'DEBUG'     => \$DEBUG
    );
}


## Check if paup can be found and if paup is going to be used
if ($paup) {
    $paup = find_paup($paup_bin);
    if (! $paup) {
        $use_paup = 0;
        $nopaup   = 1;
    }
    else {
        if ($nopaup) {
            $use_paup = 0;
        }
        else {
            $use_paup = 1;
        }
    }
}


## Read file name and get file content
$file = shift(@ARGV);
open my $FILE, '<', $file
    or die "$0 : failed to open input file $file : $!\n";
my @file_content = <$FILE>;
close $FILE
    or warn "$0 : failed to close input file $file : $!\n";


## Read matrix from file content
my $referenced_hash = read_matrix(\@file_content);
if ($DEBUG) {
    print STDERR "\nDEBUG:referenced_hash:\n";
    foreach my $taxon_label (sort(keys %$referenced_hash)) {
        print STDERR "$taxon_label => ";
        my (@sequence) = (@{$$referenced_hash{$taxon_label}});
        foreach my $s (@sequence) {
            print STDERR $s;
        }
        print STDERR "\n";
    }
}


## Get the Nexus header
@header = read_header(\@file_content);
if ($DEBUG) {
    print STDERR "\nDEBUG:header:\n@header\n";
}


## Get the paup block
@paup_block = read_paup_block(\@file_content);
if ($DEBUG) {
    print STDERR "\nDEBUG:paup_block:\n@paup_block\n";
}


## Get the ctype numbers
@ctype_numbers = read_ctype_numbers(\@paup_block);
if ($DEBUG) {
    print STDERR "\nDEBUG:ctype_numbers:\n@ctype_numbers\n";
}


## Traverse the hash and get the character states for the columns
for my $t (keys %$referenced_hash) {
    $nchar = @{$$referenced_hash{$t}}; # Get nchar
    last;
}
if ($DEBUG) {
    print STDERR "\nDEBUG:nchar:$nchar.\n";
}
for (my $i=0 ; $i < $nchar ; $i++) {
    foreach my $taxon_label (sort(keys %$referenced_hash)) {
        my $char_state = ${$$referenced_hash{$taxon_label}}[$i];
        push @{$charstate_hash{$i}}, $char_state;
    }
}
if ($DEBUG) {
    print STDERR "\nDEBUG:charstate_hash:\n";
    foreach my $ctype_nr (sort(keys %charstate_hash)) {
        my @char_state_array = @{$charstate_hash{$ctype_nr}};
        print STDERR "$ctype_nr => @char_state_array\n";
    }
    print STDERR "\n";
}


## Open outfile
if ($outfile eq "") {
    $outfile = $file . $file_end;
}
open my $OUTFILE, ">", $outfile
    or die "$0 : failed to open output file $outfile : $!\n";


## Print Nexus header
print $OUTFILE "#NEXUS\n";
print $OUTFILE "  Begin Paup;\n";
print $OUTFILE "  Log file=$outfile.log replace=yes start=yes\;\n";
print $OUTFILE "  Set increase=auto warnreset=no autoclose=yes\;\n";
print $OUTFILE "End\;\n\n";
print $OUTFILE "[!Original Data]\n";
print $OUTFILE "@header"; # header
print $OUTFILE "    ";


## Print matrices, start with the original
foreach my $taxon_label (sort(keys %$referenced_hash)) {
    print $OUTFILE "$taxon_label    "; # taxon label
    print $OUTFILE @{$$referenced_hash{$taxon_label}}; # sequence
    print $OUTFILE "\n    ";
}
print $OUTFILE "\;\nEnd;\n\n";
print $OUTFILE "@paup_block\n"; # paupblock
my (@block) = extended_paup_block($outfile); # Extended paupblock
print $OUTFILE @block;


## Then print the randomized data sets
for (my $n=0 ; $n < $reps ; $n++) {
    foreach my $ctype_nr (sort(keys %charstate_hash)) {
        my (@char_state_array) = get_unique(@{$charstate_hash{$ctype_nr}});
        my @rand_char_states = shuffle(@char_state_array);
        my $s = @rand_char_states;
        for (my $i=0 ; $i < $s ; $i++) {
            my $old = shift(@char_state_array);
            my $new = shift(@rand_char_states);
            $HoH{$ctype_nr}{$old} = $new; # get old and new states in to a hash of hashes
        }
    }
    if ($DEBUG) {
        print STDERR "\nDEBUG:HoH (old and new char states hash of hashes):\n";
        for my $ctype (sort(keys %HoH)) {
            print STDERR "==ctype_nr: $ctype:\n";
            for my $old (sort(keys %{$HoH{$ctype}})) {
                print STDERR " old:$old => ";
                my $new = $HoH{$ctype}->{$old};
                print STDERR "new:$new\n";
            }
            print STDERR "\n";
        }
    }
    print $OUTFILE "[! Data Nr.$n]\n";
    print $OUTFILE "@header";
    print $OUTFILE "    ";
    foreach my $taxon_label (sort(keys %$referenced_hash)) {
        print $OUTFILE "$taxon_label    ";
        my $i=0;
        foreach my $char_state (@{$$referenced_hash{$taxon_label}}) { # for each char in sequence
            my $char_is_in_ctype = is_char_in_ctype($i);
            if ($char_is_in_ctype) {
                my $new_char_state = get_new_char_state($i, $char_state);
                print $OUTFILE "$new_char_state";
                $i++;
            }
            else {
                print $OUTFILE "$char_state";
                $i++;
            }
        }
        print $OUTFILE "\n    ";
    }
    print $OUTFILE "\;\nEnd;\n\n";
    print $OUTFILE "@paup_block\n";
    print $OUTFILE @block; # Extended paupblock
}

print $OUTFILE "\nBegin Paup;\n  Log stop=yes\;\nQuit warntsave=no\;\nEnd;\n\n";
close $OUTFILE
    or warn "$0 : failed to close output file $outfile : $!\n";


## Run paup or not
if ($use_paup) {
    system "$paup $outfile";
}


## Print R file if paup was run
if ($write_R) {
    my $score_file_name = "$outfile.scores";
    read_scores_and_print_R($score_file_name);
}


## Done
print STDERR "\ndone\n" if $VERBOSE;


# end of main


#===  FUNCTION  ================================================================
#         NAME:  extended_paup_block
#      VERSION:  04/17/2007 10:56:48 PM CEST
#  DESCRIPTION:  Paup block
#   PARAMETERS:  $outfile, name of outfile
#      RETURNS:  @paup_block
#         TODO:  ????
#===============================================================================
sub extended_paup_block {

    my ($outfile) = @_;

    my @paup_block = qq{
    Begin Paup;
    Pscores 1 /TL=yes CI=yes RI=yes scorefile=$outfile.scores append=yes;
    [Savetrees file=$outfile.trees append=yes format=altnexus;]
    End;
    };

    return @paup_block;

} # end of extended_paup_block


#===  FUNCTION  ================================================================
#         NAME:  find_paup
#      VERSION:  04/11/2007 18:48:00 PM CET
#  DESCRIPTION:  Searches the PATH for the PAUP binary
#   PARAMETERS:  $paup_bin
#      RETURNS:  path to paup binary ($paup) or 0 if not found
#         TODO:  ????
#===============================================================================
sub find_paup {

    my ($paup_bin) = @_;
    my $paup = '';

    FIND_PAUP:
    foreach (split(/:/,$ENV{PATH})) {
        if (-x "$_/$paup_bin") {
            $paup = "$_/$paup_bin";
            last FIND_PAUP;
        }
    }
    if ($paup eq '') {
        print "\a\nWarning: Couldn't find executable '$paup_bin' (check your path).\n\n";
        $paup = 0;
    }

    return($paup);

} # end of find_paup


#===  FUNCTION  ================================================================
#         NAME:  fisher_yates_shuffle
#      VERSION:  04/12/2007 11:06:02 AM CEST
#  DESCRIPTION:  Shuffles an array. Taken from perldoc, with modifications.
#   PARAMATERS:  \@array, ref to array
#      RETURNS:  Void (shuffles array in place
#         TODO:  ????
#===============================================================================
sub fisher_yates_shuffle {

    my $array = shift;
    my $i;

    for ($i = @$array; --$i; ) {
        my $j = int rand ($i+1);
        next if $i == $j;
        @$array[$i,$j] = @$array[$j,$i];
    }

} # end of fisher_yates_shuffle


#===  FUNCTION  ================================================================
#         NAME:  get_new_char_state
#      VERSION:  04/16/2007 11:10:01 PM CEST
#  DESCRIPTION:  finds the new character state from the global HoH based on
#                position and old state. Also handles question marks, gaps and
#                multi-state characters
#   PARAMATERS:  $i, position in sequence, and $state, character state for position $i
#      RETURNS:  $new, new character state
#         TODO:  ????
#===============================================================================
sub get_new_char_state {

    my (@args) = @_;
    my $new    = q{};
    my @new    = ();
    my $i      = shift(@args);
    my $old    = shift(@args);

    if ($old =~ /^\{|^\(/) { # multistate taxa
        my @parts = split //, $old;
        foreach my $part (@parts) {
            if ($part =~ /\{|\}|\(|\)|\?|\-/) {
                $new = $new . $part;
            }
            else {
                my $n = $HoH{$i}->{$part};
                $new = $new . $n;
            }
        }
    }
    elsif ($old =~ /\?|\-/) { # questionmarks and gaps
        $new = $old;
    }
    else {
        $new = $HoH{$i}->{$old};
    }

    return ($new);

} # end of get_new_char_state


#===  FUNCTION  ================================================================
#         NAME:  get_seq
#      VERSION:  04/12/2007 11:06:08 AM CEST
#  DESCRIPTION:  Read sequence allowing for multitate characters
#   PARAMATERS:  $seq, string with sequence
#      RETURNS:  @seq, array with characters
#         TODO:  ????
#===============================================================================
sub get_seq {

    my (@l) = split //, shift(@_);
    my $m = "";
    my $u = "";
    my @s = ();
    my $foundm = 0;
    my $foundu = 0;

    foreach my $c (@l) {
        if($foundm) {
            if ($c eq '}') {
                $m = $m . $c;
                push @s, $m;
                $m = "";
                $foundm = 0;
            }
            else {
                $m = $m . $c;
            }
        }
        elsif($foundu) {
            if ($c eq ')') {
                $u = $u . $c;
                push @s, $u;
                $u = "";
                $foundu = 0;
            }
            else {
                $u = $u . $c;
            }
        }
        elsif ($c eq '{') {
            $foundm = 1;
            $m = $m . $c;
        }
        elsif ($c eq '(') {
            $foundu = 1;
            $u = $u . $c;
        }
        else {
            push @s, $c;
        }
    }

    return @s;

} # end of get_seq


#===  FUNCTION  ================================================================
#         NAME:  get_unique
#      VERSION:  04/15/2007 08:49:15 PM CEST
#  DESCRIPTION:  find the unique values in an array. From Perl Cook Book.
#   PARAMATERS:  @array
#      RETURNS:  @array
#         TODO:  ????
#===============================================================================
sub get_unique {

    my (@list) = @_;
    my @uniq   = ();
    my %seen   = ();

    foreach my $item (@list) {
        if ($item =~ /\{|\(/) { # multistate taxa
            my @parts = split //, $item;
            foreach my $part (@parts) {
                next if ($part =~ /\{|\}|\(|\)|\?|\-/);
                push(@uniq, $part) unless $seen{$part}++;
            }
        }
        elsif ($item =~ /\?|\-/) { # questionmarks and gaps
            next;
        }
        else {
            push(@uniq, $item) unless $seen{$item}++;
        }
    }

    return (@uniq);

} # end of get_unique


#===  FUNCTION  ================================================================
#         NAME:  is_char_in_ctype
#      VERSION:  04/16/2007 14:40:15 PM CEST
#  DESCRIPTION:  Searches global array @ctype_numbers for presence of $i.
#   PARAMATERS:  $i, character number
#      RETURNS:  1 if found, else 0
#         TODO:  ????
#===============================================================================
sub is_char_in_ctype {

    my $i  = shift;
    my $is = 0;

    foreach my $ctype (@ctype_numbers) {
        if ($i == $ctype - 1) {
            $is = 1;
        }
    }

    return $is;

} # end of is_char_in_ctype


#===  FUNCTION  ================================================================
#         NAME:  read_ctype_numbers
#      VERSION:  04/06/2007 01:45:18 PM CEST
#  DESCRIPTION:  read ctype numbers from file.
#                Assumes the Ctype command on a single line!
#                Does not handle ranges (e.g. '1-10')!
#   PARAMATERS:  \@paup_block, array ref to paup block
#      RETURNS:  @ctype_numbers
#         TODO:  Handle ranges
#===============================================================================
sub read_ctype_numbers {

    my ($array_ref)     = @_;
    my @ctype_numbers = ();
    my $ctype_string  = q{};

    foreach my $line (@$array_ref) {
        if ($line =~ /Ctype/i) {
            $ctype_string = $line;
            last;
        }
    }
    my (@pieces) = split /\s+/, $ctype_string;
    foreach (@pieces) {
        if (/\d+/) {
            $_ =~ s/;$//; # strip trailing ';'
            push @ctype_numbers, $_;
        }
    }

    return(@ctype_numbers);

} # end of read_ctype_numbers


#===  FUNCTION  ================================================================
#         NAME:  read_header
#      VERSION:  04/12/2007 11:56:22 PM CEST
#  DESCRIPTION:  read file content and get the Begin data block header
#   PARAMATERS:  \@file_content, reference to an array with file content
#      RETURNS:  @header, array
#         TODO:  ????
#===============================================================================
sub read_header {

    my ($array_ref)  = @_;
    my %hash         = ();
    my @header       = ();
    my $found_matrix = 0;

    foreach (@$array_ref) {
        s/#.*//; # ignore comments by erasing them
        last if (/^\s*END\s*\;/i);
        if (/Matrix/i) {
            push @header, $_;
            $found_matrix = 1;
        }
        elsif ($found_matrix == 0) {
            push @header, $_;
        }
    }

    return @header;

} # end of read_header


#===  FUNCTION  ================================================================
#         NAME:  read_matrix
#      VERSION:  tis 19 jul 2022 11:51:44 
#  DESCRIPTION:  Read file content and get the matrix.
#                Does not handle comments. The word 'matrix' should not appear
#                anywhere else than intended.
#   PARAMATERS:  \@file_content, reference to an array with file content
#      RETURNS:  \%hash, reference to anonymoushash with key=$name, value=@characters
#         TODO:  ????
#===============================================================================
sub read_matrix {

    my ($array_ref)  = @_;
    my %hash         = ();
    my $found_matrix = 0;

    # Read matrix
    foreach (@$array_ref) {
        last if (/^\s*END\s*\;/i);
        if (/Matrix/i) {
            $found_matrix = 1;
        }
        elsif ($found_matrix == 0) {
            next;
        }
        elsif (/^\s*(\S+)\s+(\S+)\s*$/) { # line has two words
            my $name = $1;
            my $seq = $2;
            if (!$name or !$seq) {
                die "\nCould not read taxon name and/or sequence from $file.\n\n";
            }
            @{$hash{$name}} = get_seq($seq); # get the sequence into an array stored in hash
        }
    }

    return \%hash;

} # end of read_matrix


#===  FUNCTION  ================================================================
#         NAME:  read_paup_block
#      VERSION:  04/11/2007 18:40:38 PM CEST
#  DESCRIPTION:  reads the paupblock
#   PARAMATERS:  \@file_content, ref to file content
#      RETURNS:  @paup_block
#         TODO:  ????
#===============================================================================
sub read_paup_block {

    my ($array_ref)      = @_;
    my @paup_block       = ();
    my $found_begin_paup = 0;

    foreach (@$array_ref) {
        if ($found_begin_paup) {
            if (/^\s*END\s*\;/i) {
                push @paup_block, $_;
                last;
            }
            else {
                push @paup_block, $_;
            }
        }
        elsif (/\s*Begin\s+Paup\s*;/i) {
            push @paup_block, $_;
            $found_begin_paup = 1;
        }
        else {
            next;
        }
    }

    return(@paup_block);

} # end of read_paup_block


#===  FUNCTION  ================================================================
#         NAME:  read_scores_and_print_R
#      VERSION:  04/18/2007 12:40:44 AM CEST
#  DESCRIPTION:  Prints a R file. Can be run in R using:
#                R --no-save < source_me_in.R
#   PARAMATERS:  $score_file_name
#      RETURNS:  ????
#         TODO:  ????
#===============================================================================
sub read_scores_and_print_R {

    my (@args)          = @_;
    my $score_file_name = shift(@_);
    my $R_file_name     = "source_me_in.R";
    my (@first)         = ();
    my (@TL)            = ();
    my (@CI)            = ();
    my (@RI)            = ();
    my($first_tl, $first_ci, $first_ri);

    ## Read score file
    open my $SF, "<", $score_file_name
        or die "$0 : failed to open score file $score_file_name : $!\n";

    my $found_first = 0;
    while (<$SF>) {
        if (/^1/) {
            if ($found_first == 0) {
                (@first) = split /\s+/;
                shift(@first);
                $found_first = 1;
            }
            else {
                my ($one, $tl, $ci, $ri) = split /\s+/;
                push @TL, $tl;
                push @CI, $ci;
                push @RI, $ri;
            }
        }
    }
    close $SF
        or warn "$0 : failed to close score file $score_file_name : $!\n";

    ## Get values for original matrix
    ($first_tl, $first_ci, $first_ri) = @first;

    ## Open R file
    open my $RF, ">", $R_file_name
        or die "$0 : failed to open R file $R_file_name : $!\n";

    ## Print R file
    #print $RF "postscript(file = \"$score_file_name.ps\")\n";
    print $RF "pdf(file = \"$score_file_name.pdf\")\n";
    #par(mfcol = c(nr, nc)
    print $RF "par(mfcol = c(3, 1))\n";
    print $RF "par(xaxs = \"i\", yaxs = \"i\")\n\n";

    # TL list
    print $RF "TL <- c(\n ";
    my $i = 0;
    my $j = 0; # line length counter
    foreach my $d ( @TL ) {
        print $RF "$d";
        if ($i == $#TL) {
            print $RF ")\n";
        }
        elsif ($j == 10) {
            print $RF ",\n ";
            $j=0;
        }
        else {
            print $RF ", ";
        }
        $i++;
        $j++;
    }
    print $RF "\n";

    # CI list
    print $RF "CI <- c(\n ";
    $i = 0;
    $j = 0; # line length counter
    foreach my $d ( @CI ) {
        print $RF "$d";
        if ($i == $#CI) {
            print $RF ")\n";
        }
        elsif ($j == 10) {
            print $RF ",\n ";
            $j=0;
        }
        else {
            print $RF ", ";
        }
        $i++;
        $j++;
    }
    print $RF "\n";

    # RI list
    print $RF "RI <- c(\n ";
    $i = 0;
    $j = 0; # line length counter
    foreach my $d ( @RI ) {
        print $RF "$d";
        if ($i == $#RI) {
            print $RF ")\n";
        }
        elsif ($j == 10) {
            print $RF ",\n ";
            $j=0;
        }
        else {
            print $RF ", ";
        }
        $i++;
        $j++;
    }
    print $RF "\n";

    # Plot TL
    print $RF "hist(TL, breaks = 30, xlab = \"Tree Length\", main = \"\")\n\n";
    print $RF "arrows($first_tl, 20, $first_tl, 5, angle = 20, length = 0.1, col = \"red\")\n\n";

    # Plot CI
    print $RF "hist(CI, breaks = 30, xlim = c(min(c(CI,$first_ci))-0.01, max(c(CI,$first_ci))+0.01) , xlab = \"Consisteny Index\", main = \"\")\n\n";
    print $RF "arrows($first_ci, 20, $first_ci, 5, angle = 20, length = 0.1, col = \"red\")\n\n";

    # Plot RI
    print $RF "hist(RI, breaks = 30, xlim = c(min(c(RI,$first_ri))-0.01, max(c(RI,$first_ri))+0.01), xlab = \"Retention Index\", main = \"\")\n";
    print $RF "arrows($first_ri, 20, $first_ri, 5, angle = 20, length = 0.1, col = \"red\")\n\n";

    print $RF "dev.off()\n\n";

    close $RF
        or warn "$0 : failed to close R file $R_file_name : $!\n";

} # end of read_scores_and_print_R


#===  POD DOCUMENTATION  =======================================================
#      VERSION:  04/18/2007 12:38:39 AM CEST
#  DESCRIPTION:  Documentation
#         TODO:  ????
#===============================================================================

=pod

=head1 NAME

neworder.pl

=head1 VERSION

Documentation for neworder.pl version 0.1.0

=head1 SYNOPSIS

neworder.pl --reps=I<NUMBER> --[no]paup --write-R --outfile=B<OUTFILE> --[no]VERBOSE B<INFILE>

=head1 DESCRIPTION

Script for creating a I<NUMBER> of random permutations of character orderings in Nexus file B<INFILE>. If option I<--paup> is used, the script creates the files, and tries to run them using paup. When the option I<--nopaup> is used, the script doesn't run paup (obviously).

Note that I<Ctype> needs to be present in the Paup block and written on a single line. The script reads only a single Paup block (the first), and any specific search arguments should be specified in the block.

Example of readable Nexus format:

    #NEXUS
    Begin data;
    Dimensions ntax=3 nchar=4;
    Format missing=? gap=- datatype=DNA;
    Matrix
    Apa 00(01)0
    Bpa 1111
    Cpa 2212
    ;
    End;
    Begin Paup;
    Outgroup Apa;
    Ctype ord : 1 2 4;
    Hsearch addseq=rand reps=10;
    End;


=head1 OPTIONS

=over 8

=item B<-r, --reps=>I<NUMBER>

Write I<NUMBER> of permuted data sets to file. Default is 100.

=item B<-p, --paup>

Try to run the created file in paup. B<--nopaup> prevents this. Default is to not run paup.

=item B<-w, --write-R>

Read scores file and write R file. Paup needs to have been run on the oufile created by the script.

=item B<-o, --outfile=NAME>

Specify output file B<NAME>. If B<--outfile> is not used, a file starting with B<INFILE> and ending in B<.bat> will be created.

=item B<-V, --VERBOSE>

Be verbose. Can also be B<--noVERBOSE> (default).

=item B<-h, --help>

Prints help message and exits.

=item B<-v, --version>

Prints version message and exits.

=item B<-m, --man>

Displays the manual page.

=item B<INFILE>

Nexus formatted data B<INFILE>.

=back

=head1 USAGE

neworder.pl --reps=I<NUMBER> --[no]paup --write-R --outfile=B<OUTFILE> --[no]VERBOSE B<INFILE>

=head1 AUTHOR

Written by Johan A. A. Nylander

=head1 DEPENDENCIES

Optional: PAUP* (by D. L. Swofford) needs to be installed (as 'paup') in the PATH.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2007-2026 Johan Nylander

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

=cut

