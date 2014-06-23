require "predictor"
require "pry"

def flush_redis!
  Predictor.redis = Redis.new
  Predictor.redis.keys("predictor-test*").each do |k|
    Predictor.redis.del(k)
  end
end

Predictor.redis_prefix "predictor-test"

class BaseRecommender
  include Predictor::Base
end

class UserRecommender
  include Predictor::Base
end

class TestRecommender
  include Predictor::Base

  input_matrix :jaccard_one
end

class Predictor::TestInputMatrix
  def initialize(opts)
    @opts = opts
  end

  def method_missing(method, *args)
    @opts[method]
  end
end
