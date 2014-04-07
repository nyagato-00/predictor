require ::File.expand_path('../spec_helper', __FILE__)

describe Predictor::InputMatrix do

  before(:all) do
    @matrix = Predictor::InputMatrix.new(:redis_prefix => "predictor-test", :key => "mymatrix")
  end

  before(:each) do
    flush_redis!
  end

  it "should build the correct keys" do
    expect(@matrix.redis_key).to eq("predictor-test:mymatrix")
  end

  it "should respond to add_set" do
    expect(@matrix.respond_to?(:add_set)).to eq(true)
  end

  it "should respond to add_single" do
    expect(@matrix.respond_to?(:add_single)).to eq(true)
  end

  it "should respond to similarities_for" do
    expect(@matrix.respond_to?(:similarities_for)).to eq(true)
  end

  it "should respond to all_items" do
    expect(@matrix.respond_to?(:all_items)).to eq(true)
  end

  describe "weight" do
    it "returns the weight configured or a default of 1" do
      expect(@matrix.weight).to eq(1.0)  # default weight
      matrix = Predictor::InputMatrix.new(redis_prefix: "predictor-test", key: "mymatrix", weight: 5.0)
      expect(matrix.weight).to eq(5.0)
    end
  end

  describe "add_set" do
    it "adds each member of the set to the 'all_items' set" do
      expect(@matrix.all_items).not_to include("foo", "bar", "fnord", "blubb")
      @matrix.add_set "item1", ["foo", "bar", "fnord", "blubb"]
      expect(@matrix.all_items).to include("foo", "bar", "fnord", "blubb")
    end

    it "adds each member of the set to the key's 'sets' set" do
      expect(@matrix.items_for("item1")).not_to include("foo", "bar", "fnord", "blubb")
      @matrix.add_set "item1", ["foo", "bar", "fnord", "blubb"]
      expect(@matrix.items_for("item1")).to include("foo", "bar", "fnord", "blubb")
    end

    it "adds the key to each set member's 'items' set" do
      expect(@matrix.sets_for("foo")).not_to include("item1")
      expect(@matrix.sets_for("bar")).not_to include("item1")
      expect(@matrix.sets_for("fnord")).not_to include("item1")
      expect(@matrix.sets_for("blubb")).not_to include("item1")
      @matrix.add_set "item1", ["foo", "bar", "fnord", "blubb"]
      expect(@matrix.sets_for("foo")).to include("item1")
      expect(@matrix.sets_for("bar")).to include("item1")
      expect(@matrix.sets_for("fnord")).to include("item1")
      expect(@matrix.sets_for("blubb")).to include("item1")
    end
  end

  describe "add_set!" do
    it "calls add_set and process_item! for each item" do
      expect(@matrix).to receive(:add_set).with("item1", ["foo", "bar"])
      expect(@matrix).to receive(:process_item!).with("foo")
      expect(@matrix).to receive(:process_item!).with("bar")
      @matrix.add_set! "item1", ["foo", "bar"]
    end
  end

  describe "add_single" do
    it "adds the item to the 'all_items' set" do
      expect(@matrix.all_items).not_to include("foo")
      @matrix.add_single "item1", "foo"
      expect(@matrix.all_items).to include("foo")
    end

    it "adds the item to the key's 'sets' set" do
      expect(@matrix.items_for("item1")).not_to include("foo")
      @matrix.add_single "item1", "foo"
      expect(@matrix.items_for("item1")).to include("foo")
    end

    it "adds the key to the item's 'items' set" do
      expect(@matrix.sets_for("foo")).not_to include("item1")
      @matrix.add_single "item1", "foo"
      expect(@matrix.sets_for("foo")).to include("item1")
    end
  end

  describe "add_single!" do
    it "calls add_single and process_item! for the item" do
      expect(@matrix).to receive(:add_single).with("item1", "foo")
      expect(@matrix).to receive(:process_item!).with("foo")
      @matrix.add_single! "item1", "foo"
    end
  end

  describe "all_items" do
    it "returns all items across all sets in the input matrix" do
      @matrix.add_set "item1", ["foo", "bar", "fnord", "blubb"]
      @matrix.add_set "item2", ["foo", "bar", "snafu", "nada"]
      @matrix.add_set "item3", ["nada"]
      expect(@matrix.all_items).to include("foo", "bar", "fnord", "blubb", "snafu", "nada")
      expect(@matrix.all_items.length).to eq(6)
    end
  end

  describe "items_for" do
    it "returns the items in the given set ID" do
      @matrix.add_set "item1", ["foo", "bar", "fnord", "blubb"]
      expect(@matrix.items_for("item1")).to include("foo", "bar", "fnord", "blubb")
      @matrix.add_set "item2", ["foo", "bar", "snafu", "nada"]
      expect(@matrix.items_for("item2")).to include("foo", "bar", "snafu", "nada")
      expect(@matrix.items_for("item1")).not_to include("snafu", "nada")
    end
  end

  describe "sets_for" do
    it "returns the set IDs the given item is in" do
      @matrix.add_set "item1", ["foo", "bar", "fnord", "blubb"]
      @matrix.add_set "item2", ["foo", "bar", "snafu", "nada"]
      expect(@matrix.sets_for("foo")).to include("item1", "item2")
      expect(@matrix.sets_for("snafu")).to eq(["item2"])
    end
  end

  describe "related_items" do
    it "returns the items in sets the given item is also in" do
      @matrix.add_set "item1", ["foo", "bar", "fnord", "blubb"]
      @matrix.add_set "item2", ["foo", "bar", "snafu", "nada"]
      @matrix.add_set "item3", ["nada", "other"]
      expect(@matrix.related_items("bar")).to include("foo", "fnord", "blubb", "snafu", "nada")
      expect(@matrix.related_items("bar").length).to eq(5)
      expect(@matrix.related_items("other")).to eq(["nada"])
      expect(@matrix.related_items("snafu")).to include("foo", "bar", "nada")
      expect(@matrix.related_items("snafu").length).to eq(3)
    end
  end

  describe "similarity" do
    it "should calculate the correct similarity between two items" do
      add_two_item_test_data!(@matrix)
      @matrix.process!
      expect(@matrix.similarity("fnord", "blubb")).to eq(0.4)
      expect(@matrix.similarity("blubb", "fnord")).to eq(0.4)
    end
  end

  describe "similarities_for" do
    it "should calculate all similarities for an item (1/3)" do
      add_three_item_test_data!(@matrix)
      @matrix.process!
      res = @matrix.similarities_for("fnord", with_scores: true)
      expect(res.length).to eq(2)
      expect(res[0]).to eq(["shmoo", 0.75])
      expect(res[1]).to eq(["blubb", 0.4])
    end

    it "should calculate all similarities for an item (2/3)" do
      add_three_item_test_data!(@matrix)
      @matrix.process!
      res = @matrix.similarities_for("shmoo", with_scores: true)
      expect(res.length).to eq(2)
      expect(res[0]).to eq(["fnord", 0.75])
      expect(res[1]).to eq(["blubb", 0.2])
    end


    it "should calculate all similarities for an item (3/3)" do
      add_three_item_test_data!(@matrix)
      @matrix.process!
      res = @matrix.similarities_for("blubb", with_scores: true)
      expect(res.length).to eq(2)
      expect(res[0]).to eq(["fnord", 0.4])
      expect(res[1]).to eq(["shmoo", 0.2])
    end
  end

  describe "delete_item!" do
    before do
      @matrix.add_set "item1", ["foo", "bar", "fnord", "blubb"]
      @matrix.add_set "item2", ["foo", "bar", "snafu", "nada"]
      @matrix.add_set "item3", ["nada", "other"]
      @matrix.process!
    end

    it "should delete the item from sets it is in" do
      expect(@matrix.items_for("item1")).to include("bar")
      expect(@matrix.items_for("item2")).to include("bar")
      expect(@matrix.sets_for("bar")).to include("item1", "item2")
      @matrix.delete_item!("bar")
      expect(@matrix.items_for("item1")).not_to include("bar")
      expect(@matrix.items_for("item2")).not_to include("bar")
      expect(@matrix.sets_for("bar")).to be_empty
    end

    it "should delete the cached similarities for the item" do
      expect(@matrix.similarities_for("bar")).not_to be_empty
      @matrix.delete_item!("bar")
      expect(@matrix.similarities_for("bar")).to be_empty
    end

    it "should delete the item from other cached similarities" do
      expect(@matrix.similarities_for("foo")).to include("bar")
      @matrix.delete_item!("bar")
      expect(@matrix.similarities_for("foo")).not_to include("bar")
    end

    it "should delete the item from the all_items set" do
      expect(@matrix.all_items).to include("bar")
      @matrix.delete_item!("bar")
      expect(@matrix.all_items).not_to include("bar")
    end
  end

  it "should calculate the correct jaccard index" do
    @matrix.add_set "item1", ["foo", "bar", "fnord", "blubb"]
    @matrix.add_set "item2", ["bar", "fnord", "shmoo", "snafu"]
    @matrix.add_set "item3", ["bar", "nada", "snafu"]

    expect(@matrix.send(:calculate_jaccard,
      "bar",
      "snafu"
    )).to eq(2.0/3.0)
  end

private

  def add_two_item_test_data!(matrix)
    matrix.add_set("user42", ["fnord", "blubb"])
    matrix.add_set("user44", ["blubb"])
    matrix.add_set("user46", ["fnord"])
    matrix.add_set("user48", ["fnord", "blubb"])
    matrix.add_set("user50", ["fnord"])
  end

  def add_three_item_test_data!(matrix)
    matrix.add_set("user42", ["fnord", "blubb", "shmoo"])
    matrix.add_set("user44", ["blubb"])
    matrix.add_set("user46", ["fnord", "shmoo"])
    matrix.add_set("user48", ["fnord", "blubb"])
    matrix.add_set("user50", ["fnord", "shmoo"])
  end

end