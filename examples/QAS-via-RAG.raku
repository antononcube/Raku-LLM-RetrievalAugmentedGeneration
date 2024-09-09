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
use Data::TypeSystem;
use Math::Nearest;
use Math::DistanceFunctions;

my $vdbObj = LLM::RetrievalAugmentedGeneration::VectorDatabase.new();

say vector-database-objects».basename;

my $dirName = data-home.Str ~ '/raku/LLM/SemanticSearchIndex';
my $fileName = $dirName ~ '/SemSe-No833.json';

say "Importing vector database...";

my $tstart = now;
$vdbObj.import($fileName);
my $tend = now;

say "...DONE; import time { $tend - $tstart } seconds.";

say $vdbObj;

.say for |$vdbObj.text-chunks.pick(3);

.say for |$vdbObj.database.pick(3);

my $query = 'What is the state of string theory?';
my @vec = |llm-embedding($query, llm-evaluator => $vdbObj.llm-configuration).head;

@vec .= deepmap(*.Num);

say (:@vec);
say 'deduce-type(@vec) : ', deduce-type(@vec);

say 'deduce-type($vdbObj.database) : ', deduce-type($vdbObj.database);

$tstart = now;
my @res = $vdbObj.nearest($query, 30, prop => <label distance>, method => 'Scan', distance-function => -> @x, @y { 1 - sum(@x >>*<< @y)});
$tend = now;
say "Time to find nearest neighbors {$tend - $tstart} seconds.";

my @dsScores = @res.map({
    %( label => $_[0], distance => $_[1], text => $vdbObj.text-chunks{$_[0]} )
});

say to-pretty-table(@dsScores, field-names => <distance label text>);

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




