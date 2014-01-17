require ::File.expand_path('../spec_helper', __FILE__)

describe Predictor do

  it "should store a redis connection" do
    Predictor.redis = "asd"
    Predictor.redis.should == "asd"
  end

  it "should raise an exception if unconfigured redis connection is accessed" do
    Predictor.redis = nil
    lambda{ Predictor.redis }.should raise_error(/not configured/i)
  end

end
