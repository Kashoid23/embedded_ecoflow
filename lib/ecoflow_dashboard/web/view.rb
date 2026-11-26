# frozen_string_literal: true

require 'erb'

module EcoflowDashboard
  module Web
    # Renders an ERB template. Locals become methods, helpers are mixed in.
    #   View.new(dir).page(:index, page: dashboard)  -> HTML inside layout
    #   partial(:kpi, tile: t)                       -> views/partials/_kpi.html.erb
    class View
      include ERB::Util
      include Helpers
      include WeatherIcons

      # Template path -> name of the View method it was compiled into. Templates don't
      # change while the app runs, so each is parsed and compiled to bytecode only once.
      TEMPLATES = {}
      COMPILE = Mutex.new

      def initialize(dir, locals = {})
        @dir = dir
        locals.each { |name, value| define_singleton_method(name) { value } }
      end

      def page(name, **locals)
        content = View.new(@dir, locals).evaluate(name.to_s)
        View.new(@dir, locals.merge(content: content)).evaluate('layout')
      end

      def partial(name, **locals) = View.new(@dir, locals).evaluate("partials/_#{name}")

      protected

      def evaluate(name) = send(template(File.join(@dir, "#{name}.html.erb")))

      private

      def template(file)
        TEMPLATES[file] || COMPILE.synchronize do
          TEMPLATES[file] ||= "__template_#{TEMPLATES.size}".tap do |method|
            ERB.new(File.read(file, encoding: 'UTF-8'), trim_mode: '-').def_method(View, method, file)
          end
        end
      end
    end
  end
end
