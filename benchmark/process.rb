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

    items = (1..100).map { |i| "item-#{i}" }
    users = (1..50).map  { |i| "user-#{i}" }
    parts = (1..50).map  { |i| "part-#{i}" }

    r = ItemRecommender.new

    start = Time.now
    users.each { |user| r.users.add_to_set user, *items.sample(20) }
    parts.each { |part| r.parts.add_to_set part, *items.sample(20) }
    elapsed = Time.now - start

    puts "add_to_set = #{elapsed.round(3)} seconds"

    start = Time.now
    r.process!
    elapsed = Time.now - start

    flush!

    puts "process! = #{elapsed.round(3)} seconds"
  end
end
