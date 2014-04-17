=======
Predictor
=========

Fast and efficient recommendations and predictions using Ruby & Redis. Used in production over at [Pathgather](http://pathgather.com) to generate course similarities and content recommendations to users.

![](https://www.codeship.io/projects/5aeeedf0-6053-0131-2319-5ede98f174ff/status)

Originally forked and based on [Recommendify](https://github.com/paulasmuth/recommendify) by Paul Asmuth, so a huge thanks to him for his contributions to Recommendify. Predictor has been almost completely rewritten to
* Be much, much more performant and efficient by using Redis for most logic.
* Provide item similarities such as "Users that read this book also read ..."
* Provide personalized predictions based on a user's past history, such as "You read these 10 books, so you might also like to read ..."

At the moment, Predictor uses the [Jaccard index](http://en.wikipedia.org/wiki/Jaccard_index) to determine similarities between items. There are other ways to do this, which we intend to implement eventually, but if you want to beat us to the punch, pull requests are quite welcome :)

Installation
---------------------
```ruby
gem install predictor
````
or in your Gemfile:
````
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
  input_matrix :topics, weight: 1.0
end
```

Now, we just need to update our matrices when courses are created, users take a course, topics are changed, etc:
```ruby
recommender = CourseRecommender.new

# Add a single course to topic-1's items. If topic-1 already exists as a set ID, this just adds course-1 to the set
recommender.topics.add_single!("topic-1", "course-1")

# If your matrix is quite large, add_single! could take some time, as it must calculate the similarity scores
# for course-1 across all other courses. If this is the case, use add_single and process the item at a more
# convenient time, perhaps in a background job
recommender.topics.add_single("topic-1", "course-1")
recommender.topics.process_item!("course-1")

# Add an array of courses to tag-1. Again, these will simply be added to tag-1's existing set, if it exists.
# If not, the tag-1 set will be initialized with course-1 and course-2
recommender.tags.add_set!("tag-1", ["course-1", "course-2"])

# Or, just add the set and process whenever you like
recommender.tags.add_set("tag-1", ["course-1", "course-2"])
["course-1", "course-2"].each { |course| recommender.topics.process_item!(course) }
```

As noted above, it's important to remember that if you don't use the bang methods (add_set! and add_single!), you'll need to manually update your similarities (the bang methods will likely suffice for most use cases though). You can do so a variety of ways.
* If you want to simply update the similarities for a single item in a specific matrix:
  ````
  recommender.matrix.process_item!(item)
  ````
* If you want to update the similarities for all items in a specific matrix:
  ````
  recommender.matrix.process!
  ````
* If you want to update the similarities for a single item in all matrices:
  ````
  recommender.process_item!(item)
  ````
* If you want to update all similarities in all matrices:
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

# Gimme some scores and ignore user-2....that user-2 is one sketchy fella
recommender.predictions_for("user-1", matrix_label: :users, with_scores: true, exclusion_set: ["user-2"])
```

Deleting Items
---------------------
If your data is deleted from your persistent storage, you certainly don't want to recommend that data to a user. To ensure that doesn't happen, simply call delete_item! on the individual matrix or recommender as a whole:
```ruby
recommender = CourseRecommender.new

# User removed course-1 from topic-1, but course-1 still exists
recommender.topics.delete_item!("course-1")

# course-1 was permanently deleted
recommender.delete_item!("course-1")

# Something crazy has happened, so let's just start fresh and wipe out all previously stored similarities:
recommender.clean!
```

Memory Management
---------------------
Predictor works by caching the similarities for each item in each matrix, then computing overall similarities off those caches. With an even semi-large dataset, this can really eat up Redis's memory. To limit the number of similarities cached in each matrix, specify a similarity_limit option when defining the matrix.
```ruby
class CourseRecommender
  include Predictor::Base

  input_matrix :users, weight: 3.0, similarity_limit: 300
  input_matrix :tags, weight: 2.0, similarity_limit: 300
  input_matrix :topics, weight: 1.0, similarity_limit: 300
end
```

This will ensure that only the top 300 similarities for each item are cached in each matrix. This can greatly reduce your memory usage, and if you're just using Predictor for scenarios where you maybe show the top 5 or so similar items, then this can be hugely helpful. But note, **don't set similarity_limit to 5 in that case**. This simply limits the similarities cached in each matrix, but does not limit the similarities for an item across all matrices. That is computed (and can be limited) on the fly, and uses the similarity cache in each matrix. So, you need a large enough cache in each matrix to determine an intelligent similarity list across all matrices.

*Note*: This is a bit of a hack, and there are most certainly other ways to improve Predictor's memory usage for large datasets, but each appear to require a more significant change than the trivial implementation of similarity_limit above. PRs are quite welcome that experiment with these other ways :)

Oh, and if you decide to tinker with your limit to try and find a sweet spot, I added a helpful method to ensure limits are obeyed to avoid regenerating all similarities. Of course, this only helps if you are decreasing the limit. If you're increasing it, you'll need to process similarities all over.
```ruby
recommender.users.ensure_similarity_limit_is_obeyed!  # Remove similarities that disobey our current limit
recommender.tags.ensure_similarity_limit_is_obeyed!
recommender.topics.ensure_similarity_limit_is_obeyed!
```

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

