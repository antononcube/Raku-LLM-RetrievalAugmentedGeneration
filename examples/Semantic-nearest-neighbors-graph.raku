#!/usr/bin/env raku
use v6.d;

use LLM::RetrievalAugmentedGeneration;
use Math::DistanceFunctions::Native;

## Small graph
# Here is a set of words:
my @content = <apple ardvark bible car cat cherry chocolate cookie cow devil film horse house movie projector raccoon tiger tree>;

# Here we specify LLM-access configuration:
my $conf = llm-configuration('Gemini');
say $conf.Hash.elems;

# Here we create semantic search index:
my $vdbObjSmall = create-semantic-search-index(@content, e => $conf, name => 'words');

# Here we see the dimensions of the obtained vectors:
say $vdbObjSmall.vectors».elems;

# Here we find the embedding of a certain word (using the same LLM model as above):
my $vec = llm-embedding("coffee", e => $conf).head;
say $vec.elems;

# Here we find the closest Nearest Neighbors (NNs) of that word:
my @nns = $vdbObjSmall.nearest($vec, 3, prop => 'label' ).map(*.Slip);

# Here are the corresponding words:
say $vdbObjSmall.items{@nns};

# Here we find the edges of the corresponding NNs graph:
my @edges =
nearest-neighbor-graph(
    $vdbObjSmall.vectors.pairs,
    1,
    method => 'Scan',
    distance-function => &euclidean-distance,
    format => 'dataset'
);

@edges .= map({ $_<distance> = euclidean-distance($vdbObjSmall.vectors{$_<from>}, $vdbObjSmall.vectors{$_<to>}); $_ });
@edges .= map({ $_<weight> = 1 - $_<distance>; $_ });
@edges = @edges.map({ $_<from> = $vdbObjSmall.items{$_<from>}; $_<to> = $vdbObjSmall.items{$_<to>}; $_ });

records-summary(@edges);