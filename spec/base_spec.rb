require ::File.expand_path('../spec_helper', __FILE__)

describe Predictor::Base do
  class BaseRecommender
    include Predictor::Base
  end

  before(:each) do
    flush_redis!
    BaseRecommender.input_matrices = {}
  end

  describe "configuration" do
    it "should add an input_matrix by 'key'" do
      BaseRecommender.input_matrix(:myinput)
      expect(BaseRecommender.input_matrices.keys).to eq([:myinput])
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
  end

  describe "process_item!" do
    it "should call process_item! on each input_matrix" do
      BaseRecommender.input_matrix(:myfirstinput)
      BaseRecommender.input_matrix(:mysecondinput)
      sm = BaseRecommender.new
      expect(sm.myfirstinput).to receive(:process_item!).with("fnorditem").and_return([["fooitem",0.5]])
      expect(sm.mysecondinput).to receive(:process_item!).with("fnorditem").and_return([["fooitem",0.5]])
      sm.process_item!("fnorditem")
    end

    it "should call process_item! on each input_matrix and add all outputs to the similarity matrix" do
      BaseRecommender.input_matrix(:myfirstinput)
      BaseRecommender.input_matrix(:mysecondinput)
      sm = BaseRecommender.new
      expect(sm.myfirstinput).to receive(:process_item!).and_return([["fooitem",0.5]])
      expect(sm.mysecondinput).to receive(:process_item!).and_return([["fooitem",0.75], ["baritem", 1.0]])
      sm.process_item!("fnorditem")
    end

    it "should call process_item! on each input_matrix and add all outputs to the similarity matrix with weight" do
      BaseRecommender.input_matrix(:myfirstinput, :weight => 4.0)
      BaseRecommender.input_matrix(:mysecondinput)
      sm = BaseRecommender.new
      expect(sm.myfirstinput).to receive(:process_item!).and_return([["fooitem",0.5]])
      expect(sm.mysecondinput).to receive(:process_item!).and_return([["fooitem",0.75], ["baritem", 1.0]])
      sm.process_item!("fnorditem")
    end
  end

  describe "all_items" do
    it "should retrieve all items from all input matrices" do
      BaseRecommender.input_matrix(:anotherinput)
      BaseRecommender.input_matrix(:yetanotherinput)
      sm = BaseRecommender.new
      sm.anotherinput.add_set('a', ["foo", "bar"])
      sm.yetanotherinput.add_set('b', ["fnord", "shmoo"])
      expect(sm.all_items.length).to eq(4)
      expect(sm.all_items).to include("foo", "bar", "fnord", "shmoo")
    end

    it "should retrieve all items from all input matrices (uniquely)" do
      BaseRecommender.input_matrix(:anotherinput)
      BaseRecommender.input_matrix(:yetanotherinput)
      sm = BaseRecommender.new
      sm.anotherinput.add_set('a', ["foo", "bar"])
      sm.yetanotherinput.add_set('b', ["fnord", "bar"])
      expect(sm.all_items.length).to eq(3)
      expect(sm.all_items).to include("foo", "bar", "fnord")
    end
  end

  describe "process!" do
    it "should call process_item for all input_matrix.all_items's" do
      BaseRecommender.input_matrix(:anotherinput)
      BaseRecommender.input_matrix(:yetanotherinput)
      sm = BaseRecommender.new
      sm.anotherinput.add_set('a', ["foo", "bar"])
      sm.yetanotherinput.add_set('b', ["fnord", "shmoo"])
      expect(sm.anotherinput).to receive(:process!).exactly(1).times
      expect(sm.yetanotherinput).to receive(:process!).exactly(1).times
      sm.process!
    end
  end

  describe "predictions_for" do
    it "returns relevant predictions" do
      BaseRecommender.input_matrix(:users, weight: 4.0)
      BaseRecommender.input_matrix(:tags, weight: 1.0)
      sm = BaseRecommender.new
      sm.users.add_set('me', ["foo", "bar", "fnord"])
      sm.users.add_set('not_me', ["foo", "shmoo"])
      sm.users.add_set('another', ["fnord", "other"])
      sm.users.add_set('another', ["nada"])
      sm.tags.add_set('tag1', ["foo", "fnord", "shmoo"])
      sm.tags.add_set('tag2', ["bar", "shmoo"])
      sm.tags.add_set('tag3', ["shmoo", "nada"])
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

    it "correctly normalizes predictions" do
      BaseRecommender.input_matrix(:users, weight: 1.0)
      BaseRecommender.input_matrix(:tags, weight: 2.0)
      BaseRecommender.input_matrix(:topics, weight: 4.0)

      sm = BaseRecommender.new

      sm.users.add_set('user1', ["c1", "c2", "c4"])
      sm.users.add_set('user2', ["c3", "c4"])
      sm.topics.add_set('topic1', ["c1", "c4"])
      sm.topics.add_set('topic2', ["c2", "c3"])
      sm.tags.add_set('tag1', ["c1", "c2", "c4"])
      sm.tags.add_set('tag2', ["c1", "c4"])

      sm.process!

      predictions = sm.predictions_for('user1', matrix_label: :users, with_scores: true, normalize: false)
      expect(predictions).to eq([["c3", 4.5]])
      predictions = sm.predictions_for('user2',  matrix_label: :users, with_scores: true, normalize: false)
      expect(predictions).to eq([["c1", 6.5], ["c2", 5.5]])
      predictions = sm.predictions_for('user1', matrix_label: :users, with_scores: true, normalize: true)
      expect(predictions[0][0]).to eq("c3")
      expect(predictions[0][1]).to be_within(0.001).of(0.592)
      predictions = sm.predictions_for('user2', matrix_label: :users, with_scores: true, normalize: true)
      expect(predictions[0][0]).to eq("c2")
      expect(predictions[0][1]).to be_within(0.001).of(1.065)
      expect(predictions[1][0]).to eq("c1")
      expect(predictions[1][1]).to be_within(0.001).of(0.764)
    end
  end

  describe "similarities_for(item_id)" do
    it "should not throw exception for non existing items" do
      sm = BaseRecommender.new
      expect(sm.similarities_for("not_existing_item").length).to eq(0)
    end

    it "correctly weighs and sums input matrices" do
      BaseRecommender.input_matrix(:users, weight: 1.0)
      BaseRecommender.input_matrix(:tags, weight: 2.0)
      BaseRecommender.input_matrix(:topics, weight: 4.0)

      sm = BaseRecommender.new

      sm.users.add_set('user1', ["c1", "c2", "c4"])
      sm.users.add_set('user2', ["c3", "c4"])
      sm.topics.add_set('topic1', ["c1", "c4"])
      sm.topics.add_set('topic2', ["c2", "c3"])
      sm.tags.add_set('tag1', ["c1", "c2", "c4"])
      sm.tags.add_set('tag2', ["c1", "c4"])

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
      sm.set1.add_set "item1", ["foo", "bar"]
      sm.set1.add_set "item2", ["nada", "bar"]
      sm.set2.add_set "item3", ["bar", "other"]
      expect(sm.sets_for("bar").length).to eq(3)
      expect(sm.sets_for("bar")).to include("item1", "item2", "item3")
      expect(sm.sets_for("other")).to eq(["item3"])
    end
  end

  describe "delete_item!" do
    it "should call delete_item on each input_matrix" do
      BaseRecommender.input_matrix(:myfirstinput)
      BaseRecommender.input_matrix(:mysecondinput)
      sm = BaseRecommender.new
      expect(sm.myfirstinput).to receive(:delete_item!).with("fnorditem")
      expect(sm.mysecondinput).to receive(:delete_item!).with("fnorditem")
      sm.delete_item!("fnorditem")
    end
  end

  describe "clean!" do
    it "should clean out the Redis storage for this Predictor" do
      BaseRecommender.input_matrix(:set1)
      BaseRecommender.input_matrix(:set2)
      sm = BaseRecommender.new
      sm.set1.add_set "item1", ["foo", "bar"]
      sm.set1.add_set "item2", ["nada", "bar"]
      sm.set2.add_set "item3", ["bar", "other"]
      expect(Predictor.redis.keys("#{sm.redis_prefix}:*")).not_to be_empty
      sm.clean!
      expect(Predictor.redis.keys("#{sm.redis_prefix}:*")).to be_empty
    end
  end
end
