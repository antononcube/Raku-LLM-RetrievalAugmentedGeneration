use v6.d;

unit module LLM::RetrievalAugmentedGeneration;

use XDG::BaseDirectory :terms;
use LLM::Functions;
use LLM::RetrievalAugmentedGeneration::VectorDatabase;


#===========================================================
# Create semantic search index
#===========================================================
our proto sub create-semantic-search-index($content, |) is export {*}

multi sub create-semantic-search-index($content, |) {
    my $dirName = data-home.Str ~ '/raku/Data/ExampleDatasets';
}



#===========================================================
#
#===========================================================
our proto sub find-nearest(LLM::RetrievalAugmentedGeneration::VectorDatabase $obj) {
    #
}


#===========================================================
# Create semantic search index
#===========================================================
