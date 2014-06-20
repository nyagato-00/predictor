require "predictor"
require "pry"

def flush_redis!
  Predictor.redis = Redis.new
  Predictor.redis.keys("predictor-test*").each do |k|
    Predictor.redis.del(k)
  end
end

module Predictor::Base
  def predictor_redis_prefix
    "predictor-test"
  end
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
