#!/usr/bin/env raku
use v6.d;

use lib <. lib>;

use Data::Importers;
use LLM::Functions;

use LLM::RetrievalAugmentedGeneration;
use LLM::RetrievalAugmentedGeneration::VectorDatabase;

my $txtEN = data-import($*HOME ~ "/MathFiles/LLMs/833.txt");

say 'text-stats($txtEN): ', text-stats($txtEN);

my @chunks = $txtEN.split(/\n '[' [\d ** 2]+ % ':' ']' \n/):g;

say "Number of chunks {@chunks.elems}.";

say "Sample of chunks:";
for @chunks.keys.pick(6) -> $k {
    say "$k : {@chunks[$k]}";
}

@chunks = @chunks.pick(10);

my $vdbObj = LLM::RetrievalAugmentedGeneration::VectorDatabase.new(name => 'No833');

#my $llm-evaluator = llm-configuration("ChatGPT", model => 'text-embedding-002');
my $llm-evaluator = llm-configuration("Gemini");

my $tstart = now;
$vdbObj.create-semantic-search-index(@chunks, method => 'by-max-tokens', max-tokens => 2048, :$llm-evaluator, :export, :embed);
my $tend = now;
say "Time to make the semantic search index: {$tend - $tstart} seconds.";

say "Text chunks:";
.say for $vdbObj.items.pairs.pick(6).sort(*.key);

say "Vectors count: {$vdbObj.vectors.elems}";

say "Exporting vector database...";

$tstart = now;
$vdbObj.export();
$tend = now;

say "...DONE; export time {$tend - $tstart} seconds.";

say "Export file location : {$vdbObj.location}";

#note (:$vdbObj);
