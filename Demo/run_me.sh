#!/bin/bash
n=500
echo 'Running neworder.pl'
echo "Will first generate $n data sets with permuted character ordering,"
echo 'then run them in PAUP*, and finally plot a summary using R.'
echo 'The red arrows in the graphs (see file results.pdf) represents'
echo 'the unpermuted (original) data.'
../src/neworder.pl -r=$n --paup --write-R --outfile=utfil --VERBOSE ../data/data.nex
R --vanilla < source_me_in.R
mv utfil.scores.pdf result.pdf
rm utfil utfil.log utfil.scores source_me_in.R
