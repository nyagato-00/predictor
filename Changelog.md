=======
Predictor Changelog
=========

2.3.0
---------------------
* The logic for processing item similarities was ported to a Lua script. Use `Predictor.processing_technique(:lua)` to use the Lua script for all similarity calculations, or use `MyRecommender.processing_technique(:lua)` to use it for specific recommenders. It is substantially faster than the default (old) Ruby mechanism, but has the disadvantage of blocking the Redis server while it runs.
* An alternate method of calculating item similarities was added, which uses a ZUNIONSTORE across item sets. The results are similar to those achieved by using the Ruby or Lua scripts, but faster. Use `Predictor.processing_technique(:union)` to use the ZUNIONSTORE technique for all similarity calculations, or use `MyRecommender.processing_technique(:union)` to use it for specific recommenders.

2.2.0 (2014-06-24)
---------------------
* The namespace used for keys in Redis is now configurable on a global or per-class basis. See the readme for more information. If you were overriding the redis_prefix instance method before, it is recommended that you use the new redis_prefix class method instead.
* Data stored in Redis is now namespaced by the class name of the recommender it is stored by. This change ensures that different recommenders with input matrices of the same name don't overwrite each others' data. After upgrading you'll need to either reindex your data in Redis or configure Predictor to use the naming system you were using before. If you were using the defaults before and you're not worried about matrix name collisions, you can mimic the old behavior with:
```ruby
  class MyRecommender
    include Predictor::Base
    redis_prefix [nil]
  end
```
* The #predictions_for method on recommenders now accepts a :boost option to give more weight to items with particular attributes. See the readme for more information.

2.1.0 (2014-06-19)
---------------------
* The similarity limit now defaults to 128, instead of being unlimited. This is intended to save space in Redis. See the Readme for more information. It is strongly recommended that you run `ensure_similarity_limit_is_obeyed!` to shrink existing similarity sets.

2.0.0 (2014-04-17)
---------------------
**Rewrite of 1.0.0 and contains several breaking changes!**

Version 1.0.0 (which really should have been 0.0.1) contained several issues that made compatability with v2 not worth the trouble. This includes:
* In v1, similarities were cached per input_matrix, and Predictor::Base utilized those caches when determining similarities and predictions. This quickly ate up Redis memory with even a semi-large dataset, as each input_matrix had a significant memory requirement. v2 caches similarities at the root (Recommender::Base), which means you can add any number of input matrices with little impact on memory usage.
* Added the ability to limit the number of items stored in the similarity cache (via the 'limit_similarities_to' option). Now that similarities are cached at the root, this is possible and can greatly help memory usage.
* Removed bang methods from input_matrix (add_set!, and_single!, etc). These called process! for you previously, but since the cache is no longer kept at the input_matrix level, process! has to be called at the root (Recommender::Base)
* Bug fix: Fixed bug where a call to delete_item! on the input matrix didn't update the similarity cache.
* Other minor fixes.
