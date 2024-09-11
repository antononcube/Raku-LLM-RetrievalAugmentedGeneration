#!/usr/bin/env raku
use v6.d;

use lib <. lib>;
use LLM::RetrievalAugmentedGeneration;

say '=' x 100;
say "Files";
say '-' x 100;
.say for vector-database-objects(format=>'file');

say '=' x 100;
say "Basenames";
say '-' x 100;
.say for vector-database-objects».basename;

say '=' x 100;
say "Gists";
say '-' x 100;
.say for vector-database-objects(f=>'gist');

say '=' x 100;
say "Hash summaries";
say '-' x 100;
.say for vector-database-objects(f=>'summary');