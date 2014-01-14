module Recommendify::Base
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def input_matrix(key, opts={})
      @matrices ||= {}
      @matrices[key] = opts
    end

    def input_matrices=(val)
      @matrices = val
    end

    def input_matrices
      @matrices
    end
  end

  def input_matrices
    @input_matrices ||= Hash[self.class.input_matrices.map{ |key, opts|
      opts.merge!(:key => key, :redis_prefix => redis_prefix)
      [ key, Recommendify::InputMatrix.new(opts) ]
    }]
  end

  def redis_prefix
    "recommendify"
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
    Recommendify.redis.sunion input_matrices.map{|k,m| m.redis_key(:all_items)}
  end

  def item_score(item, normalize)
    if normalize
      similarities = similarities_for(item, with_scores: true)
      unless similarities.empty?
        similarities.map{|x,y| y}.reduce(:+)
      else
        1
      end
    else
      1
    end
  end

  def predictions_for(set_id=nil, item_set: nil, matrix_label: nil, with_scores: false, normalize: true, offset: 0, limit: -1)
    fail "item_set or matrix_label and set_id is required" unless item_set || (matrix_label && set_id)
    redis = Recommendify.redis

    if matrix_label
      matrix = input_matrices[matrix_label]
      item_set = redis.smembers(matrix.redis_key(:items, set_id))
    end

    item_keys = item_set.map do |item|
      input_matrices.map{ |k,m| m.redis_key(:similarities, item) }
    end.flatten

    item_weights = item_set.map do |item|
      score = item_score(item, normalize)
      input_matrices.map{|k, m| m.weight/score }
    end.flatten

    unless item_keys.empty?
      predictions = nil
      redis.multi do |multi|
        multi.zunionstore 'temp', item_keys, weights: item_weights
        multi.zrem 'temp', item_set
        predictions = multi.zrevrange 'temp', offset, limit == -1 ? limit : offset + (limit - 1), with_scores: with_scores
        multi.del 'temp'
      end
      return predictions.value
    else
      return []
    end
  end

  def similarities_for(item, with_scores: false, offset: 0, limit: -1)
    keys = input_matrices.map{ |k,m| m.redis_key(:similarities, item) }
    weights = input_matrices.map{ |k,m| m.weight }
    neighbors = nil
    unless keys.empty?
      Recommendify.redis.multi do |multi|
        multi.zunionstore 'temp', keys, weights: weights
        neighbors = multi.zrevrange('temp', offset, limit == -1 ? limit : offset + (limit - 1), with_scores: with_scores)
        multi.del 'temp'
      end
      return neighbors.value
    else
      return []
    end
  end

  def sets_for(item)
    keys = input_matrices.map{ |k,m| m.redis_key(:sets, item) }
    Recommendify.redis.sunion keys
  end

  def process!
    input_matrices.each do |k,m|
      m.process!
    end
    return self
  end

  def process_item!(item)
    input_matrices.each do |k,m|
      m.process_item!(item)
    end
    return self
  end

  def delete_item!(item_id)
    input_matrices.each do |k,m|
      m.delete_item!(item_id)
    end
    return self
  end
end