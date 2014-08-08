namespace :benchmark do
  task :process do
    require 'predictor'
    require 'pry'
    require 'logger'

    Predictor.redis = Redis.new #logger: Logger.new(STDOUT)
    Predictor.redis_prefix "predictor-benchmark"

    def flush!
      keys = Predictor.redis.keys("predictor-benchmark*")
      Predictor.redis.del(keys) if keys.any?
    end

    class ItemRecommender
      include Predictor::Base

      input_matrix :users, weight: 2.0
      input_matrix :parts, weight: 1.0
    end

    flush!

    items = (1..200).map { |i| "item-#{i}" }
    users = (1..100).map { |i| "user-#{i}" }
    parts = (1..100).map { |i| "part-#{i}" }

    r = ItemRecommender.new

    start = Time.now
    users.each { |user| r.users.add_to_set user, *items.sample(40) }
    parts.each { |part| r.parts.add_to_set part, *items.sample(40) }
    elapsed = Time.now - start

    puts "add_to_set = #{elapsed.round(3)} seconds"

    [:ruby, :lua, :union].each do |technique|
      start = Time.now
      Predictor.processing_technique technique
      r.process!
      elapsed = Time.now - start
      puts "#{technique} = #{elapsed.round(3)} seconds"
    end

    flush!
  end
end
