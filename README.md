# LLM::RetrievalAugmentedGeneration

Raku package for doing LLM Retrieval Augment Generation (RAG).

-----

## General procedure

Assume we have a large (or largish) collection of (Markdown) documents and we want 
to interact with it as if a certain LLM model has been specially trained with that collection.

Here is one way to achieve this:

1. The “data wrangling problem" is the conversion of the a collection of documents into Markdown files, and then partitioning those files into text chunks.
   - There are several packages and functions that can do the conversion.
   - It is not trivial to partition texts into reasonable text chunks.
     - Certain text paragraphs might too big for certain LLMs to make embeddings for.
2. Each of the text chunks is "vectorized" via LLM embedding.
3. Then the vectors are put in a vector database or "just" into a "nearest neighbors" finding function object.
   - A large nearest neighbors finding object can be made with ["Math::Nearest"](https://raku.land/zef:antononcube/Math::Nearest), [AAp6]. 
   - Alternatively, a recommender system can be used like ["ML::StreamsBlendingRecommender"](https://github.com/antononcube/Raku-ML-StreamsBlendingRecommender), [AAp7]. 
4. When a user query is given:
   - The LLM embedding vector is being found.
   - The closest text chunk vectors are found.
5. The corresponding closest text chunks are given to the LLM to formulate a response to user's query.

-----

## References

### Packages

[AAp1] Anton Antonov,
[WWW::OpenAI Raku package](https://github.com/antononcube/Raku-WWW-OpenAI),
(2023),
[GitHub/antononcube](https://github.com/antononcube).

[AAp2] Anton Antonov,
[WWW::PaLM Raku package](https://github.com/antononcube/Raku-WWW-PaLM),
(2023),
[GitHub/antononcube](https://github.com/antononcube).

[AAp3] Anton Antonov,
[LLM::Functions Raku package](https://github.com/antononcube/Raku-LLM-Functions),
(2023-2024),
[GitHub/antononcube](https://github.com/antononcube).

[AAp4] Anton Antonov,
[LLM::Prompts Raku package](https://github.com/antononcube/Raku-LLM-Prompts),
(2023-2024),
[GitHub/antononcube](https://github.com/antononcube).

[AAp5] Anton Antonov,
[ML::FindTextualAnswer Raku package](https://github.com/antononcube/Raku-ML-FindTextualAnswer),
(2023-2024),
[GitHub/antononcube](https://github.com/antononcube).

[AAp6] Anton Antonov,
[Math::Nearest Raku package](https://github.com/antononcube/Raku-Math-Nearest),
(2024),
[GitHub/antononcube](https://github.com/antononcube).

[AAp7] Anton Antonov,
[ML::StreamsBlendingRecommender Raku package](https://github.com/antononcube/Raku-ML-StreamsBlendingRecommender),
(2021-2023),
[GitHub/antononcube](https://github.com/antononcube).
