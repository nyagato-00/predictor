class Predictor::InputMatrix
  def initialize(opts)
    @opts = opts
  end

  def parent_redis_key(*append)
    ([@opts.fetch(:redis_prefix)] + append).flatten.compact.join(":")
  end

  def redis_key(*append)
    ([@opts.fetch(:redis_prefix), @opts.fetch(:key)] + append).flatten.compact.join(":")
  end

  def weight
    (@opts[:weight] || 1).to_f
  end

  def add_to_set(set, *items)
    items = items.flatten if items.count == 1 && items[0].is_a?(Array)
    Predictor.redis.multi do
      items.each { |item| add_single_nomulti(set, item) }
    end
  end

  def add_set(set, items)
    add_to_set(set, *items)
  end

  def add_single(set, item)
    add_to_set(set, item)
  end

  def items_for(set)
    Predictor.redis.smembers redis_key(:items, set)
  end

  def sets_for(item)
    Predictor.redis.sunion redis_key(:sets, item)
  end

  def related_items(item)
    sets = Predictor.redis.smembers(redis_key(:sets, item))
    keys = sets.map { |set| redis_key(:items, set) }
    keys.length > 0 ? Predictor.redis.sunion(keys) - [item.to_s] : []
  end

  # delete item from the matrix
  def delete_item(item)
    Predictor.redis.watch(redis_key(:sets, item)) do
      sets = Predictor.redis.smembers(redis_key(:sets, item))
      Predictor.redis.multi do |multi|
        sets.each do |set|
          multi.srem(redis_key(:items, set), item)
        end

        multi.del redis_key(:sets, item)
      end
    end
  end

  def calculate_jaccard(item1, item2)
    x = nil
    y = nil
    Predictor.redis.multi do |multi|
      x = multi.sinterstore 'temp', [redis_key(:sets, item1), redis_key(:sets, item2)]
      y = multi.sunionstore 'temp', [redis_key(:sets, item1), redis_key(:sets, item2)]
      multi.del 'temp'
    end

    y.value > 0 ? (x.value.to_f/y.value.to_f) : 0.0
  end

  private

  def add_single_nomulti(set, item)
    Predictor.redis.sadd(parent_redis_key(:all_items), item)
    Predictor.redis.sadd(redis_key(:items, set), item)
    # add the set to the item's set--inverting the sets
    Predictor.redis.sadd(redis_key(:sets, item), set)
  end
end