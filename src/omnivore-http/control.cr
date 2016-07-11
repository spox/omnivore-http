module Omnivore::Http

  class Hook
    getter path : String = "/"
    getter method : String = "get"
    getter source : Source::Http
    getter port : Int32 = 8080

    def initialize(@path : String, @method : String, @source : Source::Http)
      @method = @method.downcase
      @path = @path.downcase
    end

    def initialize(@path : String, @method : String, @port : Int32, @source : Source::Http)
      @method = @method.downcase
      @path = @path.downcase
    end

    def initialize(url : String, @method : String, @source : Source::Http)
      @method = @method.downcase
      @port = 8080
      @path = "/"
      uri = URI.parse(url)
      if(uri.path)
        @path = uri.path.to_s
      end
      if(uri.port)
        @port = uri.port as Int32
      elsif(uri.scheme)
        case uri.scheme
        when "http"
          @port = 80
        when "https"
          @port = 443
        end
      end
    end

    def initialize(@source : Source::Http)
    end

  end

  class Control

    include Omnivore::Utils::Logger
    include Crogo::AnimalStrings

    @running : Bool = false
    property hooks : Array(Hook) = [] of Hook
    property lookup : Hash(String, Hook) = {} of String => Hook

    @servers = {} of Int32 => HTTP::Server

    def start
      unless(@running)
        debug "Starting HTTP incoming servers"
        ports = hooks.map do |hook|
          hook.port
        end.uniq
        ports.each do |port|
          debug "HTTP server startup for port: #{port}"
          @servers[port] = HTTP::Server.new(
            "0.0.0.0", port, Handler.new(self, port)
          )
        end
        @servers.values.each do |srv|
          spawn{ srv.listen }
        end
        debug "HTTP servers have been started and are now accepting"
        @running = true
      end
    end

    def stop
      debug "Stopping any running HTTP servers"
      @servers.each do |port, srv|
        debug "Stopping HTTP server listening on port `#{port}`"
        srv.close
        debug "HTTP server listening on port `#{port}` is now stopped"
      end
      debug "All running HTTP servers have been stopped"
      @servers.clear
    end

    def add_hook(path : String, method : String, source : Source::Http) : Hook
      hook = Hook.new(path, method, source)
      add_hook(hook)
    end

    def add_hook(path : String, method : String, port : Int32, source : Source::Http) : Hook
      hook = Hook.new(path, method, port, source)
      add_hook(hook)
    end

    def add_hook(hook : Hook) : Hook
      lookup_key = generate_lookup_key(hook)
      if(lookup[lookup_key]?)
        error "Cannot add new hook. Hook already registered at destination."
        raise "Defined HTTP path and method already registered (`#{hook.port}:#{hook.method}` -> `#{hook.path}`)"
      end
      debug "Adding new HTTP hook #{hook}"
      lookup[lookup_key] = hook
      hooks.push(hook)
      hook
    end

    def remove_hook(path : String)
      hooks.each do |hook|
        remove_hook(hook) if hook.path == path
      end
    end

    def remove_hook(path : String, method : String)
      hooks.each do |hook|
        remove_hook(hook) if hook.path == path && hook.method == method
      end
    end

    def remove_hook(source : Source)
      hooks.each do |hook|
        remove_hook(hook) if hook.source == source
      end
      nil
    end

    def remove_hook(hook : Hook)
      debug "Deleting HTTP hook: #{hook}"
      lookup_key = generate_lookup_key(hook)
      lookup.delete(lookup_key)
      hooks.delete(hook)
      nil
    end

    def generate_lookup_key(hook)
      "#{hook.method}_#{hook.port}_#{hook.path}"
    end

    def format_request(request)
      payload = Smash.new
      body = request.body ? request.body.to_s : "{}"
      data = JSON.parse(body).as_h.unsmash
      http_data = {} of String => JSON::Type
      params = {} of String => JSON::Type
      headers = {} of String => JSON::Type
      request.query_params.each do |key, value|
        params[key] = value
      end
      request.headers.each do |key, value|
        headers[snake(key.gsub("-", "_"))] = Smash.value_convert(value)
        headers[key] = Smash.value_convert(value)
      end
      http_data["headers"] = headers
      http_data["params"] = params
      data["http"] = http_data
      data
    end

    class Handler < HTTP::Handler

      include Omnivore::Utils::Logger

      getter port : Int32
      getter control : Control

      def initialize(@control : Control, @port : Int32)
      end

      def call(context)
        c_method = context.request.method.downcase
        c_path = context.request.path ? context.request.path.to_s.downcase : "/"
        lookup_key = "#{c_method}_#{port}_#{c_path}"
        if(control.lookup[lookup_key]?)
          src = control.lookup[lookup_key].source
          debug "Handling incoming HTTP request with lookup match `#{lookup_key}` for source `#{src.name}`"
          payload = control.format_request(context.request)
          message = Message.new(payload, src)
          src.request_contexts[message["id"].to_s] = context
          if(src.config["auto_confirm"]?)
            debug "Auto confirming HTTP request as instructed by source configuration (source: `#{src.name}`)"
            message.confirm
          end
          src.source_mailbox.send(message)
          message.confirm_wait
        else
          call_next(context)
        end
      end

    end

  end
end
