module Predictor::Base
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def input_matrix(key, opts={})
      @matrices ||= {}
      @matrices[key] = opts
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

    def redis_prefix(prefix = nil, &block)
      @redis_prefix = block_given? ? block : prefix
    end

    def get_redis_prefix
      if @redis_prefix
        if @redis_prefix.respond_to?(:call)
          @redis_prefix.call
        else
          @redis_prefix
        end
      else
        to_s
      end
    end

    def processing_technique(technique)
      @technique = technique
    end

    def get_processing_technique
      @technique || Predictor.get_processing_technique
    end
  end

  def input_matrices
    @input_matrices ||= Hash[self.class.input_matrices.map{ |key, opts|
      opts.merge!(:key => key, :base => self)
      [ key, Predictor::InputMatrix.new(opts) ]
    }]
  end

  def redis_prefix
    [Predictor.get_redis_prefix, self.class.get_redis_prefix]
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

  def respond_to?(method, include_all = false)
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

  def predictions_for(set=nil, item_set: nil, matrix_label: nil, with_scores: false, on: nil, offset: 0, limit: -1, exclusion_set: [], boost: {})
    fail "item_set or matrix_label and set is required" unless item_set || (matrix_label && set)

    on = Array(on)

    if matrix_label
      matrix = input_matrices[matrix_label]
      item_set = Predictor.redis.smembers(matrix.redis_key(:items, set))
    end

    item_keys = []
    weights   = []

    item_set.each do |item|
      item_keys << redis_key(:similarities, item)
      weights   << 1.0
    end

    boost.each do |matrix_label, values|
      m = input_matrices[matrix_label]

      # Passing plain sets to zunionstore is undocumented, but tested and supported:
      # https://github.com/antirez/redis/blob/2.8.11/tests/unit/type/zset.tcl#L481-L489

      case values
      when Hash
        values[:values].each do |value|
          item_keys << m.redis_key(:items, value)
          weights   << values[:weight]
        end
      when Array
        values.each do |value|
          item_keys << m.redis_key(:items, value)
          weights   << 1.0
        end
      else
        raise "Bad value for boost: #{boost.inspect}"
      end
    end

    return [] if item_keys.empty?

    predictions = nil

    Predictor.redis.multi do |multi|
      multi.zunionstore 'temp', item_keys, weights: weights
      multi.zrem 'temp', item_set if item_set.any?
      multi.zrem 'temp', exclusion_set if exclusion_set.length > 0

      if on.any?
        multi.zadd 'temp2', on.map{ |val| [0.0, val] }
        multi.zinterstore 'temp', ['temp', 'temp2']
        multi.del 'temp2'
      end

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
    items = items.flatten if items.count == 1 && items[0].is_a?(Array) # Old syntax

    case self.class.get_processing_technique
    when :lua
      matrix_data = {}
      input_matrices.each do |name, matrix|
        matrix_data[name] = {weight: matrix.weight, measure: matrix.measure_name}
      end
      matrix_json = JSON.dump(matrix_data)

      items.each do |item|
        Predictor.process_lua_script(redis_key, matrix_json, similarity_limit, item)
      end
    when :union
      items.each do |item|
        keys    = []
        weights = []

        input_matrices.each do |key, matrix|
          k = matrix.redis_key(:sets, item)
          item_keys = Predictor.redis.smembers(k).map { |set| matrix.redis_key(:items, set) }

          counts = Predictor.redis.multi do |multi|
            item_keys.each { |key| Predictor.redis.scard(key) }
          end

          item_keys.zip(counts).each do |key, count|
            unless count.zero?
              keys << key
              weights << matrix.weight / count
            end
          end
        end

        Predictor.redis.multi do |multi|
          key = redis_key(:similarities, item)
          multi.del(key)

          if keys.any?
            multi.zunionstore(key, keys, weights: weights)
            multi.zrem(key, item)
            multi.zremrangebyrank(key, 0, -(similarity_limit + 1))
            multi.zunionstore key, [key] # Rewrite zset for optimized storage.
          end
        end
      end
    else # Default to old behavior, processing things in Ruby.
      items.each do |item|
        related_items(item).each { |related_item| cache_similarity(item, related_item) }
      end
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
    keys = Predictor.redis.keys(redis_key('*'))
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
