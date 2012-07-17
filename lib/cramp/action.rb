module Cramp
  class Action < Abstract
    include PeriodicTimer
    include KeepConnectionAlive

    def initialize(env)
      super
      
      if Faye::WebSocket.websocket?(env)
        @web_socket = Faye::WebSocket.new(env)
        @web_socket.onmessage = lambda do |event|
          message = event.data
          _invoke_data_callbacks(message) if message.is_a?(String)
        end
      end
    end

    protected

    def render(body, *args)
      send(:"render_#{transport}", body, *args)
    end

    def send_initial_response(status, headers, body)
      case transport
      when :long_polling
        # Dont send no initial response. Just cache it for later.
        @_lp_status = status
        @_lp_headers = headers
      else
        super
      end
    end

    class_attribute :default_sse_headers
    self.default_sse_headers = {'Content-Type' => 'text/event-stream', 'Cache-Control' => 'no-cache', 'Connection' => 'keep-alive'}

    class_attribute :default_chunked_headers
    self.default_chunked_headers = {'Transfer-Encoding' => 'chunked', 'Connection' => 'keep-alive'}

    def build_headers
      case transport
      when :sse
        status, headers = respond_to?(:respond_with, true) ? respond_with : [200, {'Content-Type' => 'text/html'}]
        [status, headers.merge(self.default_sse_headers)]
      when :chunked
#        status, headers = respond_to?(:respond_with, true) ? respond_with : [200, {}]
#
#        headers = headers.merge(self.default_chunked_headers)
#        headers['Content-Type'] ||= 'text/html'
#        headers['Cache-Control'] ||= 'no-cache'


        status, headers = respond_to?(:respond_with, true) ? respond_with : [200, {}]

        headers.merge!({
          'Cache-Control' => 'no-cache, no-store, must-revalidate, pre-check=0, post-check=0',
          'Content-Encoding' => 'deflate',
          'Content-Type' => 'application/json;charset=utf-8',
          'Date' => 'Tue, 17 Jul 2012 06:26:49 GMT',
          'Expires' => 'Tue, 31 Mar 1981 05:00:00 GMT',
          'Last-Modified' => 'Tue, 17 Jul 2012 06:26:49 GMT',
          'Pragma' => 'no-cache',
          'Server' => 'tfe',
          'X-Firefox-Spdy' => '1',
          'x-frame-options' => 'SAMEORIGIN',
          'x-ratelimit-class' => 'api',
          'x-ratelimit-limit' => '150',
          'x-ratelimit-remaining' => '148',
          'x-ratelimit-reset' => '1342509997',
          'x-transaction' => '9ae86ab649b8cf4c'
        })

        [status, headers]
      else
        super
      end
    end

    def render_regular(body, *)
      @body.call(body)
    end

    def render_long_polling(data, *)
      @_lp_headers['Content-Length'] = data.size.to_s

      send_response(@_lp_status, @_lp_headers, @body)
      @body.call(data)

      finish
    end

    def render_sse(data, options = {})
      result = "id: #{sse_event_id}\n"
      result << "event: #{options[:event]}\n" if options[:event]
      result << "retry: #{options[:retry]}\n" if options[:retry]

      data.split(/\n/).each {|d| result << "data: #{d}\n" }
      result << "\n"

      @body.call(result)
    end

    def render_websocket(body, *)
      @web_socket.send(body)
    end

    CHUNKED_TERM = "\r\n"
    CHUNKED_TAIL = "0#{CHUNKED_TERM}#{CHUNKED_TERM}"

    def render_chunked(body, *)
      data = [Rack::Utils.bytesize(body).to_s(16), CHUNKED_TERM, body, CHUNKED_TERM].join

      @body.call(data)
    end

    # Used by SSE
    def sse_event_id
      @sse_event_id ||= Time.now.to_i
    end

    def encode(string, encoding = 'UTF-8')
      string.respond_to?(:force_encoding) ? string.force_encoding(encoding) : string
    end

    protected

    def finish
      case transport
      when :chunked
        @body.call(CHUNKED_TAIL) if is_finishable?
      end

      super
    end

  end
end
