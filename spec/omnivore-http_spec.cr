require "./spec_helper"

describe Omnivore::Http do

  it "should add an http source to available sources" do
    Omnivore::Source.sources["http"]?.should_not be_nil
  end

  it "should transmit message and process on receipt" do
    config = generate_omnivore_config("simple")
    app = Omnivore::Application::Pathed.new(config)
    endpoint = app.endpoints["tester"]
    source = endpoint.sources.first
    final = app.endpoints["spec"].sources.first as Omnivore::Source::Spec
    message = Omnivore::Message.new(source)
    app.consume!
    spawn do
      100.times{ endpoint.transmit(message) }
    end
    Fiber.yield
    99.times{ final.spec_mailbox.receive }
    message = final.spec_mailbox.receive
    app.halt!
    if(message.nil?)
      fail "Expected message not received"
    else
      message.get(:data, :test, :value, type: :string).should eq("testing")
    end

  end

end
