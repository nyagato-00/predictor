module Predictor
  @@redis = nil
  @@redis_prefix = nil

  def self.redis=(redis)
    @@redis = redis
  end

  def self.redis
    return @@redis unless @@redis.nil?
    raise "redis not configured! - Predictor.redis = Redis.new"
  end

  def self.redis_prefix(prefix = nil, &block)
    @@redis_prefix = block_given? ? block : prefix
  end

  def self.get_redis_prefix
    if @@redis_prefix
      if @@redis_prefix.respond_to?(:call)
        @@redis_prefix.call
      else
        @@redis_prefix
      end
    else
      'predictor'
    end
  end

  def self.capitalize(str_or_sym)
  	str = str_or_sym.to_s.each_char.to_a
  	str.first.upcase + str[1..-1].join("").downcase
  end

  def self.constantize(klass)
    Object.module_eval("Predictor::#{klass}", __FILE__, __LINE__)
  end
end
