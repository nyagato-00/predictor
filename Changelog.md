=======
Predictor Changelog
=========
2.0.0 (2014-03-07)
---------------------
**Rewrite of 1.0.0 and contains several breaking changes!**

Version 1.0.0 (which really should have been 0.0.1) contained several issues that made compatability with v2 not worth the trouble. This includes:
* In v1, similarities were cached per input_matrix, and Predictor::Base utilized those caches when determining similarities and predictions. This quickly ate up Redis memory with even a semi-large dataset, as each input_matrix had a significant memory requirement. v2 caches similarities at the root (Recommender::Base), which means you can add any number of input matrices with little impact on memory usage.
* Added the ability to limit the number of items stored in the similarity cache (via the 'limit_similarities_to' option). Now that similarities are cached at the root, this is possible and can greatly help memory usage.
* Removed bang methods from input_matrix (add_set!, and_single!, etc). These called process! for you previously, but since the cache is no longer kept at the input_matrix level, process! has to be called at the root (Recommender::Base)
* Bug fix: Fixed bug where a call to delete_item! on the input matrix didn't update the similarity cache.
* Other minor fixes.