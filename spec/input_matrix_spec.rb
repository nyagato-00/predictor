require ::File.expand_path('../spec_helper', __FILE__)

describe Predictor::InputMatrix do
  let(:options) { @default_options.merge(@options) }

  before(:each) { @options = {} }

  before(:all) do
    @default_options = { redis_prefix: "predictor-test", key: "mymatrix" }
    @matrix = Predictor::InputMatrix.new(@default_options)
  end

  before(:each) do
    flush_redis!
  end

  it "should build the correct keys" do
    @matrix.redis_key.should == "predictor-test:mymatrix"
  end

  describe "weight" do
    it "returns the weight configured or a default of 1" do
      @matrix.weight.should == 1.0  # default weight
      matrix = Predictor::InputMatrix.new(redis_prefix: "predictor-test", key: "mymatrix", weight: 5.0)
      matrix.weight.should == 5.0
    end
  end

  describe "add_to_set" do
    it "adds each member of the set to the key's 'sets' set" do
      @matrix.items_for("item1").should_not include("foo", "bar", "fnord", "blubb")
      @matrix.add_to_set "item1", "foo", "bar", "fnord", "blubb"
      @matrix.items_for("item1").should include("foo", "bar", "fnord", "blubb")
    end

    it "adds the key to each set member's 'items' set" do
      @matrix.sets_for("foo").should_not include("item1")
      @matrix.sets_for("bar").should_not include("item1")
      @matrix.sets_for("fnord").should_not include("item1")
      @matrix.sets_for("blubb").should_not include("item1")
      @matrix.add_to_set "item1", "foo", "bar", "fnord", "blubb"
      @matrix.sets_for("foo").should include("item1")
      @matrix.sets_for("bar").should include("item1")
      @matrix.sets_for("fnord").should include("item1")
      @matrix.sets_for("blubb").should include("item1")
    end
  end

  describe "items_for" do
    it "returns the items in the given set ID" do
      @matrix.add_to_set "item1", ["foo", "bar", "fnord", "blubb"]
      @matrix.items_for("item1").should include("foo", "bar", "fnord", "blubb")
      @matrix.add_to_set "item2", ["foo", "bar", "snafu", "nada"]
      @matrix.items_for("item2").should include("foo", "bar", "snafu", "nada")
      @matrix.items_for("item1").should_not include("snafu", "nada")
    end
  end

  describe "sets_for" do
    it "returns the set IDs the given item is in" do
      @matrix.add_to_set "item1", ["foo", "bar", "fnord", "blubb"]
      @matrix.add_to_set "item2", ["foo", "bar", "snafu", "nada"]
      @matrix.sets_for("foo").should include("item1", "item2")
      @matrix.sets_for("snafu").should == ["item2"]
    end
  end

  describe "related_items" do
    it "returns the items in sets the given item is also in" do
      @matrix.add_to_set "item1", ["foo", "bar", "fnord", "blubb"]
      @matrix.add_to_set "item2", ["foo", "bar", "snafu", "nada"]
      @matrix.add_to_set "item3", ["nada", "other"]
      @matrix.related_items("bar").should include("foo", "fnord", "blubb", "snafu", "nada")
      @matrix.related_items("bar").length.should == 5
      @matrix.related_items("other").should == ["nada"]
      @matrix.related_items("snafu").should include("foo", "bar", "nada")
      @matrix.related_items("snafu").length.should == 3
    end
  end

  describe "delete_item" do
    before do
      @matrix.add_to_set "item1", "foo", "bar", "fnord", "blubb"
      @matrix.add_to_set "item2", "foo", "bar", "snafu", "nada"
      @matrix.add_to_set "item3", "nada", "other"
    end

    it "should delete the item from sets it is in" do
      @matrix.items_for("item1").should include("bar")
      @matrix.items_for("item2").should include("bar")
      @matrix.sets_for("bar").should include("item1", "item2")
      @matrix.delete_item("bar")
      @matrix.items_for("item1").should_not include("bar")
      @matrix.items_for("item2").should_not include("bar")
      @matrix.sets_for("bar").should be_empty
    end
  end

  it "should calculate the correct jaccard index" do
    @matrix.add_to_set "item1", "foo", "bar", "fnord", "blubb"
    @matrix.add_to_set "item2", "bar", "fnord", "shmoo", "snafu"
    @matrix.add_to_set "item3", "bar", "nada", "snafu"

    @matrix.calculate_jaccard("bar", "snafu").should == 2.0/3.0
  end

  describe "#score" do
    let(:matrix) { Predictor::InputMatrix.new(options) }

    context "default" do
      it "scores as jaccard index by default" do
        matrix.add_to_set "item1", "foo", "bar", "fnord", "blubb"
        matrix.add_to_set "item2", "bar", "fnord", "shmoo", "snafu"
        matrix.add_to_set "item3", "bar", "nada", "snafu"

        matrix.score("bar", "snafu").should == 2.0/3.0
      end

      it "should handle missing sets" do
        matrix.add_to_set "item1", "foo", "bar", "fnord", "blubb"

        matrix.score("is", "missing").should == 0.0
      end
    end

    context "sorensen_coefficient" do
      before { @options[:measure] = :sorensen_coefficient }

      it "should calculate the correct sorensen index" do
        matrix.add_to_set "item1", "foo", "bar", "fnord", "blubb"
        matrix.add_to_set "item2", "fnord", "shmoo", "snafu"
        matrix.add_to_set "item3", "bar", "nada", "snafu"

        matrix.score("bar", "snafu").should == 2.0/4.0
      end

      it "should handle missing sets" do
        matrix.add_to_set "item1", "foo", "bar", "fnord", "blubb"

        matrix.score("is", "missing").should == 0.0
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
