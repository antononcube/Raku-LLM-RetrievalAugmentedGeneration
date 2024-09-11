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
sub extract-vb-summaries(@files) {
    my %vbTexts = @files.map({ $_.Str => $_.slurp });

    my @res = %vbTexts.map({

        my $conf-name = (with $_.value.match(/ '"llm-configuration"' .*? '"name"' \h* ':' \h* \" (<-["]>+) \" /) { $0.Str });
        my @all-names = (with $_.value.match(:g, / '"name"' \h* ':' \h* \" $<name>=(<-["]>+) \" /) { $/.values.map(*<name>.Str) });
        my $name = (@all-names (-) $conf-name).keys.head;

        %(
            :$name,
            file => $_.key.IO,
            item-count => (with $_.value.match(/'"item-count"' \h* ':' \h* (\d+) /) { $0.Str  } else {0}),
            document-count => (with $_.value.match(/'"document-count"' \h* ':' \h* (\d+) /) { $0.Str  } else {0}),
            id => (with $_.value.match(/'"id"' \h* ':' \h* \" (.+?) \" /) { $0.Str  } else {''}),
            version => (with $_.value.match(/'"version"' \h* ':' \h* (\d+?) /) { $0.Str  } else {0})
        ) });

    return @res;
}

sub vector-database-objects($dirname is copy = Whatever,
                            :$pattern = '',
                            :f(:form(:$format)) is copy = Whatever) is export {
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

        if $format.isa(Whatever) { $format = 'gist' }
        die 'The argument $format is expected to be a string or Whatever.'
        unless $format ~~ Str:D;

        given $format.lc {
            when $_ ∈ <file files> {
                return @files
            }
            when $_ ∈ <filename filenames file-name file-names> {
                return @files».Str
            }
            when $_ ∈ <summary map hash gist-map gist-hash> {
                return extract-vb-summaries(@files)
            }
            when $_ eq 'gist' {
                return extract-vb-summaries(@files).map({
                    # This should be consistent with VectorDatabase::gist
                    'VectorDatabase' ~ (<id name elements sources> Z=> $_<id name item-count document-count>).List.raku;
                })
            }
            default {
                note 'Unknown format for the result; known formats are "file", "file-name", and "gist".';
                return @files
            }
        }
    }
}