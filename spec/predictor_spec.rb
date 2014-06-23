require 'spec_helper'

describe Predictor do

  it "should store a redis connection" do
    Predictor.redis = "asd"
    expect(Predictor.redis).to eq("asd")
  end

  it "should raise an exception if unconfigured redis connection is accessed" do
    Predictor.redis = nil
    expect{ Predictor.redis }.to raise_error(/not configured/i)
  end

end
