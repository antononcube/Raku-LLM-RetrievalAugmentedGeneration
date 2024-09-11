#!/usr/bin/env raku
use v6.d;

use lib <. lib>;

use Data::Importers;
use LLM::Functions;
use XDG::BaseDirectory :terms;

use LLM::RetrievalAugmentedGeneration;
use LLM::RetrievalAugmentedGeneration::VectorDatabase;

use Data::Reshapers;
use Data::Summarizers;
use Data::TypeSystem;
use Math::DistanceFunctions::Native;

my $vdbObj = LLM::RetrievalAugmentedGeneration::VectorDatabase.new();

say "Known vector databases:";
say vector-database-objects».basename;

my $dirName = data-home.Str ~ '/raku/LLM/SemanticSearchIndex';
my $fileName = $dirName ~ '/SemSe-266b20ca-d917-4ac0-9b0a-7c420625666c.json';
#my $fileName = $dirName ~ '/SemSe-d2effebc-2cef-4b2b-84ca-5dcfa3c1864b.json';

say "Importing vector database...";

my $tstart = now;
$vdbObj.import($fileName);
my $tend = now;

say "...DONE; import time { $tend - $tstart } seconds.";

say $vdbObj;

.say for |$vdbObj.text-chunks.pick(3);

.say for |$vdbObj.database.pick(3);

my $query = 'What is the state of string theory?';

say 'deduce-type($vdbObj.database) : ', deduce-type($vdbObj.database);

$tstart = now;

# This won't work because by default the vector database elements are converted to CArray's:
# my @res = $vdbObj.nearest($query, 30, prop => <label distance>, method => 'Scan', distance-function => { 1.0 - sum($^a <<*>> $^b) });

my @res = $vdbObj.nearest($query, 30, prop => <label distance>, method => 'Scan', distance-function => &euclidean-distance);

$tend = now;
say "Time to find nearest neighbors {$tend - $tstart} seconds.";

my @dsScores = @res.map({
    %( label => $_[0], distance => $_[1], text => $vdbObj.text-chunks{$_[0]} )
});

say to-pretty-table(@dsScores, field-names => <distance label text>, align => 'l');

say "\n\n\n";

#`[
my $answer = llm-synthesize([
    'Come up with a narration answering this question:',
    $query,
    "using these discussion statements:",
    @dsScores.head(40).map(*<text>).join("\n")
]);

say (:$answer);
]




