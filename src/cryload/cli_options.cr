module Cryload
  class Cli
    module OptionsBuilder
      extend self

      def resolve_output_format(options : Hash(Symbol, String | Int32 | Bool | Float64 | Array(String))) : String
        return "json" if options[:json]?.try(&.as(Bool))
        options[:output_format]?.try(&.as(String)) || "text"
      end

      def resolve_body(options : Hash(Symbol, String | Int32 | Bool | Float64 | Array(String))) : String?
        body = options[:body]?.try(&.as(String))
        return body if body

        body_file = options[:body_file]?.try(&.as(String))
        return nil unless body_file

        File.read(body_file)
      end

      def build_headers(
        options : Hash(Symbol, String | Int32 | Bool | Float64 | Array(String)),
        raw_headers : Array(String),
        cookies : Array(String),
      ) : HTTP::Headers
        headers = parse_headers(raw_headers)
        if host_header = options[:host_header]?.try(&.as(String))
          headers["Host"] = host_header
        end
        if user_agent = options[:user_agent]?.try(&.as(String))
          headers["User-Agent"] = user_agent
        end
        if auth = options[:basic_auth]?.try(&.as(String))
          headers["Authorization"] = "Basic #{Base64.strict_encode(auth)}"
        end
        unless cookies.empty?
          existing = headers["Cookie"]?
          cookie_values = existing ? [existing] + cookies : cookies
          headers["Cookie"] = cookie_values.join("; ")
        end
        headers
      end

      def build_ci_thresholds(options : Hash(Symbol, String | Int32 | Bool | Float64 | Array(String))) : CiThresholds
        CiThresholds.new(
          fail_on_error: options[:fail_on_error]?.try(&.as(Bool)) || false,
          fail_on_transport_error: options[:fail_on_transport_error]?.try(&.as(Bool)) || false,
          max_fail_rate: options[:max_fail_rate]?.try(&.as(Float64)),
          max_p99_ms: options[:max_p99_ms]?.try(&.as(Float64)),
        )
      end

      def resolve_urls(options : Hash(Symbol, String | Int32 | Bool | Float64 | Array(String))) : Array(URI)
        urls = [] of URI
        if path = options[:urls_file]?.try(&.as(String))
          urls.concat Cryload.load_urls_from_file(path)
        end
        if server = options[:server]?.try(&.as(String))
          urls.unshift URI.parse(server)
        end
        urls
      end

      def resolve_proxy(options : Hash(Symbol, String | Int32 | Bool | Float64 | Array(String))) : URI?
        raw = options[:proxy]?.try(&.as(String))
        return nil unless raw
        URI.parse(raw)
      end

      private def parse_headers(raw_headers : Array(String))
        headers = HTTP::Headers.new
        raw_headers.each do |header|
          parts = header.split(":", 2)
          next if parts.size != 2
          key = parts[0].strip
          value = parts[1].strip
          headers[key] = value
        end
        headers
      end
    end
  end
end
