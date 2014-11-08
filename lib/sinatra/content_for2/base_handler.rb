class Sinatra::ContentFor2::BaseHandler
  class << self
    def classes
      @classes ||= []
    end

    def register(handlerClass)
      classes << handlerClass
    end
  end

  attr_reader :template

  def initialize(template)
    @template = template
  end

  def engines
    raise NotImplementedError.new
  end

  def is_type?
    raise NotImplementedError.new
  end

  def block_is_type?(block)
    raise NotImplementedError.new
  end

  def capture_from_template(*args, &block)
    raise NotImplementedError.new
  end
end
