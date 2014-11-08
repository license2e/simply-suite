module Sinatra
  module ContentFor2
    def self.included(base) #:nodoc:
      base.send(:include, CurrentTemplateEngine) unless base.method_defined?(:current_template_engine)
    end

    module CurrentTemplateEngine
      attr_reader :current_template_engine

      def render(engine, *) #:nodoc:
        @current_template_engine, engine_was = engine, @current_template_engine
        output = super
        @current_template_engine = engine_was
        output
      end
    end
  end
end

require 'sinatra/content_for2/base_handler'
require 'sinatra/content_for2/erb_handler'
require 'sinatra/content_for2/haml_handler'
require 'sinatra/content_for2/slim_handler'

module Sinatra::ContentFor2
  def capture_html(*args, &block)
    handler = find_proper_handler
    captured_html = nil
    if handler && handler.is_type? && handler.block_is_type?(block)
      captured_html = handler.capture_from_template(*args, &block)
    end
    if captured_html.nil? && block_given?
      captured_html = block.call(*args)
    end
    captured_html || ''
  end

  # Capture a block of content to be rendered later. For example:
  #
  #     <% content_for :head do %>
  #       <script type="text/javascript" src="/foo.js"></script>
  #     <% end %>
  #
  # You can call +content_for+ multiple times with the same key
  # (in the example +:head+), and when you render the blocks for
  # that key all of them will be rendered, in the same order you
  # captured them.
  #
  # Your blocks can also receive values, which are passed to them
  # by <tt>yield_content</tt>
  def content_for(key, content = nil, &block)
    key = key.to_sym
    unless content.nil?
      content_blocks[key] << content
    end
    if block_given?
      content_blocks[key] << block
    end
    ''
  end
  
  # Check if a block of content with the given key was defined. For
  # example:
  #
  #     <% content_for :head do %>
  #       <script type="text/javascript" src="/foo.js"></script>
  #     <% end %>
  #
  #     <% if content_for? :head %>
  #       <span>content "head" was defined.</span>
  #     <% end %>
  def content_for?(key)
    content_blocks[key.to_sym].any?
  end

  # Render the captured blocks for a given key. For example:
  #
  #     <head>
  #       <title>Example</title>
  #       <% yield_content :head %>
  #     </head>
  #
  # Would render everything you declared with <tt>content_for 
  # :head</tt> before closing the <tt><head></tt> tag.
  #
  # You can also pass values to the content blocks by passing them
  # as arguments after the key:
  #
  #     <% yield_content :head, 1, 2 %>
  #
  # Would pass <tt>1</tt> and <tt>2</tt> to all the blocks registered
  # for <tt>:head</tt>.
  #
  # *NOTICE* that you call this without an <tt>=</tt> sign. IE, 
  # in a <tt><% %></tt> block, and not in a <tt><%= %></tt> block.
  #
  # *NOTICE* 
  # if you call from erubis, you call this with <tt>=</tt> sign.IE,
  #in a <tt><%= %></tt> block, and not in a <tt><% %></tt> block.
  def yield_content(key, *args)
    blocks = content_blocks[key.to_sym]
    return nil if blocks.empty?
    blocks.map do |block|
      block.kind_of?(Proc) ? capture_html(*args, &block) : block.to_s
    end.join('')
  end

protected
  def content_blocks
    @content_blocks ||= Hash.new { |h, k| h[k] = [] }
  end

  def find_proper_handler
    Sinatra::ContentFor2::BaseHandler.classes.map do |handlerClass|
      handlerClass.new(self)
    end.find do |handler|
      handler.engines.include?(current_template_engine) && handler.is_type?
    end
  end

end

