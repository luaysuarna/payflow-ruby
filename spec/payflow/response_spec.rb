require 'spec_helper'

describe Payflow::Response do
  let(:http_response) { OpenStruct.new(status: 200, body: "RESULT=0&PNREF=V7004C204D9A&RESPMSG=HELLOMESSAGE")}
  let(:response) { Payflow::Response.new(http_response)}

  it "should know the response message" do
    response.result[:message] = "This is the auth response message"
    response.message.should eql("This is the auth response message")
  end

  it "should not be successful if result is not 0" do
    response.result[:result] = "1"
    response.successful?.should be(false)
  end

  it "should know if the response was successful" do
    response.result[:result] = "0"
    response.successful?.should be(true)
  end

  it "should use a pn_ref for auth token if it exists" do
    response.result[:pn_ref] = "PN_REF"
    response.authorization_token.should eql("PN_REF")
  end

  it "should use rp_ref if pn_ref is undefined" do
    response.result[:rp_ref] = "RP_REF"
    response.authorization_token.should eql("RP_REF")
  end

  it "should assign result, message, authorization_token, avs_result, cv_result" do
   http_response.body = "RESULT=0&PNREF=PNREFAUTH&RESPMSG=HELLOMESSAGE&PREFPSMSG=Review: More than one rule was triggered for Review"

    response = Payflow::Response.new(http_response)

    response.result[:pnref].should eql("PNREFAUTH")
    response.result[:result].should eql("0")
  end
end