module Predictor::Base
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def input_matrix(key, opts={})
      @matrices ||= {}
      @matrices[key] = opts
    end

    def recommend_for(key, opts)
      @associative_recommendations ||= {}
      @associative_recommendations[key] = opts
    end

    def limit_similarities_to(val)
      @similarity_limit_set = true
      @similarity_limit     = val
    end

    def similarity_limit
      @similarity_limit_set ? @similarity_limit : 128
    end

    def reset_similarity_limit!
      @similarity_limit_set = nil
      @similarity_limit     = nil
    end

    def input_matrices=(val)
      @matrices = val
    end

    def input_matrices
      @matrices
    end

    attr_accessor :associative_recommendations
  end

  def input_matrices
    @input_matrices ||= Hash[self.class.input_matrices.map{ |key, opts|
      opts.merge!(:key => key, :redis_prefix => redis_prefix)
      [ key, Predictor::InputMatrix.new(opts) ]
    }]
  end

  def predictor_redis_prefix
    "predictor" # Overridden in testing.
  end

  def redis_prefix
    "#{predictor_redis_prefix}:#{self.class.to_s}"
  end

  def similarity_limit
    self.class.similarity_limit
  end

  def redis_key(*append)
    ([redis_prefix] + append).flatten.compact.join(":")
  end

  def method_missing(method, *args)
    if input_matrices.has_key?(method)
      input_matrices[method]
    else
      raise NoMethodError.new(method.to_s)
    end
  end

  def respond_to?(method)
    input_matrices.has_key?(method) ? true : super
  end

  def all_items
    Predictor.redis.smembers(redis_key(:all_items))
  end

  def add_to_matrix(matrix, set, *items)
    items = items.flatten if items.count == 1 && items[0].is_a?(Array)  # Old syntax
    input_matrices[matrix].add_to_set(set, *items)
  end

  def add_to_matrix!(matrix, set, *items)
    items = items.flatten if items.count == 1 && items[0].is_a?(Array)  # Old syntax
    add_to_matrix(matrix, set, *items)
    process_items!(*items)
  end

  def related_items(item)
    keys = []
    input_matrices.each do |key, matrix|
      sets = Predictor.redis.smembers(matrix.redis_key(:sets, item))
      keys.concat(sets.map { |set| matrix.redis_key(:items, set) })
    end

    keys.empty? ? [] : (Predictor.redis.sunion(keys) - [item.to_s])
  end

  def predictions_for(set=nil, item_set: nil, matrix_label: nil, with_scores: false, offset: 0, limit: -1, exclusion_set: [])
    fail "item_set or matrix_label and set is required" unless item_set || (matrix_label && set)

    # binding.pry
    # 0

    if matrix_label
      matrix = input_matrices[matrix_label]
      item_set = Predictor.redis.smembers(matrix.redis_key(:items, set))
      association = self.class.associative_recommendations[matrix_label]
    end

    item_keys = []
    weights   = []

    item_set.each do |item|
      item_keys << redis_key(:similarities, item)
      weights   << 1.0
    end

    return [] if item_keys.empty?

    # if association
    #   recommender = Object.const_get(association[:recommender]).new

    #   association[:via].each do |key, weight|
    #     k = recommender.redis_key(:items, key)
    #   end
    # end

    # boost.each do |matrix_label, values|
    #   m = input_matrices[matrix_label]

    #   # Passing plain sets to zunionstore is undocumented, but tested and supported:
    #   # https://github.com/antirez/redis/blob/2.8.11/tests/unit/type/zset.tcl#L481-L489

    #   case values
    #   when Hash
    #     values[:values].each do |value|
    #       item_keys << m.redis_key(:items, value)
    #       weights   << values[:weight]
    #     end
    #   when Array
    #     values.each do |value|
    #       item_keys << m.redis_key(:items, value)
    #       weights   << 1.0
    #     end
    #   else
    #     raise "Bad value for boost: #{boost.inspect}"
    #   end
    # end

    predictions = nil

    Predictor.redis.multi do |multi|
      multi.zunionstore 'temp', item_keys
      multi.zrem 'temp', item_set
      multi.zrem 'temp', exclusion_set if exclusion_set.length > 0
      predictions = multi.zrevrange 'temp', offset, limit == -1 ? limit : offset + (limit - 1), with_scores: with_scores
      multi.del 'temp'
    end

    predictions.value
  end

  def similarities_for(item, with_scores: false, offset: 0, limit: -1, exclusion_set: [])
    neighbors = nil
    Predictor.redis.multi do |multi|
      multi.zunionstore 'temp', [1, redis_key(:similarities, item)]
      multi.zrem 'temp', exclusion_set if exclusion_set.length > 0
      neighbors = multi.zrevrange('temp', offset, limit == -1 ? limit : offset + (limit - 1), with_scores: with_scores)
      multi.del 'temp'
    end
    return neighbors.value
  end

  def sets_for(item)
    keys = input_matrices.map{ |k,m| m.redis_key(:sets, item) }
    Predictor.redis.sunion keys
  end

  def process_item!(item)
    process_items!(item)  # Old method
  end

  def process_items!(*items)
    items = items.flatten if items.count == 1 && items[0].is_a?(Array)  # Old syntax
    items.each do |item|
      related_items(item).each{ |related_item| cache_similarity(item, related_item) }
    end
    return self
  end

  def process!
    process_items!(*all_items)
    return self
  end

  def delete_from_matrix!(matrix, item)
    # Deleting from a specific matrix, so get related_items, delete, then update the similarity of those related_items
    items = related_items(item)
    input_matrices[matrix].delete_item(item)
    items.each { |related_item| cache_similarity(item, related_item) }
    return self
  end

  def delete_item!(item)
    Predictor.redis.srem(redis_key(:all_items), item)
    Predictor.redis.watch(redis_key(:similarities, item)) do
      items = related_items(item)
      Predictor.redis.multi do |multi|
        items.each do |related_item|
          multi.zrem(redis_key(:similarities, related_item), item)
        end
        multi.del redis_key(:similarities, item)
      end
    end

    input_matrices.each do |k,m|
      m.delete_item(item)
    end
    return self
  end

  def clean!
    keys = Predictor.redis.keys("#{self.redis_prefix}:*")
    unless keys.empty?
      Predictor.redis.del(keys)
    end
  end

  def ensure_similarity_limit_is_obeyed!
    if similarity_limit
      items = all_items
      Predictor.redis.multi do |multi|
        items.each do |item|
          key = redis_key(:similarities, item)
          multi.zremrangebyrank(key, 0, -(similarity_limit + 1))
          multi.zunionstore key, [key] # Rewrite zset to take advantage of ziplist implementation.
        end
      end
    end
  end

  private

  def cache_similarity(item1, item2)
    score = 0
    input_matrices.each do |key, matrix|
      score += (matrix.score(item1, item2) * matrix.weight)
    end
    if score > 0
      add_similarity_if_necessary(item1, item2, score)
      add_similarity_if_necessary(item2, item1, score)
    else
      Predictor.redis.multi do |multi|
        multi.zrem(redis_key(:similarities, item1), item2)
        multi.zrem(redis_key(:similarities, item2), item1)
      end
    end
  end

  def add_similarity_if_necessary(item, similarity, score)
    store = true
    key = redis_key(:similarities, item)
    if similarity_limit
      if Predictor.redis.zrank(key, similarity).nil? && Predictor.redis.zcard(key) >= similarity_limit
        # Similarity is not already stored and we are at limit of similarities
        lowest_scored_item = Predictor.redis.zrangebyscore(key, "0", "+inf", limit: [0, 1], with_scores: true)
        unless lowest_scored_item.empty?
          # If score is less than or equal to the lowest score, don't store it. Otherwise, make room by removing the lowest scored similarity
          score <= lowest_scored_item[0][1] ? store = false : Predictor.redis.zrem(key, lowest_scored_item[0][0])
        end
      end
    end
    Predictor.redis.zadd(key, score, similarity) if store
  end
end
