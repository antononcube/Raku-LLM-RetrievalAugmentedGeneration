use v6.d;

use UUID;
use XDG::BaseDirectory :terms;
use JSON::Fast;

use LLM::Functions;

use Math::DistanceFunctions;
use Math::Nearest;

class LLM::RetrievalAugmentedGeneration::VectorDatabase {

    has Str:D $.name is rw = '';
    has $.id is rw = '';
    has $.distance-function is rw = WhateverCode;
    has $.item-count = 0;
    has $.document-count = 0;
    has %.database;
    has %.text-chunks;
    has %.tags;
    has $.tokenizer = WhateverCode;
    has UInt:D $.version = 0;
    has $.location = Whatever;
    has $.llm-configuration = Whatever;

    #======================================================
    # Creators
    #======================================================
    submethod BUILD(
            :$!name = '',
            :$!distance-function = WhateverCode,
            :%!database = %(),
            :$!tokenizer,
            :$!version = 0,
            :$!location = Whatever,
            :$!id = Whatever,
                    ) {
        die 'The argument $location is expected to be a IO.Path or Whatever.'
        unless $!location.isa(Whatever) || $!location ~~ IO::Path:D;

        $!document-count = %!database.elems;
        $!item-count = %!database.elems;

        die 'The argument $id is expected to be a string or Whatever.'
        unless $!id.isa(Whatever) || $!id ~~ Str:D;

        if $!id.isa(Whatever) { $!id = ~UUID.new(:version(4)); }
    }

    #------------------------------------------------------
    multi method new(@vectors = Empty, *%args) {
        if @vectors {
            my %args2 = %args.grep({ $_.key ne 'database' });
            self.bless(database => @vectors.kv.Hash, |%args2);
        } else {
            self.bless(|%args);
        }
    }

    multi method new(:@ids!, :@vectors!, *%args) {
        die 'The arguments @ids and @vectors are expected to have the same, positive length.'
        unless @ids.elems == @vectors.elems && @vectors.elems > 0;

        my %args2 = %args.grep({ $_.key ne 'database' });
        self.bless(database => (@ids Z=> @vectors).Hash, |%args2);
    }

    #======================================================
    # Utilities
    #======================================================
    # Note that this sub produces information loss since
    # the word groups would miss "meaningful" white space.
    # It is assumed that $max-tokens is larger than any word.
    sub partition-words($text, UInt :$max-chars) {
        my @words = $text.words;
        my @partitions;
        my @current-group;
        my $current-length = 0;

        for @words -> $word {
            if $current-length + $word.chars <= $max-chars {
                @current-group.push: $word;
                # Add one for the joining white space
                $current-length += $word.chars + 1;
            } else {
                @partitions.push: @current-group.join(' ');
                @current-group = ($word);
                $current-length = $word.chars;
            }
        }

        @partitions.push: @current-group.join(' ') if @current-group;
        return @partitions;
    }

    multi sub pad-zeroes(Int:D $num, Int:D $nd) {
        return sprintf('%0*d', $nd, $num);
    }

    multi sub pad-zeroes(Str:D $id, Int $nd) {
        return $id;
    }

    #======================================================
    # Create semantic index
    #======================================================
    multi method create-semantic-search-index(IO::Path:D $location, *%args) {
        # Ingest documents at location

        # 1. Verify $location is a directory with text documents
        die "Not a directory: ⎡$location⎦." unless $location.d;

        # 2. Ingest the documents into an array
        my @content = $location.dir.grep(*.IO.f).map(*.slurp);

        # 3. Delegate
        return self.create-semantic-index(@content, |%args);
    }

    multi method create-semantic-search-index(@content, *%args) {
        my $nd = @content.elems.log10.ceiling;
        self.create-semantic-search-index(
                @content.pairs.map({ pad-zeroes($_.key, $nd) => $_.value }).Hash,
                |%args);
    }

    multi method create-semantic-search-index(%content,
                                              :$method is copy = Whatever,
                                              :&tokenizer is copy = WhateverCode,
                                              :$max-tokens is copy = Whatever,
                                              Bool:D :$embed = True,
                                              Bool:D :$export = True,
                                              *%args) {

        #-------------------------------------------------------------
        # Tokenizer
        my $charsPerToken = 2.5;

        if &tokenizer.isa(WhateverCode) {
            &tokenizer = sub ($text) {
                ($text.chars / $charsPerToken).Int
            };
        }

        #-------------------------------------------------------------
        # Get LLM evaluator
        my $llm-evaluator = %args<llm-evaluator> // %args<e> // %args<conf> // 'ChatGPT';
        $llm-evaluator = llm-evaluator($llm-evaluator);

        #-------------------------------------------------------------
        # Max tokens per text chunk
        if $max-tokens.isa(Whatever) {
            # What is a good number of here?
            # $llm-evaluator.conf.max-tokens is not that adequate.
            $max-tokens = 2048
        }
        die 'The argument max-tokens is expected to be a positive integer or Whatever.'
        unless $max-tokens ~~ Int:D && $max-tokens > 0;

        #-------------------------------------------------------------
        # 1. Split documents into text chunks
        # 1.1. Heuristic paragraphs
        # 1.2. Tokens-count based splitting
        # 1.3. Do nothing is $method is 'asis'
        my %chunks;
        if $method.isa(Whatever) { $method = 'heuristic' }

        die 'The argument $method is expected to be a string or Whatever.'
        unless $method ~~ Str:D;

        given $method {
            when $_ ∈ <heuristic paragraphs text-paragraphs> {
                %chunks =
                        %content.map({
                            my $k = $_.key;
                            $_.value.split(/\n\n+/, :g).pairs.map({ $k ~ '.' ~ $_.key => $_.value }).Slip
                        });
            }
            when $_ ∈ <tokens max-tokens by-max-tokens> {
                %chunks = %content.map({
                    my $k = $_.key;
                    my @res = partition-words($_.value, max-chars => ceiling($max-tokens * $charsPerToken));
                    @res.pairs.map({ $k ~ '.' ~ $_.key => $_.value }).Slip
                })
            }
            when 'asis' {
                %chunks = %content;
            }
            default {
                die "Unknown method for splitting text into embeddable chunks.";
            }
        }

        %!text-chunks = %chunks;

        #-------------------------------------------------------------
        # 2. Verify the text chunks are with size that is allowed
        # 2.1. Use tokenization function if available from the LLM or %args
        # 2.2. Otherwise assume a token is 2.5 characters on average
        my @verified-chunks = %chunks.values.grep({ &tokenizer($_) <= $max-tokens });

        my $allChunksEmbeddable = @verified-chunks.elems == %chunks.elems;

        if !$allChunksEmbeddable {
            note "{ %chunks.elems - @verified-chunks.elems } of the obtained text chunks to embed are larger than the specified max tokens.";
            return self;
        }

        #-------------------------------------------------------------
        # 3. Find the vector embeddings
        my @vector-embeddings = Empty;
        if $embed {
           @vector-embeddings = llm-embedding(@verified-chunks, :$llm-evaluator);
           @vector-embeddings .= deepmap({.Num})
        }

        #-------------------------------------------------------------
        # 4. Create/place the vector database.
        if @vector-embeddings {
            %!database = %chunks.keys Z=> @vector-embeddings;
        } else {
            %!database = Empty
        }

        $!document-count = %content.elems;
        $!item-count = %!database.elems;
        $!llm-configuration = $llm-evaluator.conf;

        #-------------------------------------------------------------
        # Export
        self.export() if $export;

        # Result
        return self;
    }

    #======================================================
    # Nearest
    #======================================================
    multi method nearest(Str:D $query, $spec, *%args) {

        my @vec = |llm-embedding($query, llm-evaluator => self.llm-configuration).head;

        return self.nearest(@vec, $spec, |%args);
    }

    multi method nearest(
            @vec where @vec.all ~~ Numeric:D,
            $spec,
            :$distance-function is copy = Whatever,
            :$method is copy = Whatever,
            :$prop is copy = Whatever) {
        if !%!database {
            note "The vector database is empty";
            return Nil;
        }

        if $distance-function.isa(Whatever) {
            $distance-function = $!distance-function;
            if $distance-function.isa(Whatever) {
                $distance-function = &euclidean-distance
            }
        }

        # It is assumed that making the finder object is fast
        my &finder = nearest(%!database.pairs, :$method, :$distance-function);

        if $prop.isa(Whatever) {
            $prop = <label>;
        }
        my @res = &finder(@vec, $spec, :$prop);

        return @res;
    }

    #======================================================
    # Import
    #======================================================
    method import($file) {
        if !$file.IO.e {
            die "Does not exist: ⎡$file⎦."
        }
        if !$file.IO.f {
            die "Is not a file: ⎡$file⎦."
        }

        my %h = try from-json(slurp($file));

        if $! {
            die "Cannot ingest as a JSON file: ⎡$file⎦."
        }

        $!name = %h<name> // '';
        $!id = %h<id> // '';
        $!distance-function = %h<distance-function> // WhateverCode;
        $!item-count = %h<item-count> // 0;
        $!document-count = %h<document-count> // 0;
        %!database = %h<database> // %();
        %!text-chunks = %h<text-chunks> // %();
        $!tokenizer = %h<tokenizer> // WhateverCode;
        $!version = %h<version> // 0;
        $!location = %h<location> // Whatever;
        $!llm-configuration = %h<llm-configuration> // Whatever;

        if $!llm-configuration ~~ Map:D && ($!llm-configuration<name>:exists) {
            $!llm-configuration = llm-configuration($!llm-configuration<name>, |$!llm-configuration)
        }

        return self;
    }

    #======================================================
    # Export
    #======================================================
    method export($file is copy = Whatever) {
        if $file.isa(Whatever) {
            my $dirName = data-home.Str ~ '/raku/LLM/SemanticSearchIndex';
            if !$dirName.IO.d { $dirName.IO.mkdir }
            my $id = $!id;
            if !$id { $id = DateTime.Str.trans(':'=>'.').substr(^19) }
            $id = "SemSe-$id";
            $file = $dirName ~ "/$id.json";
        }

        # Save location
        $!location = $file.IO.Str;

        # Export
        try {
            my %h = self.Hash;
            %h<llm-configuration> = %h<llm-configuration>.Hash.grep({ $_.key ∈ <name embedding-model> }).Hash;
            spurt $file.IO, to-json(%h);
        }

        if $! {
            note "Error trying to export to file ⎡{$file.IO.Str}⎦:", $!.^name;
        }
        return self;
    }

    #======================================================
    # Representation
    #======================================================
    #| To Hash
    multi method Hash(::?CLASS:D:-->Hash) {
        return
                {
                    :$!id, :$!name, :$!location, :$!version,
                    :$!item-count, :$!document-count,
                    :$!distance-function, :$!tokenizer,
                    :$!llm-configuration,
                    :%!text-chunks,
                    :%!database
                };
    }

    #| To string
    multi method Str(::?CLASS:D:-->Str) {
        return self.gist;
    }

    #| To gist
    multi method gist(::?CLASS:D:-->Str) {
        return 'VectorDatabase' ~ (<id name elements sources> Z=> self.Hash<id name item-count document-count>).List.raku;
    }
}