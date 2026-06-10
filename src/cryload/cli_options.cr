module Cryload
  class Cli
    # Typed CLI options populated by the option parser. Nilable fields mean
    # "not provided"; booleans default to their flag-absent value.
    class Options
      property server : String?
      property urls_file : String?
      property numbers : Int32?
      property duration : Int32?
      property connections : Int32 = 10
      property method : String = "GET"
      property body : String?
      property body_file : String?
      property? body_stdin : Bool = false
      property headers : Array(String) = [] of String
      property cookies : Array(String) = [] of String
      property user_agent : String?
      property host_header : String?
      property basic_auth : String?
      property timeout : Int32?
      property rate : Int32?
      property? follow_redirects : Bool = false
      property? disable_keepalive : Bool = false
      property output_format : String?
      property? json : Bool = false
      property success_status : String?
      property? insecure : Bool = false
      property? fail_on_error : Bool = false
      property? fail_on_transport_error : Bool = false
      property max_fail_rate : Float64?
      property max_p99_ms : Float64?
      property warmup : Int32?
      property proxy : String?
      property? progress : Bool = true
      property? random_path : Bool = false
    end

    module OptionsBuilder
      extend self

      def resolve_output_format(options : Options) : String
        return "json" if options.json?
        options.output_format || "text"
      end

      def resolve_body(options : Options) : String?
        return options.body if options.body
        return STDIN.gets_to_end if options.body_stdin?
        options.body_file.try { |path| File.read(path) }
      end

      def build_headers(options : Options) : HTTP::Headers
        headers = parse_headers(options.headers)
        if host_header = options.host_header
          headers["Host"] = host_header
        end
        if user_agent = options.user_agent
          headers["User-Agent"] = user_agent
        end
        if auth = options.basic_auth
          headers["Authorization"] = "Basic #{Base64.strict_encode(auth)}"
        end
        unless options.cookies.empty?
          existing = headers["Cookie"]?
          cookie_values = existing ? [existing] + options.cookies : options.cookies
          headers["Cookie"] = cookie_values.join("; ")
        end
        headers
      end

      def build_ci_thresholds(options : Options) : CiThresholds
        CiThresholds.new(
          fail_on_error: options.fail_on_error?,
          fail_on_transport_error: options.fail_on_transport_error?,
          max_fail_rate: options.max_fail_rate,
          max_p99_ms: options.max_p99_ms,
        )
      end

      def resolve_urls(options : Options) : Array(URI)
        urls = [] of URI
        if path = options.urls_file
          urls.concat Cryload.load_urls_from_file(path)
        end
        if server = options.server
          urls.unshift URI.parse(server)
        end
        urls
      end

      def resolve_proxy(options : Options) : URI?
        options.proxy.try { |raw| URI.parse(raw) }
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
