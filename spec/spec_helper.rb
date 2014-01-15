require "rspec"
require "redis"
require "pry"

require ::File.expand_path('../../lib/predictor', __FILE__)

def flush_redis!
  Predictor.redis = Redis.new
  Predictor.redis.keys("predictor-test*").each do |k|
    Predictor.redis.del(k)
  end
end

module Predictor::Base

  def redis_prefix
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