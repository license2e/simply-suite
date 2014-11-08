class Sinatra::ContentFor2::HamlHandler < Sinatra::ContentFor2::BaseHandler
  def is_type?
    template.respond_to?(:is_haml?) && template.is_haml?
  end

  def block_is_type?(block)
    template.block_is_haml?(block)
  end

  def capture_from_template(*args, &block)
    eval("_hamlout ||= @haml_buffer", block.binding) # this is for rbx
    template.capture_haml(*args, &block)
  end

  def engines
    @engines ||= [ :haml ]
  end
end

Sinatra::ContentFor2::BaseHandler.register(Sinatra::ContentFor2::HamlHandler)

