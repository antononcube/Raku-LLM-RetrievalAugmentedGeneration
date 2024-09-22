use v6.d;

unit module LLM::RetrievalAugmentedGeneration;

use XDG::BaseDirectory :terms;
use LLM::Functions;
use LLM::RetrievalAugmentedGeneration::VectorDatabase;
use JSON::Fast;

our sub resources {
    %?RESOURCES
}

#===========================================================
# Database location
#===========================================================

#| Default directory for vector databases export
my $dirnameXDG = data-home.Str ~ '/raku/LLM/SemanticSearchIndex';
my $defaultLocation = $dirnameXDG;

#| Default location
our proto sub default-location() {*}

multi sub default-location() {
    return $defaultLocation;
}

multi sub default-location($dirname) {
    given $dirname {
        when Whatever {
            $defaultLocation = $dirnameXDG;
        }
        when $_.IO.d {
            $defaultLocation = $dirname;
        }
        default {
            die "If an argument is given then that argument is expected to be a directory or Whatever."
        }
    }
    return $defaultLocation;
}

sub get-source-file($source) {
    given $source {
        when $_ ~~ IO::Path:D && $_.f {  return $_; }
        when $_ ~~ Str:D && $_.IO.f { return $_.IO; }
        when Str:D {
            # from basename
            for <cbor json> -> $ext {
                my $file = IO::Path.new(dirname => default-location, basename => $source ~ '.' ~ $ext);
                return $file if $file.f;

                $file = IO::Path.new(dirname => default-location, basename => 'SemSe-' ~ $source ~ '.' ~ $ext);
                return $file if $file.f;
            }
        }
    }
    return Nil;
}

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
# Vector database import
#===========================================================
#| Creates a vector database. If a given location spec is given imports location's database.
#| C<:file(:$location)> Location of the vector database.
#| C<%args> Creation options.
our proto sub create-vector-database(*%args) is export {*}

multi sub create-vector-database(*%args) {
    my $location = %args<generated-asset-location> // %args<location> // %args<file> // False;
    if $location {
        my %args2 = %args.grep({ $_.key ∉ <generated-asset-location location file> });
        my $vdbObj = LLM::RetrievalAugmentedGeneration::VectorDatabase.new(|%args2);
        my $location2 = get-source-file($location);
        return $vdbObj.import($location2 // $location, keep-id => %args<id>:exists);
    }
    return LLM::RetrievalAugmentedGeneration::VectorDatabase.new(|%args);
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
sub extract-vb-summaries(@files, Bool:D :$flat = False) {
    my %vbTexts = @files.map({ $_.Str => $_.slurp });

    my @res = %vbTexts.map({

        my $llm-configuration = (with $_.value.match(/ '"llm-configuration"' \s* ':' \s* ('{' <-[}]>+ '}') /) { $0
                .Str });
        if $llm-configuration { $llm-configuration = from-json($llm-configuration.trim) }
        my $conf-name = (with $_.value.match(/ '"llm-configuration"' .*? '"name"' \s* ':' \s* \" (<-["]>+) \" /) { $0
                .Str });
        my @all-names = (with $_.value.match(:g, / '"name"' \s* ':' \s* \" $<name>=(<-["]>+) \" /) { $/.values
                .map(*<name>.Str) });
        my $name = (@all-names (-) $conf-name).keys.head;
        my $dimension = (with $_.value.match(/ '"vectors"' \s* ':' \s* '{' \s* <-[[]>+ '[' (<-[\]]>+) ']' /) { $0.Str
                .split(',', :skip-empty).elems });

        my %res =
                :$name,
                file => $_.key.IO,
                item-count => (with $_.value.match(/'"item-count"' \h* ':' \h* (\d+) /) { $0.Str } else { 0 }),
                document-count => (with $_.value.match(/'"document-count"' \h* ':' \h* (\d+) /) { $0.Str } else { 0 }),
                id => (with $_.value.match(/'"id"' \h* ':' \h* \" (.+?) \" /) { $0.Str } else { '' }),
                version => (with $_.value.match(/'"version"' \h* ':' \h* (\d+?) /) { $0.Str } else { 0 }),
                :$dimension,
                :$llm-configuration;

        if $flat {
            %res<llm-configuration>:delete;
            %res<llm-service> = $conf-name;
            %res<llm-embedding-model> = $llm-configuration<embedding-model> // '(Any)';
        }

        %res
    });

    return @res;
}

#| Gives file names or gists of available vector databases.
#| C<$dirname> Directory to search in.
#| C<:$pattern> String or regex to filter the filenames with.
#| C<:$format> Format of the results. One of file, filename, gist, summary, or Whatever.
#| C<:$flat> Whether the map-summaries be flat or nested.
sub vector-database-objects($dirname is copy = Whatever,
                            :$pattern = '',
                            :f(:form(:$format)) is copy = Whatever,
                            Bool:D :$flat = False
                            ) is export {
    if $dirname.isa(Whatever) {
        $dirname = default-location()
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
                return extract-vb-summaries(@files, :$flat)
            }
            default {
                note 'Unknown format for the result; known formats are "file", "file-name", "gist", "gist-map".';
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
