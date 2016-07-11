module Omnivore
  class Source
    class Http < Source

      property source_mailbox = Channel(Message).new
      property connect_called : Bool = false
      property shutdown_called : Bool = false
      property request_contexts = {} of String => HTTP::Server::Context

      @client : HTTP::Client?
      @path : String?

      def setup
        uri = URI.parse(config["url"].to_s)
        @client = HTTP::Client.new(uri)
        @path = uri.path ? uri.path.to_s : "/"
        hook = Omnivore::Http::Hook.new(
          config["url"].to_s, config.fetch("method", "get").to_s, self
        )
        Omnivore::Http.control.add_hook(hook)
      end

      def client : HTTP::Client
        client = @client
        if(client.nil?)
          raise "HTTP client connection is not properly setup!"
        else
          client
        end
      end

      def connect
        @connect_called = true
        Omnivore::Http.control.start
      end

      # Send message to source
      #
      # @param msg [Message]
      # @return [self]
      def transmit(msg : Message)
        payload = msg.data
        debug ">> #{payload.to_json}"
        response = client.exec(
          config.fetch("method", "get").to_s.upcase,
          @path.to_s
        )
        unless(response.status_code == 200)
          error "Transmission of message (`#{msg}`) to source `#{name}` failed with status code: #{response.status_code}"
          raise "Failed to send message to source `#{name}`!"
        end
        self
      end

      # Fetch message from source
      #
      # @return [Message?]
      def receive
        debug "Waiting for new message"
        payload = source_mailbox.receive?
        until(payload || source_mailbox.closed?)
          source_mailbox.wait_for_receive
          payload = source_mailbox.receive?
        end
        if(payload)
          debug "<< #{payload}"
          payload
        end
      end

      def confirm(msg : Message) : Message
        context = request_contexts.delete(msg["id"].to_s)
        if(context)
          debug "Confirming HTTP message `#{msg}`"
          context = context as HTTP::Server::Context
          context.response.status_code = 200
          body = {"message" => "message delivered", "code" => 200, "job_id" => msg["id"]}.to_json
          context.response.content_type = "application/json"
          context.response.content_length = body.size
          context.response.print(body)
          context.response.close
        else
          warn "Failed to locate HTTP request context for message confirmation (ID: `#{msg["id"]}`)"
        end
        msg
      end

      # Shutdown the source
      #
      # @return [self]
      def shutdown
        Omnivore::Http.control.stop
        source_mailbox.close
        @shutdown_called = true
        self
      end

    end
  end
end
