require 'logger'

module ExampleGroupMethods
  def uses_logger
    let(:logger) { instance_double(Logger, 'mock') }

    before(:each) do
      allow(Logger).to receive(:new).and_return(logger)
      allow(logger).to receive(:debug).with(instance_of(String)) { |s, &blk| blk.call }
      allow(logger).to receive(:info).with(instance_of(String)) { |s, &blk| blk.call }
      allow(logger).to receive(:error).with(instance_of(String)) { |s, &blk| blk.call }
      allow(logger).to receive(:level=).with(Logger::INFO)
      allow(logger).to receive(:formatter=).with(an_instance_of(Proc))
      allow(logger).to receive(:kind_of?).with(Logger).and_return(true)
    end
  end
end
