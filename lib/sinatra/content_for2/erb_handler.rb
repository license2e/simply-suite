class Sinatra::ContentFor2::ErbHandler < Sinatra::ContentFor2::BaseHandler
  attr_reader :output_buffer

  def initialize(template)
    super
    @output_buffer = get_buf
  end

  def is_type?
    ! self.output_buffer.nil?
  end

  def block_is_type?(block)
    is_type? || (block && eval('defined?(__in_erb_template)', block.binding))
  end

  def engines
    @engines ||= [ :erb, :erubis ]
  end

  def capture_from_template(*args, &block)
    self.output_buffer, _buf_was = '', self.output_buffer
    block.call(*args)
    ret = eval('@_out_buf || @_buf', block.binding)
    self.output_buffer = _buf_was
    ret
  end

protected
  def output_buffer=(value)
    template.instance_variable_set(:@_buf, value)
    template.instance_variable_set(:@_out_buf, value)
  end

  def get_buf
    template.instance_variable_get(:@_out_buf) || template.instance_variable_get(:@_buf)
  end
end

Sinatra::ContentFor2::BaseHandler.register(Sinatra::ContentFor2::ErbHandler)

