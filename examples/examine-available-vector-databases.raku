#!/usr/bin/env raku
use v6.d;

use lib <. lib>;
use LLM::RetrievalAugmentedGeneration;

say '=' x 100;
say "Gists";
say '-' x 100;
# Same as
# .say for vector-database-objects(f=>'gist');
.say for vector-database-objects;

say '=' x 100;
say "Hash summaries";
say '-' x 100;
.say for vector-database-objects(f=>'summary');

say '=' x 100;
say "Files names";
say '-' x 100;
.say for vector-database-objects(format=>'file-name');

say '=' x 100;
say "Basenames of IO:Path objects";
say '-' x 100;
.say for vector-database-objects(form=>'file')».basename;

#`[
say '=' x 100;
say "Short file spec import";
say '-' x 100;
say create-vector-database(file => 'a6b12f80-0ed7-4125-9e2b-9f77c11a16f8');
]