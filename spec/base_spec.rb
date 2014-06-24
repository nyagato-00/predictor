require 'spec_helper'

describe Predictor::Base do
  before(:each) do
    flush_redis!
    BaseRecommender.input_matrices = {}
    BaseRecommender.reset_similarity_limit!
    BaseRecommender.redis_prefix(nil)
    UserRecommender.input_matrices = {}
    UserRecommender.reset_similarity_limit!
  end

  describe "configuration" do
    it "should add an input_matrix by 'key'" do
      BaseRecommender.input_matrix(:myinput)
      BaseRecommender.input_matrices.keys.should == [:myinput]
    end

    it "should default the similarity_limit to 128" do
      BaseRecommender.similarity_limit.should == 128
    end

    it "should allow the similarity limit to be configured" do
      BaseRecommender.limit_similarities_to(500)
      BaseRecommender.similarity_limit.should == 500
    end

    it "should allow the similarity limit to be removed" do
      BaseRecommender.limit_similarities_to(nil)
      BaseRecommender.similarity_limit.should == nil
    end

    it "should retrieve an input_matrix on a new instance" do
      BaseRecommender.input_matrix(:myinput)
      sm = BaseRecommender.new
      lambda{ sm.myinput }.should_not raise_error
    end

    it "should retrieve an input_matrix on a new instance and correctly overload respond_to?" do
      BaseRecommender.input_matrix(:myinput)
      sm = BaseRecommender.new
      sm.respond_to?(:process!).should be_true
      sm.respond_to?(:myinput).should be_true
      sm.respond_to?(:fnord).should be_false
    end

    it "should retrieve an input_matrix on a new instance and intialize the correct class" do
      BaseRecommender.input_matrix(:myinput)
      sm = BaseRecommender.new
      sm.myinput.should be_a(Predictor::InputMatrix)
    end
  end

  describe "redis_key" do
    it "should vary based on the class name" do
      BaseRecommender.new.redis_key.should == 'predictor-test:BaseRecommender'
      UserRecommender.new.redis_key.should == 'predictor-test:UserRecommender'
    end
  end

  describe "redis_key" do
    it "should vary based on the class name" do
      BaseRecommender.new.redis_key.should == 'predictor-test:BaseRecommender'
      UserRecommender.new.redis_key.should == 'predictor-test:UserRecommender'
    end

    it "should be able to mimic the old naming defaults" do
      BaseRecommender.redis_prefix([nil])
      BaseRecommender.new.redis_key(:key).should == 'predictor-test:key'
    end

    it "should respect the Predictor prefix configuration setting" do
      br = BaseRecommender.new

      br.redis_key.should == "predictor-test:BaseRecommender"
      br.redis_key(:another).should == "predictor-test:BaseRecommender:another"
      br.redis_key(:another, :key).should == "predictor-test:BaseRecommender:another:key"
      br.redis_key(:another, [:set, :of, :keys]).should == "predictor-test:BaseRecommender:another:set:of:keys"

      i = 0
      Predictor.redis_prefix { i += 1 }
      br.redis_key.should == "1:BaseRecommender"
      br.redis_key(:another).should == "2:BaseRecommender:another"
      br.redis_key(:another, :key).should == "3:BaseRecommender:another:key"
      br.redis_key(:another, [:set, :of, :keys]).should == "4:BaseRecommender:another:set:of:keys"

      Predictor.redis_prefix nil
      br.redis_key.should == "predictor:BaseRecommender"
      br.redis_key(:another).should == "predictor:BaseRecommender:another"
      br.redis_key(:another, :key).should == "predictor:BaseRecommender:another:key"
      br.redis_key(:another, [:set, :of, :keys]).should == "predictor:BaseRecommender:another:set:of:keys"

      Predictor.redis_prefix { [1, 2, 3] }
      br.redis_key.should == "1:2:3:BaseRecommender"
      br.redis_key(:another).should == "1:2:3:BaseRecommender:another"
      br.redis_key(:another, :key).should == "1:2:3:BaseRecommender:another:key"
      br.redis_key(:another, [:set, :of, :keys]).should == "1:2:3:BaseRecommender:another:set:of:keys"

      Predictor.redis_prefix 'predictor-test'
      br.redis_key.should == "predictor-test:BaseRecommender"
      br.redis_key(:another).should == "predictor-test:BaseRecommender:another"
      br.redis_key(:another, :key).should == "predictor-test:BaseRecommender:another:key"
      br.redis_key(:another, [:set, :of, :keys]).should == "predictor-test:BaseRecommender:another:set:of:keys"
    end

    it "should respect the class prefix configuration setting" do
      br = BaseRecommender.new

      BaseRecommender.redis_prefix('base')
      br.redis_key.should == "predictor-test:base"
      br.redis_key(:another).should == "predictor-test:base:another"
      br.redis_key(:another, :key).should == "predictor-test:base:another:key"
      br.redis_key(:another, [:set, :of, :keys]).should == "predictor-test:base:another:set:of:keys"

      i = 0
      BaseRecommender.redis_prefix { i += 1 }
      br.redis_key.should == "predictor-test:1"
      br.redis_key(:another).should == "predictor-test:2:another"
      br.redis_key(:another, :key).should == "predictor-test:3:another:key"
      br.redis_key(:another, [:set, :of, :keys]).should == "predictor-test:4:another:set:of:keys"

      BaseRecommender.redis_prefix(nil)
      br.redis_key.should == "predictor-test:BaseRecommender"
      br.redis_key(:another).should == "predictor-test:BaseRecommender:another"
      br.redis_key(:another, :key).should == "predictor-test:BaseRecommender:another:key"
      br.redis_key(:another, [:set, :of, :keys]).should == "predictor-test:BaseRecommender:another:set:of:keys"
    end
  end

  describe "all_items" do
    it "returns all items across all matrices" do
      BaseRecommender.input_matrix(:anotherinput)
      BaseRecommender.input_matrix(:yetanotherinput)
      sm = BaseRecommender.new
      sm.add_to_matrix(:anotherinput, 'a', "foo", "bar")
      sm.add_to_matrix(:yetanotherinput, 'b', "fnord", "shmoo", "bar")
      sm.all_items.should include('foo', 'bar', 'fnord', 'shmoo')
      sm.all_items.length.should == 4
    end

    it "doesn't return items from other recommenders" do
      BaseRecommender.input_matrix(:anotherinput)
      BaseRecommender.input_matrix(:yetanotherinput)
      UserRecommender.input_matrix(:anotherinput)
      UserRecommender.input_matrix(:yetanotherinput)
      sm = BaseRecommender.new
      sm.add_to_matrix(:anotherinput, 'a', "foo", "bar")
      sm.add_to_matrix(:yetanotherinput, 'b', "fnord", "shmoo", "bar")
      sm.all_items.should include('foo', 'bar', 'fnord', 'shmoo')
      sm.all_items.length.should == 4

      ur = UserRecommender.new
      ur.all_items.should == []
    end
  end

  describe "add_to_matrix" do
    it "calls add_to_set on the given matrix" do
      BaseRecommender.input_matrix(:anotherinput)
      sm = BaseRecommender.new
      sm.anotherinput.should_receive(:add_to_set).with('a', 'foo', 'bar')
      sm.add_to_matrix(:anotherinput, 'a', 'foo', 'bar')
    end

    it "adds the items to the all_items storage" do
      BaseRecommender.input_matrix(:anotherinput)
      sm = BaseRecommender.new
      sm.add_to_matrix(:anotherinput, 'a', 'foo', 'bar')
      sm.all_items.should include('foo', 'bar')
    end
  end

  describe "add_to_matrix!" do
    it "calls add_to_matrix and process_items! for the given items" do
      BaseRecommender.input_matrix(:anotherinput)
      sm = BaseRecommender.new
      sm.should_receive(:add_to_matrix).with(:anotherinput, 'a', 'foo')
      sm.should_receive(:process_items!).with('foo')
      sm.add_to_matrix!(:anotherinput, 'a', 'foo')
    end
  end

  describe "related_items" do
    it "returns items in the sets across all matrices that the given item is also in" do
      BaseRecommender.input_matrix(:anotherinput)
      BaseRecommender.input_matrix(:yetanotherinput)
      BaseRecommender.input_matrix(:finalinput)
      sm = BaseRecommender.new
      sm.anotherinput.add_to_set('a', "foo", "bar")
      sm.yetanotherinput.add_to_set('b', "fnord", "shmoo", "bar")
      sm.finalinput.add_to_set('c', "nada")
      sm.process!
      sm.related_items("bar").should include("foo", "fnord", "shmoo")
      sm.related_items("bar").length.should == 3
    end
  end

  describe "predictions_for" do
    it "returns relevant predictions" do
      BaseRecommender.input_matrix(:users, weight: 4.0)
      BaseRecommender.input_matrix(:tags, weight: 1.0)
      sm = BaseRecommender.new
      sm.users.add_to_set('me', "foo", "bar", "fnord")
      sm.users.add_to_set('not_me', "foo", "shmoo")
      sm.users.add_to_set('another', "fnord", "other")
      sm.users.add_to_set('another', "nada")
      sm.tags.add_to_set('tag1', "foo", "fnord", "shmoo")
      sm.tags.add_to_set('tag2', "bar", "shmoo")
      sm.tags.add_to_set('tag3', "shmoo", "nada")
      sm.process!
      predictions = sm.predictions_for('me', matrix_label: :users)
      predictions.should == ["shmoo", "other", "nada"]
      predictions = sm.predictions_for(item_set: ["foo", "bar", "fnord"])
      predictions.should == ["shmoo", "other", "nada"]
      predictions = sm.predictions_for('me', matrix_label: :users, offset: 1, limit: 1)
      predictions.should == ["other"]
      predictions = sm.predictions_for('me', matrix_label: :users, offset: 1)
      predictions.should == ["other", "nada"]
    end

    it "accepts a :boost option" do
      BaseRecommender.input_matrix(:users, weight: 4.0)
      BaseRecommender.input_matrix(:tags, weight: 1.0)
      sm = BaseRecommender.new
      sm.users.add_to_set('me', "foo", "bar", "fnord")
      sm.users.add_to_set('not_me', "foo", "shmoo")
      sm.users.add_to_set('another', "fnord", "other")
      sm.users.add_to_set('another', "nada")
      sm.tags.add_to_set('tag1', "foo", "fnord", "shmoo")
      sm.tags.add_to_set('tag2', "bar", "shmoo")
      sm.tags.add_to_set('tag3', "shmoo", "nada")
      sm.process!

      # Syntax #1: Tags passed as array, weights assumed to be 1.0
      predictions = sm.predictions_for('me', matrix_label: :users, boost: {tags: ['tag3']})
      predictions.should == ["shmoo", "nada", "other"]
      predictions = sm.predictions_for(item_set: ["foo", "bar", "fnord"], boost: {tags: ['tag3']})
      predictions.should == ["shmoo", "nada", "other"]
      predictions = sm.predictions_for('me', matrix_label: :users, offset: 1, limit: 1, boost: {tags: ['tag3']})
      predictions.should == ["nada"]
      predictions = sm.predictions_for('me', matrix_label: :users, offset: 1, boost: {tags: ['tag3']})
      predictions.should == ["nada", "other"]

      # Syntax #2: Weights explicitly set.
      predictions = sm.predictions_for('me', matrix_label: :users, boost: {tags: {values: ['tag3'], weight: 1.0}})
      predictions.should == ["shmoo", "nada", "other"]
      predictions = sm.predictions_for(item_set: ["foo", "bar", "fnord"], boost: {tags: {values: ['tag3'], weight: 1.0}})
      predictions.should == ["shmoo", "nada", "other"]
      predictions = sm.predictions_for('me', matrix_label: :users, offset: 1, limit: 1, boost: {tags: {values: ['tag3'], weight: 1.0}})
      predictions.should == ["nada"]
      predictions = sm.predictions_for('me', matrix_label: :users, offset: 1, boost: {tags: {values: ['tag3'], weight: 1.0}})
      predictions.should == ["nada", "other"]

      # Make sure weights are actually being passed to Redis.
      shmoo, nada, other = sm.predictions_for('me', matrix_label: :users, boost: {tags: {values: ['tag3'], weight: 10000.0}}, with_scores: true)
      shmoo[0].should == 'shmoo'
      shmoo[1].should > 10000
      nada[0].should == 'nada'
      nada[1].should > 10000
      other[0].should == 'other'
      other[1].should < 10
    end

    it "accepts a :boost option, even with an empty item set" do
      BaseRecommender.input_matrix(:users, weight: 4.0)
      BaseRecommender.input_matrix(:tags, weight: 1.0)
      sm = BaseRecommender.new
      sm.users.add_to_set('not_me', "foo", "shmoo")
      sm.users.add_to_set('another', "fnord", "other")
      sm.users.add_to_set('another', "nada")
      sm.tags.add_to_set('tag1', "foo", "fnord", "shmoo")
      sm.tags.add_to_set('tag2', "bar", "shmoo")
      sm.tags.add_to_set('tag3', "shmoo", "nada")
      sm.process!

      # Syntax #1: Tags passed as array, weights assumed to be 1.0
      predictions = sm.predictions_for('me', matrix_label: :users, boost: {tags: ['tag3']})
      predictions.should == ["shmoo", "nada"]
      predictions = sm.predictions_for(item_set: [], boost: {tags: ['tag3']})
      predictions.should == ["shmoo", "nada"]
      predictions = sm.predictions_for('me', matrix_label: :users, offset: 1, limit: 1, boost: {tags: ['tag3']})
      predictions.should == ["nada"]
      predictions = sm.predictions_for('me', matrix_label: :users, offset: 1, boost: {tags: ['tag3']})
      predictions.should == ["nada"]

      # Syntax #2: Weights explicitly set.
      predictions = sm.predictions_for('me', matrix_label: :users, boost: {tags: {values: ['tag3'], weight: 1.0}})
      predictions.should == ["shmoo", "nada"]
      predictions = sm.predictions_for(item_set: [], boost: {tags: {values: ['tag3'], weight: 1.0}})
      predictions.should == ["shmoo", "nada"]
      predictions = sm.predictions_for('me', matrix_label: :users, offset: 1, limit: 1, boost: {tags: {values: ['tag3'], weight: 1.0}})
      predictions.should == ["nada"]
      predictions = sm.predictions_for('me', matrix_label: :users, offset: 1, boost: {tags: {values: ['tag3'], weight: 1.0}})
      predictions.should == ["nada"]
    end
  end

  describe "similarities_for" do
    it "should not throw exception for non existing items" do
      sm = BaseRecommender.new
      sm.similarities_for("not_existing_item").length.should == 0
    end

    it "correctly weighs and sums input matrices" do
      BaseRecommender.input_matrix(:users, weight: 1.0)
      BaseRecommender.input_matrix(:tags, weight: 2.0)
      BaseRecommender.input_matrix(:topics, weight: 4.0)

      sm = BaseRecommender.new

      sm.users.add_to_set('user1', "c1", "c2", "c4")
      sm.users.add_to_set('user2', "c3", "c4")
      sm.topics.add_to_set('topic1', "c1", "c4")
      sm.topics.add_to_set('topic2', "c2", "c3")
      sm.tags.add_to_set('tag1', "c1", "c2", "c4")
      sm.tags.add_to_set('tag2', "c1", "c4")

      sm.process!
      sm.similarities_for("c1", with_scores: true).should eq([["c4", 6.5], ["c2", 2.0]])
      sm.similarities_for("c2", with_scores: true).should eq([["c3", 4.0], ["c1", 2.0], ["c4", 1.5]])
      sm.similarities_for("c3", with_scores: true).should eq([["c2", 4.0], ["c4", 0.5]])
      sm.similarities_for("c4", with_scores: true, exclusion_set: ["c3"]).should eq([["c1", 6.5], ["c2", 1.5]])
    end
  end

  describe "sets_for" do
    it "should return all the sets the given item is in" do
      BaseRecommender.input_matrix(:set1)
      BaseRecommender.input_matrix(:set2)
      sm = BaseRecommender.new
      sm.set1.add_to_set "item1", "foo", "bar"
      sm.set1.add_to_set "item2", "nada", "bar"
      sm.set2.add_to_set "item3", "bar", "other"
      sm.sets_for("bar").length.should == 3
      sm.sets_for("bar").should include("item1", "item2", "item3")
      sm.sets_for("other").should == ["item3"]
    end
  end

  describe "process_items!" do
    context "with no similarity_limit" do
      it "calculates the similarity between the item and all related_items (other items in a set the given item is in)" do
        BaseRecommender.input_matrix(:myfirstinput)
        BaseRecommender.input_matrix(:mysecondinput)
        BaseRecommender.input_matrix(:mythirdinput, weight: 3.0)
        sm = BaseRecommender.new
        sm.myfirstinput.add_to_set 'set1', 'item1', 'item2'
        sm.mysecondinput.add_to_set 'set2', 'item2', 'item3'
        sm.mythirdinput.add_to_set 'set3', 'item2', 'item3'
        sm.mythirdinput.add_to_set 'set4', 'item1', 'item2', 'item3'
        sm.similarities_for('item2').should be_empty
        sm.process_items!('item2')
        similarities = sm.similarities_for('item2', with_scores: true)
        similarities.should include(["item3", 4.0], ["item1", 2.5])
      end
    end

    context "with a similarity_limit" do
      it "calculates the similarity between the item and all related_items (other items in a set the given item is in), but obeys the similarity_limit" do
        BaseRecommender.input_matrix(:myfirstinput)
        BaseRecommender.input_matrix(:mysecondinput)
        BaseRecommender.input_matrix(:mythirdinput, weight: 3.0)
        BaseRecommender.limit_similarities_to(1)
        sm = BaseRecommender.new
        sm.myfirstinput.add_to_set 'set1', 'item1', 'item2'
        sm.mysecondinput.add_to_set 'set2', 'item2', 'item3'
        sm.mythirdinput.add_to_set 'set3', 'item2', 'item3'
        sm.mythirdinput.add_to_set 'set4', 'item1', 'item2', 'item3'
        sm.similarities_for('item2').should be_empty
        sm.process_items!('item2')
        similarities = sm.similarities_for('item2', with_scores: true)
        similarities.should include(["item3", 4.0])
        similarities.length.should == 1
      end
    end
  end

  describe "process!" do
    it "should call process_items for all_items's" do
      BaseRecommender.input_matrix(:anotherinput)
      BaseRecommender.input_matrix(:yetanotherinput)
      sm = BaseRecommender.new
      sm.anotherinput.add_to_set('a', "foo", "bar")
      sm.yetanotherinput.add_to_set('b', "fnord", "shmoo")
      sm.all_items.should include("foo", "bar", "fnord", "shmoo")
      sm.should_receive(:process_items!).with(*sm.all_items)
      sm.process!
    end
  end

  describe "delete_from_matrix!" do
    it "calls delete_item on the matrix" do
      BaseRecommender.input_matrix(:anotherinput)
      BaseRecommender.input_matrix(:yetanotherinput)
      sm = BaseRecommender.new
      sm.anotherinput.add_to_set('a', "foo", "bar")
      sm.yetanotherinput.add_to_set('b', "bar", "shmoo")
      sm.process!
      sm.similarities_for('bar').should include('foo', 'shmoo')
      sm.anotherinput.should_receive(:delete_item).with('foo')
      sm.delete_from_matrix!(:anotherinput, 'foo')
    end

    it "updates similarities" do
      BaseRecommender.input_matrix(:anotherinput)
      BaseRecommender.input_matrix(:yetanotherinput)
      sm = BaseRecommender.new
      sm.anotherinput.add_to_set('a', "foo", "bar")
      sm.yetanotherinput.add_to_set('b', "bar", "shmoo")
      sm.process!
      sm.similarities_for('bar').should include('foo', 'shmoo')
      sm.delete_from_matrix!(:anotherinput, 'foo')
      sm.similarities_for('bar').should == ['shmoo']
    end
  end

  describe "delete_item!" do
    it "should call delete_item on each input_matrix" do
      BaseRecommender.input_matrix(:myfirstinput)
      BaseRecommender.input_matrix(:mysecondinput)
      sm = BaseRecommender.new
      sm.myfirstinput.should_receive(:delete_item).with("fnorditem")
      sm.mysecondinput.should_receive(:delete_item).with("fnorditem")
      sm.delete_item!("fnorditem")
    end

    it "should remove the item from all_items" do
      BaseRecommender.input_matrix(:anotherinput)
      sm = BaseRecommender.new
      sm.anotherinput.add_to_set('a', "foo", "bar")
      sm.process!
      sm.all_items.should include('foo')
      sm.delete_item!('foo')
      sm.all_items.should_not include('foo')
    end

    it "should remove the item's similarities and also remove the item from related_items' similarities" do
      BaseRecommender.input_matrix(:anotherinput)
      BaseRecommender.input_matrix(:yetanotherinput)
      sm = BaseRecommender.new
      sm.anotherinput.add_to_set('a', "foo", "bar")
      sm.yetanotherinput.add_to_set('b', "bar", "shmoo")
      sm.process!
      sm.similarities_for('bar').should include('foo', 'shmoo')
      sm.similarities_for('shmoo').should include('bar')
      sm.delete_item!('shmoo')
      sm.similarities_for('bar').should_not include('shmoo')
      sm.similarities_for('shmoo').should be_empty
    end
  end

  describe "clean!" do
    it "should clean out the Redis storage for this Predictor" do
      BaseRecommender.input_matrix(:set1)
      BaseRecommender.input_matrix(:set2)
      sm = BaseRecommender.new
      sm.set1.add_to_set "item1", "foo", "bar"
      sm.set1.add_to_set "item2", "nada", "bar"
      sm.set2.add_to_set "item3", "bar", "other"

      Predictor.redis.keys(sm.redis_key('*')).should_not be_empty
      sm.clean!
      Predictor.redis.keys(sm.redis_key('*')).should be_empty
    end
  end

  describe "ensure_similarity_limit_is_obeyed!" do
    it "should shorten similarities to the given limit and rewrite the zset" do
      BaseRecommender.limit_similarities_to(nil)

      BaseRecommender.input_matrix(:myfirstinput)
      sm = BaseRecommender.new
      sm.myfirstinput.add_to_set *(['set1'] + 130.times.map{|i| "item#{i}"})
      sm.similarities_for('item2').should be_empty
      sm.process_items!('item2')
      sm.similarities_for('item2').length.should == 129

      redis = Predictor.redis
      key = sm.redis_key(:similarities, 'item2')
      redis.zcard(key).should == 129
      redis.object(:encoding, key).should == 'skiplist' # Inefficient

      BaseRecommender.reset_similarity_limit!
      sm.ensure_similarity_limit_is_obeyed!

      redis.zcard(key).should == 128
      redis.object(:encoding, key).should == 'ziplist' # Efficient
    end
  end
end
