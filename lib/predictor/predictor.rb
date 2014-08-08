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

  def self.processing_technique(algorithm)
    @technique = algorithm
  end

  def self.get_processing_technique
    @technique || :ruby
  end

  def self.process_lua_script(*args)
    @process_sha ||= redis.script(:load, PROCESS_ITEMS_LUA_SCRIPT)
    redis.evalsha(@process_sha, argv: args)
  end

  PROCESS_ITEMS_LUA_SCRIPT = <<-LUA
    local redis_prefix = ARGV[1]
    local input_matrices = cjson.decode(ARGV[2])
    local similarity_limit = tonumber(ARGV[3])
    local item = ARGV[4]
    local keys = {}

    for name, options in pairs(input_matrices) do
      local key = table.concat({redis_prefix, name, 'sets', item}, ':')
      local sets = redis.call('SMEMBERS', key)
      for _, set in ipairs(sets) do
        table.insert(keys, table.concat({redis_prefix, name, 'items', set}, ':'))
      end
    end

    -- Account for empty tables.
    if next(keys) == nil then
      return nil
    end

    local related_items = redis.call('SUNION', unpack(keys))

    local function add_similarity_if_necessary(item, similarity, score)
      local store = true
      local key = table.concat({redis_prefix, 'similarities', item}, ':')

      if similarity_limit ~= nil then
        local zrank = redis.call('ZRANK', key, similarity)

        if zrank ~= nil then
          local zcard = redis.call('ZCARD', key)

          if zcard >= similarity_limit then
            -- Similarity is not already stored and we are at limit of similarities.

            local lowest_scored_item = redis.call('ZRANGEBYSCORE', key, '0', '+inf', 'withscores', 'limit', 0, 1)

            if #lowest_scored_item > 0 then
              -- If score is less than or equal to the lowest score, don't store it. Otherwise, make room by removing the lowest scored similarity
              if score <= tonumber(lowest_scored_item[2]) then
                store = false
              else
                redis.call('ZREM', key, lowest_scored_item[1])
              end
            end
          end
        end
      end

      if store then
        redis.call('ZADD', key, score, similarity)
      end
    end

    for i, related_item in ipairs(related_items) do
      -- Disregard the current item.
      if related_item ~= item then
        local score = 0.0

        for name, matrix in pairs(input_matrices) do
          local s = 0.0

          local key_1 = table.concat({redis_prefix, name, 'sets', item}, ':')
          local key_2 = table.concat({redis_prefix, name, 'sets', related_item}, ':')

          if matrix.measure == 'jaccard_index' then
            local x = tonumber(redis.call('SINTERSTORE', 'temp', key_1, key_2))
            local y = tonumber(redis.call('SUNIONSTORE', 'temp', key_1, key_2))
            redis.call('DEL', 'temp')

            if y > 0 then
              s = s + (x / y)
            end
          elseif matrix.measure == 'sorensen_coefficient' then
            local x = redis.call('SINTERSTORE', 'temp', key_1, key_2)
            local y = redis.call('SCARD', key_1)
            local z = redis.call('SCARD', key_2)

            redis.call('DEL', 'temp')

            local denom = y + z
            if denom > 0 then
              s = s + (2 * x / denom)
            end
          else
            error("Bad matrix.measure: " .. matrix.measure)
          end

          score = score + (s * matrix.weight)
        end

        if score > 0 then
          add_similarity_if_necessary(item, related_item, score)
          add_similarity_if_necessary(related_item, item, score)
        else
          redis.call('ZREM', table.concat({redis_prefix, 'similarities', item}, ':'), related_item)
          redis.call('ZREM', table.concat({redis_prefix, 'similarities', related_item}, ':'), item)
        end
      end
    end
  LUA
end
