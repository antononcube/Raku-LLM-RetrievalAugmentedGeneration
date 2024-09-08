use v6.d;

use UUID;
use LLM::Functions;

class LLM::RetrievalAugmentedGeneration::VectorDatabase {

    has Str:D $.name is rw = '';
    has $.id is rw = '';
    has $.distance-function is rw = WhateverCode;
    has $.item-count = 0;
    has $.document-count = 0;
    has %.database;
    has %.text-chunks;
    has $.tokenizer = WhateverCode;
    has UInt:D $.version = 0;
    has $.location = Whatever;

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
    # Partition into text chunks
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

    multi method create-semantic-search-index(@content,
                                              :$method is copy = Whatever,
                                              :&tokenizer is copy = WhateverCode,
                                              :$max-tokens is copy = Whatever,
                                              Bool:D :$embed = True,
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
        my @chunks;
        if $method.isa(Whatever) { $method = 'heuristic' }

        die 'The argument $method is expected to be a string or Whatever.'
        unless $method ~~ Str:D;

        given $method {
            when $_ ∈ <heuristic paragraphs text-paragraphs> {
                @chunks = @content.map(*.split(/\n\n+/, :g)).map(*.Slip);
            }
            when $_ ∈ <tokens max-tokens by-max-tokens> {
                @chunks = @content.map({ partition-words($_, max-chars => ceiling($max-tokens * $charsPerToken)) }).map(*.Slip);
            }
            when 'asis' {
                @chunks = @content;
            }
            default {
                die "Unknown method for splitting text into embeddable chunks.";
            }
        }

        %!text-chunks = @chunks.kv.Hash;

        #-------------------------------------------------------------
        # 2. Verify the text chunks are with size that is allowed
        # 2.1. Use tokenization function if available from the LLM or %args
        # 2.2. Otherwise assume a token is 2.5 characters on average
        my @verified_chunks = @chunks.grep({ &tokenizer($_) <= $max-tokens });

        my $allChunksEmbeddable = @verified_chunks.elems == @chunks.elems;

        if !$allChunksEmbeddable {
            note "{ @chunks.elems - @verified_chunks.elems } of the obtained text chunks to embed are larger than the specified max tokens.";
            return self;
        }

        #-------------------------------------------------------------
        # 3. Find the vector embeddings
        my @vector_embeddings = $embed ?? llm-embedding(@verified_chunks, :$llm-evaluator) !! @verified_chunks;

        #-------------------------------------------------------------
        # 4. Create/place the vector database.
        %!database = @vector_embeddings.kv.Hash;

        # Result
        return self;
    }
}