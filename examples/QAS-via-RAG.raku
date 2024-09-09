#!/usr/bin/env raku
use v6.d;

use lib <. lib>;

use Data::Importers;
use LLM::Configurations;
use LLM::Functions;
use XDG::BaseDirectory :terms;

use LLM::RetrievalAugmentedGeneration;
use LLM::RetrievalAugmentedGeneration::VectorDatabase;

use Data::Reshapers;
use Data::Summarizers;
use Math::Nearest;
use Math::DistanceFunctions;

my $vdbObj = LLM::RetrievalAugmentedGeneration::VectorDatabase.new();

my $dirName = data-home.Str ~ '/raku/LLM/SemanticSearchIndex';
my $fileName = $dirName ~ '/No833-gemini.json';

say "Importing vector database...";

my $tstart = now;
$vdbObj.import($fileName);
my $tend = now;

say "...DONE; import time { $tend - $tstart } seconds.";


.say for |$vdbObj.text-chunks.pick(3);

.say for |$vdbObj.database.pick(3);

my $query = 'How the USA election system with its two parties is presented?';
#my $query = 'What is the state of string theory?';
my @vec = |llm-embedding($query, llm-evaluator => $vdbObj.llm-configuration).head;

say (:@vec);

#`[
say "Finder construction...";

$tstart = now;
my &finder = nearest(@labeledVectors, method => 'KDTree');
$tend = now;

say "...DONE. Construction time: {$tend - $tstart} seconds.";

$tstart = now;
my @res = &finder(@vec, 12, prop => <label>);
$tend = now;

say "Computation time: {$tend - $tstart} seconds.";

say (:@res);
]

my @dsScores =
        $vdbObj.database.map({ %(
            label => $_.key,
            distance => euclidean-distance($_.value, @vec),
            text => $vdbObj.text-chunks{$_.key}
        ) }).Array;

@dsScores .= sort({ $_<distance> });

say to-pretty-table(@dsScores.head(30), field-names => <distance label text>);

say "\n\n\n";

my $answer = llm-synthesize([
    'Come up with a narration answering this question:',
    $query,
    "using these discussion statements:",
    @dsScores.head(40).map(*<text>).join("\n")
]);

say (:$answer);





