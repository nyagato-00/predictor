module Predictor
  class InputMatrix
    def initialize(opts)
      @opts = opts
    end

    def measure_name
      @opts.fetch(:measure, :jaccard_index)
    end

    def base
      @opts[:base]
    end

    def parent_redis_key(*append)
      base.redis_key(*append)
    end

    def redis_key(*append)
      base.redis_key(@opts.fetch(:key), *append)
    end

    def weight
      (@opts[:weight] || 1).to_f
    end

    def add_to_set(set, *items)
      items = items.flatten if items.count == 1 && items[0].is_a?(Array)
      if items.any?
        Predictor.redis.multi do |redis|
          redis.sadd(parent_redis_key(:all_items), items)
          redis.sadd(redis_key(:items, set), items)

          items.each do |item|
            # add the set to the item's set--inverting the sets
            redis.sadd(redis_key(:sets, item), set)
          end
        end
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

    def score(item1, item2)
      Distance.send(measure_name, redis_key(:sets, item1), redis_key(:sets, item2), Predictor.redis)
    end

    def calculate_jaccard(item1, item2)
      warn 'InputMatrix#calculate_jaccard is now deprecated. Use InputMatrix#score instead'
      Distance.jaccard_index(redis_key(:sets, item1), redis_key(:sets, item2), Predictor.redis)
    end
  end
end
