class Sinatra::ContentFor2::SlimHandler < Sinatra::ContentFor2::BaseHandler
  class << self
    def setup_slim
      return if @slim_set
      if defined?(Slim)
        Slim::Engine.set_default_options(:buffer => '@_out_buf', :generator => Temple::Generators::StringBuffer)
        @slim_set = true
      end
    end
  end

  attr_reader :output_buffer

  def initialize(template)
    super
    self.class.setup_slim
    @output_buffer = template.instance_variable_get(:@_out_buf)
  end

  def is_type?
    ! self.output_buffer.nil?
  end

  def capture_from_template(*args, &block)
    self.output_buffer, _buf_was = "", self.output_buffer
    block.call(*args)
    ret = eval("@_out_buf", block.binding)
    self.output_buffer = _buf_was
    ret
  end

  def block_is_type?(block)
    is_type? || (block && eval('defined? __in_erb_template', block.binding))
  end

  def engines
    @engines ||= [ :slim ]
  end

protected
  def output_buffer=(val)
    template.instance_variable_set(:@_out_buf, val)
  end
end

Sinatra::ContentFor2::BaseHandler.register(Sinatra::ContentFor2::SlimHandler)


