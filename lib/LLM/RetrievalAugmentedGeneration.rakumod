use v6.d;

unit module LLM::RetrievalAugmentedGeneration;

use XDG::BaseDirectory :terms;
use LLM::Functions;
use LLM::RetrievalAugmentedGeneration::VectorDatabase;

#| Default directory for vector databases export
my $dirnameXDG = data-home.Str ~ '/raku/LLM/SemanticSearchIndex';

#===========================================================
# Create semantic search index
#===========================================================
our proto sub create-semantic-search-index($content, |) is export {*}

multi sub create-semantic-search-index($content, *%args) {

    my $name = %args<name> // '';
    my $id = %args<id> // Whatever;

    my $vdbObj = LLM::RetrievalAugmentedGeneration::VectorDatabase.new(:$name, :$id);

    return $vdbObj.create-semantic-search-index($content, |%args);
}

#===========================================================
# Vector database search
#===========================================================
our proto sub vector-database-search(LLM::RetrievalAugmentedGeneration::VectorDatabase $obj, $query) is export {*}

multi sub vector-database-search(LLM::RetrievalAugmentedGeneration::VectorDatabase $obj, $query, $spec, *%args) {
    return $obj.nearest($query, $spec, |%args);
}

#===========================================================
# Vector databases
#===========================================================
sub vector-database-objects($dirname is copy = Whatever, :$pattern = '') is export {
    if $dirname.isa(Whatever) {
        $dirname = $dirnameXDG
    }
    if !$dirname.IO.d {
        note "Not a directory: ⎡$dirname⎦." unless $dirname eq $dirnameXDG;
        return Empty;
    } else {
        my @files = $dirname.IO.dir.grep(*.IO.f);
        @files = do given $pattern {
            when ($_ ~~ Str:D) && $_.chars > 0 {
                @files.grep({ $_.Str.contains($pattern) });
            }
            when $_ ~~ Regex:D {
                @files.grep({ $_.Str ~~ $pattern });
            }
            default {
                @files.grep({ $_.Str.ends-with('.json') })
            }
        }
        return @files;
    }
}