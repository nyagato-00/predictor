=======
Predictor
=========

Fast and efficient recommendations and predictions using Redis.

![](https://www.codeship.io/projects/5aeeedf0-6053-0131-2319-5ede98f174ff/status)

Originally forked and based on [Recommendify](https://github.com/paulasmuth/recommendify) by Paul Asmuth, so a huge thanks to him for his contributions to Recommendify. Predictor has been almost completely rewritten to
* Be more performant and efficient by using Redis for most logic
* Provide predictions as well as item similarities (supports both cases of "Users that liked this book also liked ..." and "You liked these x books, so you might also like...")

At the moment, Predictor uses the [Jaccard index](http://en.wikipedia.org/wiki/Jaccard_index) to determine similarities between items.

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

# Or, to improve performance, add hiredis as your driver (you'll need to install the hiredis gem first
Predictor.redis = Redis.new(:url => ENV["PREDICTOR_REDIS"], :driver => :hiredis)
```
Usage
---------------------
Create a class and include the Predictor::Base module. Define an input_matrix for each relationship you'd like to keep track. Below, we're building a recommender to recommend courses based off of:
* Users that have taken a course (the :user matrix). If 2 courses were taken by the same user, this is 3 times as important to us than if the courses share the same topic. This will lead to sets like:
  * "user1" -> "course1", "course3",
  * "user2" -> "course1", "course4"
* Tags and their courses. This will lead to sets like:
  * "rails" -> "course1", "course2",
  * "microeconomics" -> "course3", "course4"
* Topics and their courses. This will lead to sets like:
  * "computer science" -> "course1", "course2",
  * "economics and finance" -> "course3", "course4"

```ruby
  class CourseRecommender
    include Predictor::Base

    input_matrix :users, :weight => 3.0
    input_matrix :tags, :weight => 2.0
    input_matrix :topics, :weight => 1.0
  end
```

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

