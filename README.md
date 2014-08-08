=======
Predictor
=========

Fast and efficient recommendations and predictions using Ruby & Redis. Developed by and used at [Pathgather](http://pathgather.com) to generate course similarities and content recommendations to users.

![](https://www.codeship.io/projects/5aeeedf0-6053-0131-2319-5ede98f174ff/status)

Originally forked and based on [Recommendify](https://github.com/paulasmuth/recommendify) by Paul Asmuth, so a huge thanks to him for his contributions to Recommendify. Predictor has been almost completely rewritten to
* Be much, much more performant and efficient by using Redis for most logic.
* Provide item similarities such as "Users that read this book also read ..."
* Provide personalized predictions based on a user's past history, such as "You read these 10 books, so you might also like to read ..."

At the moment, Predictor uses the [Jaccard index](http://en.wikipedia.org/wiki/Jaccard_index) or the [Sorenson-Dice coefficient](http://en.wikipedia.org/wiki/S%C3%B8rensen%E2%80%93Dice_coefficient) (default is Jaccard) to determine similarities between items. There are other ways to do this, which we intend to implement eventually, but if you want to beat us to the punch, pull requests are quite welcome :)

Notice
---------------------
This is the readme for Predictor 2.0, which contains a few breaking changes from 1.0. The 1.0 readme can be found [here](https://github.com/Pathgather/predictor/blob/master/docs/READMEv1.md). See below on how to upgrade to 2.0

Installation
---------------------
In your Gemfile:
```ruby
gem 'predictor'
```
Getting Started
---------------------
First step is to configure Predictor with your Redis instance.
```ruby
# in config/initializers/predictor.rb
Predictor.redis = Redis.new(:url => ENV["PREDICTOR_REDIS"])

# Or, to improve performance, add hiredis as your driver (you'll need to install the hiredis gem first)
Predictor.redis = Redis.new(:url => ENV["PREDICTOR_REDIS"], :driver => :hiredis)
```

Inputting Data
---------------------
Create a class and include the Predictor::Base module. Define an input_matrix for each relationship you'd like to keep track of. This can be anything you think is a significant metric for the item: page views, purchases, categories the item belongs to, etc.

Below, we're building a recommender to recommend courses based off of:
* Users that have taken a course. If 2 courses were taken by the same user, this is 3 times as important to us than if the courses share the same topic. This will lead to sets like:
  * "user1" -> "course-1", "course-3",
  * "user2" -> "course-1", "course-4"
* Tags and their courses. This will lead to sets like:
  * "rails" -> "course-1", "course-2",
  * "microeconomics" -> "course-3", "course-4"
* Topics and their courses. This will lead to sets like:
  * "computer science" -> "course-1", "course-2",
  * "economics and finance" -> "course-3", "course-4"

```ruby
class CourseRecommender
  include Predictor::Base

  input_matrix :users, weight: 3.0
  input_matrix :tags, weight: 2.0
  input_matrix :topics, weight: 1.0, measure: :sorensen_coefficient # Use Sorenson over Jaccard
end
```

Now, we just need to update our matrices when courses are created, users take a course, topics are changed, etc:
```ruby
recommender = CourseRecommender.new

# Add a single course to topic-1's items. If topic-1 already exists as a set ID, this just adds course-1 to the set
recommender.add_to_matrix!(:topics, "topic-1", "course-1")

# If your dataset is even remotely large, add_to_matrix! could take some time, as it must calculate the similarity scores
# for course-1 and other courses that share a set with course-1. If this is the case, use add_to_matrix and
# process the items at a more convenient time, perhaps in a background job
recommender.topics.add_to_set("topic-1", "course-1", "course-2") # Same as recommender.add_to_matrix(:topics, "topic-1", "course-1", "course-2")
recommender.process_items!("course-1", "course-2")
```

As noted above, it's important to remember that if you don't use the bang method 'add_to_matrix!', you'll need to manually update your similarities. If your dataset is even remotely large, you'll probably want to do this:
* If you want to update the similarities for certain item(s):
  ````
  recommender.process_items!(item1, item2, etc)
  ````
* If you want to update all similarities for all items:
  ````
  recommender.process!
  ````

Retrieving Similarities and Recommendations
---------------------
Now that your matrices have been initialized with several relationships, you can start generating similarities and recommendations! First, let's start with similarities, which will use the weights we specify on each matrix to determine which courses share the most in common with a given course.

![Course Alternative](http://pathgather.github.io/predictor/images/course-alts.png)

```ruby
recommender = CourseRecommender.new

# Return all similarities for course-1 (ordered by most similar to least).
recommender.similarities_for("course-1")

# Need to paginate? Not a problem! Specify an offset and a limit
recommender.similarities_for("course-1", offset: 10, limit: 10) # Gets similarities 11-20

# Want scores?
recommender.similarities_for("course-1", with_scores: true)

# Want to ignore a certain set of courses in similarities?
recommender.similarities_for("course-1", exclusion_set: ["course-2"])
```

The above examples are great for situations like "Users that viewed this also liked ...", but what if you wanted to recommend courses to a user based on the courses they've already taken? Not a problem!

![Course Recommendations](http://pathgather.github.io/predictor/images/suggested.png)

```ruby
recommender = CourseRecommender.new

# User has taken course-1 and course-2. Let's see what else they might like...
recommender.predictions_for(item_set: ["course-1", "course-2"])

# Already have the set you need stored in an input matrix? In our case, we do (the users matrix stores the courses a user has taken), so we can just do:
recommender.predictions_for("user-1", matrix_label: :users)

# Paginate too!
recommender.predictions_for("user-1", matrix_label: :users, offset: 10, limit: 10)

# Gimme some scores and ignore course-2....that course-2 is one sketchy fella
recommender.predictions_for("user-1", matrix_label: :users, with_scores: true, exclusion_set: ["course-2"])
```

Deleting Items
---------------------
If your data is deleted from your persistent storage, you certainly don't want to recommend it to a user. To ensure that doesn't happen, simply call delete_from_matrix! with the individual matrix or delete_item! if the item is completely gone:
```ruby
recommender = CourseRecommender.new

# User removed course-1 from topic-1, but course-1 still exists
recommender.delete_from_matrix!(:topics, "course-1")

# course-1 was permanently deleted
recommender.delete_item!("course-1")

# Something crazy has happened, so let's just start fresh and wipe out all previously stored similarities:
recommender.clean!
```

Limiting Similarities
---------------------
By default, Predictor caches 128 similarities for each item. This is because this is the maximum size for the similarity sorted sets to be kept in a [memory-efficient format](http://redis.io/topics/memory-optimization). If you want to keep more similarities than that, and you don't mind using more memory, you may want to increase the similarity limit, like so:

```ruby
class CourseRecommender
  include Predictor::Base

  limit_similarities_to 500
  input_matrix :users, weight: 3.0
  input_matrix :tags, weight: 2.0
  input_matrix :topics, weight: 1.0
end
```

The memory penalty can be heavy, though. In our testing, similarity caches for 1,000 objects varied in size like so:

```
limit_similarities_to(128) # 8.5 MB (this is the default)
limit_similarities_to(129) # 22.74 MB
limit_similarities_to(500) # 76.72 MB
```

If you decide you need to store more than 128 similarities, you may want to see the Redis documentation linked above and consider increasing `zset-max-ziplist-entries` in your configuration.

Predictions fetched with the predictions_for call utilizes the similarity caches, so if you're using predictions_for, make sure you set the limit high enough so that intelligent predictions can be generated. If you aren't using predictions and are just using similarities, then feel free to set this to the maximum number of similarities you'd possibly want to show!

You can also use `limit_similarities_to(nil)` to remove the limit entirely. This means if you have 10,000 items, and each item is somehow related to the other, you'll have 10,000 sets each with 9,999 items, which will run up your Redis bill quite quickly. Removing the limit is not recommended unless you're sure you know what you're doing.

If at some point you decide to lower your similarity limits, you'll want to be sure to shrink the size of the sorted sets already in Redis. You can do this with `CourseRecommender.new.ensure_similarity_limit_is_obeyed!`.

Boost
---------------------
What if you want to recommend courses to users based not only on what courses they've taken, but on other attributes of courses that they may be interested in? You can do that by passing the :boost argument to predictions_for:

```ruby
class CourseRecommender
  include Predictor::Base

  # Courses are compared to one another by the users taking them and their tags.
  input_matrix :users,  weight: 3.0
  input_matrix :tags,   weight: 2.0
  input_matrix :topics, weight: 2.0
end

recommender = CourseRecommender.new

# We want to find recommendations for Billy, who's told us that he's
# especially interested in free, interactive courses on Photoshop. So, we give
# a boost to courses that are tagged as free and interactive and have
# Photoshop as a topic:
recommender.predictions_for("Billy", matrix_label: :users, boost: {tags: ['free', 'interactive'], topics: ["Photoshop"]})

# We can also modify how much these tags and topics matter by specifying a
# weight. The default is 1.0, but if that's too much we can just tweak it:
recommender.predictions_for("Billy", matrix_label: :users, boost: {tags: {values: ['free', 'interactive'], weight: 0.4}, topics: {values: ["Photoshop"], weight: 0.3}})
```

Key Prefixes
---------------------
As of 2.2.0, there is much more control available over the format of the keys Predictor will use in Redis. By default, the CourseRecommender given as an example above will use keys like "predictor:CourseRecommender:users:items:user1". You can configure the global namespace like so:

```ruby
  Predictor.redis_prefix 'my_namespace' # => "my_namespace:CourseRecommender:users:items:user1"
  # Or, for a multitenanted setup:
  Predictor.redis_prefix { "user-#{User.current.id}" } # => "user-7:CourseRecommender:users:items:user1"
```

You can also configure the namespace used by each class you create:

```ruby
  class CourseRecommender
    include Predictor::Base
    redis_prefix "courses" # => "predictor:courses:users:items:user1"
    redis_prefix { "courses_for_user-#{User.current.id}" } # => "predictor:courses_for_user-7:users:items:user1"
  end
```

Processing Items
---------------------
As of 2.3.0, there are now multiple techniques available for processing item similarities. You can choose between them by setting a global default like `Predictor.processing_technique(:lua)` or setting a technique for certain classes like `CourseRecommender.processing_technique(:union)`. There are three values.
- :ruby - This is the default, and is how Predictor calculated similarities before 2.3.0. With this technique the Jaccard and Sorensen calculations are performed in Ruby, with frequent calls to Redis to retrieve simple values. It is somewhat slow.
- :lua - This option performs the Jaccard and Sorensen calculations in a Lua script on the Redis server. It is substantially faster than the :ruby technique, but blocks the Redis server while each set of calculations are run. The period of blocking will vary based on the size and disposition of your data, but each call may take up to several hundred milliseconds. If your application requires your Redis server to always return results quickly, and you're not able to simply run calculations during off-hours, you should use a different strategy.
- :union - This option skips Jaccard and Sorensen entirely, and uses a simpler technique involving a ZUNIONSTORE across many item sets to calculate similarities. The results are different from, but similar to the results of using the Jaccard and Sorensen algorithms. It is even faster than the :lua option and does not have the same problem of blocking Redis for long periods of time, but before using it you should sample the output to ensure that it is good enough for your application.

Predictor now contains a benchmarking script that you can use to compare the speed of these options. An example output from the processing of a relatively small dataset is:

```
ruby = 21.098 seconds
lua = 2.106 seconds
union = 0.741 seconds
```

Upgrading from 1.0 to 2.0
---------------------
As mentioned, 2.0.0 is quite a bit different than 1.0.0, so simply upgrading with no changes likely won't work. My apologies for this. I promise this won't happen in future releases, as I'm much more confident in this Predictor release than the last. Anywho, upgrading really shouldn't be that much of a pain if you follow these steps:

* Change predictor.matrix.add_set! and predictor.matrix.add_single! calls to predictor.add_to_matrix!. For example:
```ruby
# Change
predictor.topics.add_single!("topic-1", "course-1")
# to
predictor.add_to_matrix!(:topics, "topic-1", "course-1")

# Change
predictor.tags.add_set!("tag-1", ["course-1", "course-2"])
# to
predictor.add_to_matrix!(:tags, "tag-1", "course-1", "course-2")
```
* Change predictor.matrix.process! or predictor.matrix.process_item! calls to just predictor.process! or predictor.process_items!
```ruby
# Change
predictor.topics.process_item!("course-1")
# to
predictor.process_items!("course-1")
```
* Change predictor.matrix.delete_item! calls to predictor.delete_from_matrix!. This will update similarities too, so you may want to queue this to run in a background job.
```ruby
# Change
predictor.topics.delete_item!("course-1")
# to delete_from_matrix! if you want to update similarities to account for the deleted item (in v1, this was a bug and didn't occur)
predictor.delete_from_matrix!(:topics, "course-1")
```
* Regenerate your recommendations, as redis keys have changed for Predictor 2. You can use the recommender.clean! to clear out old similarities, then run your rake task (or whatever you've setup) to create new similarities.

Problems? Issues? Want to help out?
---------------------
Just submit a Gihub issue or pull request! We'd love to have you help out, as the most common library to use for this need, Recommendify, was last updated 2 years ago. We'll be sure to keep this maintained, but we could certainly use your help!

The MIT License (MIT)
---------------------
Copyright (c) 2014 Pathgather

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
