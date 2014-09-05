require 'spec_helper'

describe Predictor::Base do
  before(:each) do
    flush_redis!
    BaseRecommender.input_matrices = {}
    BaseRecommender.reset_similarity_limit!
    BaseRecommender.redis_prefix(nil)
    UserRecommender.input_matrices = {}
    UserRecommender.reset_similarity_limit!
    BaseRecommender.processing_technique nil
    UserRecommender.processing_technique nil
    Predictor.processing_technique nil
  end

  describe "configuration" do
    it "should add an input_matrix by 'key'" do
      BaseRecommender.input_matrix(:myinput)
      expect(BaseRecommender.input_matrices.keys).to eq([:myinput])
    end

    it "should default the similarity_limit to 128" do
      expect(BaseRecommender.similarity_limit).to eq(128)
    end

    it "should allow the similarity limit to be configured" do
      BaseRecommender.limit_similarities_to(500)
      expect(BaseRecommender.similarity_limit).to eq(500)
    end

    it "should allow the similarity limit to be removed" do
      BaseRecommender.limit_similarities_to(nil)
      expect(BaseRecommender.similarity_limit).to eq(nil)
    end

    it "should retrieve an input_matrix on a new instance" do
      BaseRecommender.input_matrix(:myinput)
      sm = BaseRecommender.new
      expect{ sm.myinput }.not_to raise_error
    end

    it "should retrieve an input_matrix on a new instance and correctly overload respond_to?" do
      BaseRecommender.input_matrix(:myinput)
      sm = BaseRecommender.new
      expect(sm.respond_to?(:process!)).to be_true
      expect(sm.respond_to?(:myinput)).to be_true
      expect(sm.respond_to?(:fnord)).to be_false
    end

    it "should retrieve an input_matrix on a new instance and intialize the correct class" do
      BaseRecommender.input_matrix(:myinput)
      sm = BaseRecommender.new
      expect(sm.myinput).to be_a(Predictor::InputMatrix)
    end

    it "should accept a custom processing_technique, or default to Predictor's default" do
      BaseRecommender.get_processing_technique.should == :ruby
      Predictor.processing_technique :lua
      BaseRecommender.get_processing_technique.should == :lua
      BaseRecommender.processing_technique :union
      BaseRecommender.get_processing_technique.should == :union
    end
  end

  describe "redis_key" do
    it "should vary based on the class name" do
      expect(BaseRecommender.new.redis_key).to eq('predictor-test:BaseRecommender')
      expect(UserRecommender.new.redis_key).to eq('predictor-test:UserRecommender')
    end
  end

  describe "redis_key" do
    it "should vary based on the class name" do
      expect(BaseRecommender.new.redis_key).to eq('predictor-test:BaseRecommender')
      expect(UserRecommender.new.redis_key).to eq('predictor-test:UserRecommender')
    end

    it "should be able to mimic the old naming defaults" do
      BaseRecommender.redis_prefix([nil])
      expect(BaseRecommender.new.redis_key(:key)).to eq('predictor-test:key')
    end

    it "should respect the Predictor prefix configuration setting" do
      br = BaseRecommender.new

      expect(br.redis_key).to eq("predictor-test:BaseRecommender")
      expect(br.redis_key(:another)).to eq("predictor-test:BaseRecommender:another")
      expect(br.redis_key(:another, :key)).to eq("predictor-test:BaseRecommender:another:key")
      expect(br.redis_key(:another, [:set, :of, :keys])).to eq("predictor-test:BaseRecommender:another:set:of:keys")

      i = 0
      Predictor.redis_prefix { i += 1 }
      expect(br.redis_key).to eq("1:BaseRecommender")
      expect(br.redis_key(:another)).to eq("2:BaseRecommender:another")
      expect(br.redis_key(:another, :key)).to eq("3:BaseRecommender:another:key")
      expect(br.redis_key(:another, [:set, :of, :keys])).to eq("4:BaseRecommender:another:set:of:keys")

      Predictor.redis_prefix nil
      expect(br.redis_key).to eq("predictor:BaseRecommender")
      expect(br.redis_key(:another)).to eq("predictor:BaseRecommender:another")
      expect(br.redis_key(:another, :key)).to eq("predictor:BaseRecommender:another:key")
      expect(br.redis_key(:another, [:set, :of, :keys])).to eq("predictor:BaseRecommender:another:set:of:keys")

      Predictor.redis_prefix [nil]
      expect(br.redis_key).to eq("BaseRecommender")
      expect(br.redis_key(:another)).to eq("BaseRecommender:another")
      expect(br.redis_key(:another, :key)).to eq("BaseRecommender:another:key")
      expect(br.redis_key(:another, [:set, :of, :keys])).to eq("BaseRecommender:another:set:of:keys")

      Predictor.redis_prefix { [1, 2, 3] }
      expect(br.redis_key).to eq("1:2:3:BaseRecommender")
      expect(br.redis_key(:another)).to eq("1:2:3:BaseRecommender:another")
      expect(br.redis_key(:another, :key)).to eq("1:2:3:BaseRecommender:another:key")
      expect(br.redis_key(:another, [:set, :of, :keys])).to eq("1:2:3:BaseRecommender:another:set:of:keys")

      Predictor.redis_prefix 'predictor-test'
      expect(br.redis_key).to eq("predictor-test:BaseRecommender")
      expect(br.redis_key(:another)).to eq("predictor-test:BaseRecommender:another")
      expect(br.redis_key(:another, :key)).to eq("predictor-test:BaseRecommender:another:key")
      expect(br.redis_key(:another, [:set, :of, :keys])).to eq("predictor-test:BaseRecommender:another:set:of:keys")
    end

    it "should respect the class prefix configuration setting" do
      br = BaseRecommender.new

      BaseRecommender.redis_prefix('base')
      expect(br.redis_key).to eq("predictor-test:base")
      expect(br.redis_key(:another)).to eq("predictor-test:base:another")
      expect(br.redis_key(:another, :key)).to eq("predictor-test:base:another:key")
      expect(br.redis_key(:another, [:set, :of, :keys])).to eq("predictor-test:base:another:set:of:keys")

      i = 0
      BaseRecommender.redis_prefix { i += 1 }
      expect(br.redis_key).to eq("predictor-test:1")
      expect(br.redis_key(:another)).to eq("predictor-test:2:another")
      expect(br.redis_key(:another, :key)).to eq("predictor-test:3:another:key")
      expect(br.redis_key(:another, [:set, :of, :keys])).to eq("predictor-test:4:another:set:of:keys")

      BaseRecommender.redis_prefix(nil)
      expect(br.redis_key).to eq("predictor-test:BaseRecommender")
      expect(br.redis_key(:another)).to eq("predictor-test:BaseRecommender:another")
      expect(br.redis_key(:another, :key)).to eq("predictor-test:BaseRecommender:another:key")
      expect(br.redis_key(:another, [:set, :of, :keys])).to eq("predictor-test:BaseRecommender:another:set:of:keys")
    end
  end

  describe "all_items" do
    it "returns all items across all matrices" do
      BaseRecommender.input_matrix(:anotherinput)
      BaseRecommender.input_matrix(:yetanotherinput)
      sm = BaseRecommender.new
      sm.add_to_matrix(:anotherinput, 'a', "foo", "bar")
      sm.add_to_matrix(:yetanotherinput, 'b', "fnord", "shmoo", "bar")
      expect(sm.all_items).to include('foo', 'bar', 'fnord', 'shmoo')
      expect(sm.all_items.length).to eq(4)
    end

    it "doesn't return items from other recommenders" do
      BaseRecommender.input_matrix(:anotherinput)
      BaseRecommender.input_matrix(:yetanotherinput)
      UserRecommender.input_matrix(:anotherinput)
      UserRecommender.input_matrix(:yetanotherinput)
      sm = BaseRecommender.new
      sm.add_to_matrix(:anotherinput, 'a', "foo", "bar")
      sm.add_to_matrix(:yetanotherinput, 'b', "fnord", "shmoo", "bar")
      expect(sm.all_items).to include('foo', 'bar', 'fnord', 'shmoo')
      expect(sm.all_items.length).to eq(4)

      ur = UserRecommender.new
      expect(ur.all_items).to eq([])
    end
  end

  describe "add_to_matrix" do
    it "calls add_to_set on the given matrix" do
      BaseRecommender.input_matrix(:anotherinput)
      sm = BaseRecommender.new
      expect(sm.anotherinput).to receive(:add_to_set).with('a', 'foo', 'bar')
      sm.add_to_matrix(:anotherinput, 'a', 'foo', 'bar')
    end

    it "adds the items to the all_items storage" do
      BaseRecommender.input_matrix(:anotherinput)
      sm = BaseRecommender.new
      sm.add_to_matrix(:anotherinput, 'a', 'foo', 'bar')
      expect(sm.all_items).to include('foo', 'bar')
    end
  end

  describe "add_to_matrix!" do
    it "calls add_to_matrix and process_items! for the given items" do
      BaseRecommender.input_matrix(:anotherinput)
      sm = BaseRecommender.new
      expect(sm).to receive(:add_to_matrix).with(:anotherinput, 'a', 'foo')
      expect(sm).to receive(:process_items!).with('foo')
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
      expect(sm.related_items("bar")).to include("foo", "fnord", "shmoo")
      expect(sm.related_items("bar").length).to eq(3)
    end
  end

  describe "predictions_for" do
    it "accepts an :on option to return scores of specific objects" do
      BaseRecommender.input_matrix(:users, weight: 4.0)
      BaseRecommender.input_matrix(:tags, weight: 1.0)
      sm = BaseRecommender.new
      sm.users.add_to_set('me', "foo", "bar", "fnord")
      sm.users.add_to_set('not_me', "foo", "shmoo")
      sm.users.add_to_set('another', "fnord", "other")
      sm.users.add_to_set('another', "nada")
      sm.tags.add_to_set('tag1', "foo", "fnord", "shmoo")
      sm.tags.add_to_set('tag2', "bar", "shmoo", "other")
      sm.tags.add_to_set('tag3', "shmoo", "nada")
      sm.process!
      predictions = sm.predictions_for('me', matrix_label: :users, on: 'other', with_scores: true)
      expect(predictions).to eq([['other', 3.0]])
      predictions = sm.predictions_for('me', matrix_label: :users, on: ['other'], with_scores: true)
      expect(predictions).to eq([['other', 3.0]])
      predictions = sm.predictions_for('me', matrix_label: :users, on: ['other', 'nada'], with_scores: true)
      expect(predictions).to eq([['other', 3.0], ['nada', 2.0]])
      predictions = sm.predictions_for(item_set: ["foo", "bar", "fnord"], on: ['other', 'nada'], with_scores: true)
      expect(predictions).to eq([['other', 3.0], ['nada', 2.0]])
      predictions = sm.predictions_for(item_set: ["foo", "bar", "fnord"], on: ['other', 'nada'])
      expect(predictions).to eq(['other', 'nada'])
      predictions = sm.predictions_for('me', matrix_label: :users, on: ['shmoo', 'other', 'nada'], offset: 1, limit: 1, with_scores: true)
      expect(predictions).to eq([["other", 3.0]])
      predictions = sm.predictions_for('me', matrix_label: :users, on: ['shmoo', 'other', 'nada'], offset: 1, with_scores: true)
      expect(predictions).to eq([['other', 3.0], ['nada', 2.0]])
    end
  end

  [:ruby, :lua, :union].each do |technique|
    describe "predictions_for with #{technique} processing" do
      before do
        Predictor.processing_technique(technique)
      end

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
        expect(predictions).to eq(["shmoo", "other", "nada"])
        predictions = sm.predictions_for(item_set: ["foo", "bar", "fnord"])
        expect(predictions).to eq(["shmoo", "other", "nada"])
        predictions = sm.predictions_for('me', matrix_label: :users, offset: 1, limit: 1)
        expect(predictions).to eq(["other"])
        predictions = sm.predictions_for('me', matrix_label: :users, offset: 1)
        expect(predictions).to eq(["other", "nada"])
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
        expect(predictions).to eq(["shmoo", "nada", "other"])
        predictions = sm.predictions_for(item_set: ["foo", "bar", "fnord"], boost: {tags: ['tag3']})
        expect(predictions).to eq(["shmoo", "nada", "other"])
        predictions = sm.predictions_for('me', matrix_label: :users, offset: 1, limit: 1, boost: {tags: ['tag3']})
        expect(predictions).to eq(["nada"])
        predictions = sm.predictions_for('me', matrix_label: :users, offset: 1, boost: {tags: ['tag3']})
        expect(predictions).to eq(["nada", "other"])

        # Syntax #2: Weights explicitly set.
        predictions = sm.predictions_for('me', matrix_label: :users, boost: {tags: {values: ['tag3'], weight: 1.0}})
        expect(predictions).to eq(["shmoo", "nada", "other"])
        predictions = sm.predictions_for(item_set: ["foo", "bar", "fnord"], boost: {tags: {values: ['tag3'], weight: 1.0}})
        expect(predictions).to eq(["shmoo", "nada", "other"])
        predictions = sm.predictions_for('me', matrix_label: :users, offset: 1, limit: 1, boost: {tags: {values: ['tag3'], weight: 1.0}})
        expect(predictions).to eq(["nada"])
        predictions = sm.predictions_for('me', matrix_label: :users, offset: 1, boost: {tags: {values: ['tag3'], weight: 1.0}})
        expect(predictions).to eq(["nada", "other"])

        # Make sure weights are actually being passed to Redis.
        shmoo, nada, other = sm.predictions_for('me', matrix_label: :users, boost: {tags: {values: ['tag3'], weight: 10000.0}}, with_scores: true)
        expect(shmoo[0]).to eq('shmoo')
        expect(shmoo[1]).to be > 10000
        expect(nada[0]).to eq('nada')
        expect(nada[1]).to be > 10000
        expect(other[0]).to eq('other')
        expect(other[1]).to be < 10
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
        expect(predictions).to eq(["shmoo", "nada"])
        predictions = sm.predictions_for(item_set: [], boost: {tags: ['tag3']})
        expect(predictions).to eq(["shmoo", "nada"])
        predictions = sm.predictions_for('me', matrix_label: :users, offset: 1, limit: 1, boost: {tags: ['tag3']})
        expect(predictions).to eq(["nada"])
        predictions = sm.predictions_for('me', matrix_label: :users, offset: 1, boost: {tags: ['tag3']})
        expect(predictions).to eq(["nada"])

        # Syntax #2: Weights explicitly set.
        predictions = sm.predictions_for('me', matrix_label: :users, boost: {tags: {values: ['tag3'], weight: 1.0}})
        expect(predictions).to eq(["shmoo", "nada"])
        predictions = sm.predictions_for(item_set: [], boost: {tags: {values: ['tag3'], weight: 1.0}})
        expect(predictions).to eq(["shmoo", "nada"])
        predictions = sm.predictions_for('me', matrix_label: :users, offset: 1, limit: 1, boost: {tags: {values: ['tag3'], weight: 1.0}})
        expect(predictions).to eq(["nada"])
        predictions = sm.predictions_for('me', matrix_label: :users, offset: 1, boost: {tags: {values: ['tag3'], weight: 1.0}})
        expect(predictions).to eq(["nada"])
      end
    end

    describe "process_items! with #{technique} processing" do
      before do
        Predictor.processing_technique(technique)
      end

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
          expect(sm.similarities_for('item2')).to be_empty
          sm.process_items!('item2')
          similarities = sm.similarities_for('item2')
          expect(similarities).to eq(["item3", "item1"])
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
          expect(sm.similarities_for('item2')).to be_empty
          sm.process_items!('item2')
          similarities = sm.similarities_for('item2')
          expect(similarities).to include("item3")
          expect(similarities.length).to eq(1)
        end
      end
    end
  end

  describe "similarities_for" do
    it "should not throw exception for non existing items" do
      sm = BaseRecommender.new
      expect(sm.similarities_for("not_existing_item").length).to eq(0)
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
      expect(sm.similarities_for("c1", with_scores: true)).to eq([["c4", 6.5], ["c2", 2.0]])
      expect(sm.similarities_for("c2", with_scores: true)).to eq([["c3", 4.0], ["c1", 2.0], ["c4", 1.5]])
      expect(sm.similarities_for("c3", with_scores: true)).to eq([["c2", 4.0], ["c4", 0.5]])
      expect(sm.similarities_for("c4", with_scores: true, exclusion_set: ["c3"])).to eq([["c1", 6.5], ["c2", 1.5]])
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
      expect(sm.sets_for("bar").length).to eq(3)
      expect(sm.sets_for("bar")).to include("item1", "item2", "item3")
      expect(sm.sets_for("other")).to eq(["item3"])
    end
  end

  describe "process!" do
    it "should call process_items for all_items's" do
      BaseRecommender.input_matrix(:anotherinput)
      BaseRecommender.input_matrix(:yetanotherinput)
      sm = BaseRecommender.new
      sm.anotherinput.add_to_set('a', "foo", "bar")
      sm.yetanotherinput.add_to_set('b', "fnord", "shmoo")
      expect(sm.all_items).to include("foo", "bar", "fnord", "shmoo")
      expect(sm).to receive(:process_items!).with(*sm.all_items)
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
      expect(sm.similarities_for('bar')).to include('foo', 'shmoo')
      expect(sm.anotherinput).to receive(:delete_item).with('foo')
      sm.delete_from_matrix!(:anotherinput, 'foo')
    end

    it "updates similarities" do
      BaseRecommender.input_matrix(:anotherinput)
      BaseRecommender.input_matrix(:yetanotherinput)
      sm = BaseRecommender.new
      sm.anotherinput.add_to_set('a', "foo", "bar")
      sm.yetanotherinput.add_to_set('b', "bar", "shmoo")
      sm.process!
      expect(sm.similarities_for('bar')).to include('foo', 'shmoo')
      sm.delete_from_matrix!(:anotherinput, 'foo')
      expect(sm.similarities_for('bar')).to eq(['shmoo'])
    end
  end

  describe "delete_item!" do
    it "should call delete_item on each input_matrix" do
      BaseRecommender.input_matrix(:myfirstinput)
      BaseRecommender.input_matrix(:mysecondinput)
      sm = BaseRecommender.new
      expect(sm.myfirstinput).to receive(:delete_item).with("fnorditem")
      expect(sm.mysecondinput).to receive(:delete_item).with("fnorditem")
      sm.delete_item!("fnorditem")
    end

    it "should remove the item from all_items" do
      BaseRecommender.input_matrix(:anotherinput)
      sm = BaseRecommender.new
      sm.anotherinput.add_to_set('a', "foo", "bar")
      sm.process!
      expect(sm.all_items).to include('foo')
      sm.delete_item!('foo')
      expect(sm.all_items).not_to include('foo')
    end

    it "should remove the item's similarities and also remove the item from related_items' similarities" do
      BaseRecommender.input_matrix(:anotherinput)
      BaseRecommender.input_matrix(:yetanotherinput)
      sm = BaseRecommender.new
      sm.anotherinput.add_to_set('a', "foo", "bar")
      sm.yetanotherinput.add_to_set('b', "bar", "shmoo")
      sm.process!
      expect(sm.similarities_for('bar')).to include('foo', 'shmoo')
      expect(sm.similarities_for('shmoo')).to include('bar')
      sm.delete_item!('shmoo')
      expect(sm.similarities_for('bar')).not_to include('shmoo')
      expect(sm.similarities_for('shmoo')).to be_empty
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

      expect(Predictor.redis.keys(sm.redis_key('*'))).not_to be_empty
      sm.clean!
      expect(Predictor.redis.keys(sm.redis_key('*'))).to be_empty
    end
  end

  describe "ensure_similarity_limit_is_obeyed!" do
    it "should shorten similarities to the given limit and rewrite the zset" do
      BaseRecommender.limit_similarities_to(nil)

      BaseRecommender.input_matrix(:myfirstinput)
      sm = BaseRecommender.new
      sm.myfirstinput.add_to_set *(['set1'] + 130.times.map{|i| "item#{i}"})
      expect(sm.similarities_for('item2')).to be_empty
      sm.process_items!('item2')
      expect(sm.similarities_for('item2').length).to eq(129)

      redis = Predictor.redis
      key = sm.redis_key(:similarities, 'item2')
      expect(redis.zcard(key)).to eq(129)
      expect(redis.object(:encoding, key)).to eq('skiplist') # Inefficient

      BaseRecommender.reset_similarity_limit!
      sm.ensure_similarity_limit_is_obeyed!

      expect(redis.zcard(key)).to eq(128)
      expect(redis.object(:encoding, key)).to eq('ziplist') # Efficient
    end
  end
end
