require 'spec_helper'

describe Predictor::InputMatrix do
  let(:options) { @default_options.merge(@options) }

  before(:each) { @options = {} }

  before(:all) do
    @base = BaseRecommender.new
    @default_options = { base: @base, key: "mymatrix" }
    @matrix = Predictor::InputMatrix.new(@default_options)
  end

  before(:each) do
    flush_redis!
  end

  describe "redis_key" do
    it "should respect the global namespace configuration" do
      @matrix.redis_key.should == "predictor-test:BaseRecommender:mymatrix"
      @matrix.redis_key(:another).should == "predictor-test:BaseRecommender:mymatrix:another"
      @matrix.redis_key(:another, :key).should == "predictor-test:BaseRecommender:mymatrix:another:key"
      @matrix.redis_key(:another, [:set, :of, :keys]).should == "predictor-test:BaseRecommender:mymatrix:another:set:of:keys"

      i = 0
      Predictor.redis_prefix { i += 1 }
      @matrix.redis_key.should == "1:BaseRecommender:mymatrix"
      @matrix.redis_key(:another).should == "2:BaseRecommender:mymatrix:another"
      @matrix.redis_key(:another, :key).should == "3:BaseRecommender:mymatrix:another:key"
      @matrix.redis_key(:another, [:set, :of, :keys]).should == "4:BaseRecommender:mymatrix:another:set:of:keys"

      Predictor.redis_prefix(nil)
      @matrix.redis_key.should == "predictor:BaseRecommender:mymatrix"
      @matrix.redis_key(:another).should == "predictor:BaseRecommender:mymatrix:another"
      @matrix.redis_key(:another, :key).should == "predictor:BaseRecommender:mymatrix:another:key"
      @matrix.redis_key(:another, [:set, :of, :keys]).should == "predictor:BaseRecommender:mymatrix:another:set:of:keys"

      Predictor.redis_prefix('predictor-test')
      @matrix.redis_key.should == "predictor-test:BaseRecommender:mymatrix"
      @matrix.redis_key(:another).should == "predictor-test:BaseRecommender:mymatrix:another"
      @matrix.redis_key(:another, :key).should == "predictor-test:BaseRecommender:mymatrix:another:key"
      @matrix.redis_key(:another, [:set, :of, :keys]).should == "predictor-test:BaseRecommender:mymatrix:another:set:of:keys"
    end

    it "should respect the class-level configuration" do
      i = 0
      BaseRecommender.redis_prefix { i += 1 }
      @matrix.redis_key.should == "predictor-test:1:mymatrix"
      @matrix.redis_key(:another).should == "predictor-test:2:mymatrix:another"
      @matrix.redis_key(:another, :key).should == "predictor-test:3:mymatrix:another:key"
      @matrix.redis_key(:another, [:set, :of, :keys]).should == "predictor-test:4:mymatrix:another:set:of:keys"

      BaseRecommender.redis_prefix([nil])
      @matrix.redis_key.should == "predictor-test:mymatrix"
      @matrix.redis_key(:another).should == "predictor-test:mymatrix:another"
      @matrix.redis_key(:another, :key).should == "predictor-test:mymatrix:another:key"
      @matrix.redis_key(:another, [:set, :of, :keys]).should == "predictor-test:mymatrix:another:set:of:keys"

      BaseRecommender.redis_prefix(['a', 'b'])
      @matrix.redis_key.should == "predictor-test:a:b:mymatrix"
      @matrix.redis_key(:another).should == "predictor-test:a:b:mymatrix:another"
      @matrix.redis_key(:another, :key).should == "predictor-test:a:b:mymatrix:another:key"
      @matrix.redis_key(:another, [:set, :of, :keys]).should == "predictor-test:a:b:mymatrix:another:set:of:keys"

      BaseRecommender.redis_prefix(nil)
      @matrix.redis_key.should == "predictor-test:BaseRecommender:mymatrix"
      @matrix.redis_key(:another).should == "predictor-test:BaseRecommender:mymatrix:another"
      @matrix.redis_key(:another, :key).should == "predictor-test:BaseRecommender:mymatrix:another:key"
      @matrix.redis_key(:another, [:set, :of, :keys]).should == "predictor-test:BaseRecommender:mymatrix:another:set:of:keys"
    end
  end

  describe "weight" do
    it "returns the weight configured or a default of 1" do
      expect(@matrix.weight).to eq(1.0)  # default weight
      matrix = Predictor::InputMatrix.new(redis_prefix: "predictor-test", key: "mymatrix", weight: 5.0)
      expect(matrix.weight).to eq(5.0)
    end
  end

  describe "add_to_set" do
    it "adds each member of the set to the key's 'sets' set" do
      expect(@matrix.items_for("item1")).not_to include("foo", "bar", "fnord", "blubb")
      @matrix.add_to_set "item1", "foo", "bar", "fnord", "blubb"
      expect(@matrix.items_for("item1")).to include("foo", "bar", "fnord", "blubb")
    end

    it "adds the key to each set member's 'items' set" do
      expect(@matrix.sets_for("foo")).not_to include("item1")
      expect(@matrix.sets_for("bar")).not_to include("item1")
      expect(@matrix.sets_for("fnord")).not_to include("item1")
      expect(@matrix.sets_for("blubb")).not_to include("item1")
      @matrix.add_to_set "item1", "foo", "bar", "fnord", "blubb"
      expect(@matrix.sets_for("foo")).to include("item1")
      expect(@matrix.sets_for("bar")).to include("item1")
      expect(@matrix.sets_for("fnord")).to include("item1")
      expect(@matrix.sets_for("blubb")).to include("item1")
    end
  end

  describe "items_for" do
    it "returns the items in the given set ID" do
      @matrix.add_to_set "item1", ["foo", "bar", "fnord", "blubb"]
      expect(@matrix.items_for("item1")).to include("foo", "bar", "fnord", "blubb")
      @matrix.add_to_set "item2", ["foo", "bar", "snafu", "nada"]
      expect(@matrix.items_for("item2")).to include("foo", "bar", "snafu", "nada")
      expect(@matrix.items_for("item1")).not_to include("snafu", "nada")
    end
  end

  describe "sets_for" do
    it "returns the set IDs the given item is in" do
      @matrix.add_to_set "item1", ["foo", "bar", "fnord", "blubb"]
      @matrix.add_to_set "item2", ["foo", "bar", "snafu", "nada"]
      expect(@matrix.sets_for("foo")).to include("item1", "item2")
      expect(@matrix.sets_for("snafu")).to eq(["item2"])
    end
  end

  describe "related_items" do
    it "returns the items in sets the given item is also in" do
      @matrix.add_to_set "item1", ["foo", "bar", "fnord", "blubb"]
      @matrix.add_to_set "item2", ["foo", "bar", "snafu", "nada"]
      @matrix.add_to_set "item3", ["nada", "other"]
      expect(@matrix.related_items("bar")).to include("foo", "fnord", "blubb", "snafu", "nada")
      expect(@matrix.related_items("bar").length).to eq(5)
      expect(@matrix.related_items("other")).to eq(["nada"])
      expect(@matrix.related_items("snafu")).to include("foo", "bar", "nada")
      expect(@matrix.related_items("snafu").length).to eq(3)
    end
  end

  describe "delete_item" do
    before do
      @matrix.add_to_set "item1", "foo", "bar", "fnord", "blubb"
      @matrix.add_to_set "item2", "foo", "bar", "snafu", "nada"
      @matrix.add_to_set "item3", "nada", "other"
    end

    it "should delete the item from sets it is in" do
      expect(@matrix.items_for("item1")).to include("bar")
      expect(@matrix.items_for("item2")).to include("bar")
      expect(@matrix.sets_for("bar")).to include("item1", "item2")
      @matrix.delete_item("bar")
      expect(@matrix.items_for("item1")).not_to include("bar")
      expect(@matrix.items_for("item2")).not_to include("bar")
      expect(@matrix.sets_for("bar")).to be_empty
    end
  end

  describe "#score" do
    let(:matrix) { Predictor::InputMatrix.new(options) }

    context "default" do
      it "scores as jaccard index by default" do
        matrix.add_to_set "item1", "foo", "bar", "fnord", "blubb"
        matrix.add_to_set "item2", "bar", "fnord", "shmoo", "snafu"
        matrix.add_to_set "item3", "bar", "nada", "snafu"

        expect(matrix.score("bar", "snafu")).to eq(2.0/3.0)
      end

      it "scores as jaccard index when given option" do
        matrix = Predictor::InputMatrix.new(options.merge(measure: :jaccard_index))
        matrix.add_to_set "item1", "foo", "bar", "fnord", "blubb"
        matrix.add_to_set "item2", "bar", "fnord", "shmoo", "snafu"
        matrix.add_to_set "item3", "bar", "nada", "snafu"

        expect(matrix.score("bar", "snafu")).to eq(2.0/3.0)
      end

      it "should handle missing sets" do
        matrix.add_to_set "item1", "foo", "bar", "fnord", "blubb"

        expect(matrix.score("is", "missing")).to eq(0.0)
      end
    end

    context "sorensen_coefficient" do
      before { @options[:measure] = :sorensen_coefficient }

      it "should calculate the correct sorensen index" do
        matrix.add_to_set "item1", "foo", "bar", "fnord", "blubb"
        matrix.add_to_set "item2", "fnord", "shmoo", "snafu"
        matrix.add_to_set "item3", "bar", "nada", "snafu"

        expect(matrix.score("bar", "snafu")).to eq(2.0/4.0)
      end

      it "should handle missing sets" do
        matrix.add_to_set "item1", "foo", "bar", "fnord", "blubb"

        expect(matrix.score("is", "missing")).to eq(0.0)
      end
    end
  end

  private

  def add_two_item_test_data!(matrix)
    matrix.add_to_set("user42", "fnord", "blubb")
    matrix.add_to_set("user44", "blubb")
    matrix.add_to_set("user46", "fnord")
    matrix.add_to_set("user48", "fnord", "blubb")
    matrix.add_to_set("user50", "fnord")
  end

  def add_three_item_test_data!(matrix)
    matrix.add_to_set("user42", "fnord", "blubb", "shmoo")
    matrix.add_to_set("user44", "blubb")
    matrix.add_to_set("user46", "fnord", "shmoo")
    matrix.add_to_set("user48", "fnord", "blubb")
    matrix.add_to_set("user50", "fnord", "shmoo")
  end

end
