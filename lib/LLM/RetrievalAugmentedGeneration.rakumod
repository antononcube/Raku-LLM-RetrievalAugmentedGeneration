use v6.d;

unit module LLM::RetrievalAugmentedGeneration;

use XDG::BaseDirectory :terms;
use LLM::Functions;
use LLM::RetrievalAugmentedGeneration::VectorDatabase;

our sub resources {
    %?RESOURCES
}

#| Default directory for vector databases export
my $dirnameXDG = data-home.Str ~ '/raku/LLM/SemanticSearchIndex';

#===========================================================
# Create semantic search index
#===========================================================
#| Create semantic search index for a given source.
our proto sub create-semantic-search-index($source, |) is export {*}

multi sub create-semantic-search-index($source, *%args) {

    my $name = %args<name> // '';
    my $id = %args<id> // Whatever;

    my $vdbObj = LLM::RetrievalAugmentedGeneration::VectorDatabase.new(:$name, :$id);

    return $vdbObj.create-semantic-search-index($source, |%args);
}

#===========================================================
# Vector database search
#===========================================================
#| Find the nearest neighbor vectors for a given database and query.
#| C<$obj> Vector database.
#| C<$query> A vector compatible with the database or a string.
#| C<$spec> Number of nearest neighbors or C<(count, radius)> spec.
our proto sub vector-database-search(LLM::RetrievalAugmentedGeneration::VectorDatabase $obj, $query) is export {*}

multi sub vector-database-search(LLM::RetrievalAugmentedGeneration::VectorDatabase $obj, $query, $spec, *%args) {
    return $obj.nearest($query, $spec, |%args);
}

#===========================================================
# Vector databases
#===========================================================
# Importing of the whole vector database can be slow (3-5 seconds for database with ≈500 vectors.)
# Hence, we just slurp the text file an extract gist-data from it.
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

#| Gives file names or gists of available vector databases.
#| C<$dirname> Directory to search in.
#| C<:$pattern> String or regex to filter the filenames with.
#| C<:$format> Format of the results. One of file, filename, gist, summary, or Whatever.
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
            when $_ eq 'gist' {
                return extract-vb-summaries(@files).map({
                    # This should be consistent with VectorDatabase::gist
                    'VectorDatabase' ~ (<id name elements sources> Z=> $_<id name item-count document-count>).List.raku;
                })
            }
            when $_ ∈ <summary map hash gist-map gist-hash> {
                return extract-vb-summaries(@files)
            }
            default {
                note 'Unknown format for the result; known formats are "file", "file-name", and "gist".';
                return @files
            }
        }
    }
}


#===========================================================
# Join
#===========================================================
proto sub vector-database-join(|) is export {*}

multi sub vector-database-join(+@objs where @objs.all ~~ LLM::RetrievalAugmentedGeneration::VectorDatabase:D,
                               :$name is copy = Whatever,
                               Bool :$strict-check = False) {
    if $name.isa(Whatever) {
        $name = @objs.map(*.name).join('-AND-');
    }

    die 'The argument $name is expected to be a string or Whatever.'
    unless $name ~~ Str:D;

    my $res = LLM::RetrievalAugmentedGeneration::VectorDatabase.new(:$name);
    for @objs -> $obj {
        $res.join($obj, :$strict-check);
    }

    return $res
}

multi sub vector-database-join(*@objs, *%args) {
    note 'The positional arguments are expected to be vector database objects.' ~
            ' The named argument are $name is expected to be string or Whatever.' ~
            ' The named argument $strict-check is expected to be Boolean.';
}
