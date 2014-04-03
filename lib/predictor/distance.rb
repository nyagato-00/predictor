module Predictor
  module Distance
    extend self

    def jaccard_index(key_1, key_2, redis = Predictor.redis)
      x, y = nil

      redis.multi do |multi|
        x = multi.sinterstore 'temp', [key_1, key_2]
        y = multi.sunionstore 'temp', [key_1, key_2]
        multi.del 'temp'
      end

      y.value > 0 ? (x.value.to_f/y.value.to_f) : 0.0
    end

    def sorensen_coefficient(key_1, key_2, redis = Predictor.redis)
      x, y, z = nil

      redis.multi do |multi|
        x = multi.sinterstore 'temp', [key_1, key_2]
        y = multi.scard key_1
        z = multi.scard key_2
        multi.del 'temp'
      end

      denom = (y.value + z.value)
      denom > 0 ? (2 * (x.value) / denom.to_f) : 0.0
    end
  end
end
