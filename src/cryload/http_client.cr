require "openssl"

{% if flag?(:darwin) %}
  lib LibCrypto
    fun x509_get_default_cert_file = X509_get_default_cert_file : LibC::Char*
  end
{% end %}

{% if flag?(:static) || flag?(:static_openssl) %}
  # A statically linked OpenSSL must not parse the host system's openssl.cnf:
  # its compiled-in OPENSSLDIR can resolve to a foreign distro's config (e.g.
  # Fedora's crypto-policies), which aborts every TLS connection with
  # "digital envelope routines::unknown option". OPENSSL_no_config() is not
  # enough with OpenSSL 3 (config is still loaded lazily per lib context), so
  # point OPENSSL_CONF at the null device before any TLS use. Users can still
  # opt in to a config file by setting OPENSSL_CONF explicitly.
  # (-Dstatic_openssl marks builds that statically link OpenSSL without
  # building the whole binary with --static, e.g. the macOS release binary.)
  ENV["OPENSSL_CONF"] ||= File::NULL
{% end %}

module Cryload
  DEFAULT_MAX_REDIRECTS = 5

  # macOS system CA bundle, used as a fallback when OpenSSL's compiled-in
  # default certificate path (e.g. a Homebrew OPENSSLDIR baked into a
  # statically linked libcrypto) does not exist on the user's machine.
  MACOS_SYSTEM_CA_BUNDLE = "/etc/ssl/cert.pem"

  def self.elapsed_ms(since : Time::Instant) : Float64
    (Time.instant - since).total_milliseconds
  end

  def self.proxy_request_target(uri : URI) : String
    port = effective_port(uri)
    "#{uri.scheme}://#{uri.host}:#{port}#{uri.request_target}"
  end

  def self.effective_port(uri : URI) : Int32
    uri.port || (uri.scheme == "https" ? 443 : 80)
  end

  def self.create_http_client(uri, timeouts : Timeouts = Timeouts.new, insecure : Bool = false, proxy : URI? = nil) : PhasedClient
    return create_direct_http_client(uri, timeouts, insecure) unless proxy

    if uri.scheme == "https"
      create_https_proxy_client(uri, proxy, timeouts, insecure)
    else
      create_http_proxy_client(uri, proxy, timeouts, insecure)
    end
  end

  def self.create_direct_http_client(uri, timeouts : Timeouts = Timeouts.new, insecure : Bool = false) : PhasedClient
    host = uri.host || raise ArgumentError.new("URI host is required")
    port = effective_port(uri)
    tls_context = tls_context_for(uri, insecure)
    client = PhasedClient.new host, port: port, tls: tls_context
    timeouts.apply(client)
    client
  end

  def self.create_http_proxy_client(uri, proxy : URI, timeouts : Timeouts = Timeouts.new, insecure : Bool = false) : PhasedClient
    proxy_host = proxy.host || raise ArgumentError.new("Proxy host is required")
    proxy_port = effective_port(proxy)
    client = PhasedClient.new proxy_host, port: proxy_port, tls: tls_context_for(proxy, insecure)
    # Plain-HTTP targets go to the proxy as absolute-form requests, so the
    # credentials ride on every request instead of on a CONNECT preamble. An
    # explicit -H Proxy-Authorization wins.
    if auth = proxy_authorization(proxy)
      client.before_request { |request| request.headers["Proxy-Authorization"] ||= auth }
    end
    timeouts.apply(client)
    client
  end

  def self.create_https_proxy_client(uri, proxy : URI, timeouts : Timeouts = Timeouts.new, insecure : Bool = false) : PhasedClient
    host = uri.host || raise ArgumentError.new("URI host is required")
    port = effective_port(uri)
    proxy_host = proxy.host || raise ArgumentError.new("Proxy host is required")
    proxy_port = effective_port(proxy)

    connect_start = Time.instant
    # Time::Span, not a bare number: the Windows IOCP event loop only accepts a
    # span, and the numeric overload type-checks on Unix but not there.
    socket = TCPSocket.new(proxy_host, proxy_port, timeouts.timeout, timeouts.timeout)
    socket << connect_request(uri, port, proxy)

    status_code = read_proxy_connect_status(socket)
    unless status_code == 200
      socket.close
      raise IO::Error.new("Proxy CONNECT failed with status #{status_code}")
    end
    connect_ms = elapsed_ms(connect_start)

    tls_context = if insecure
                    OpenSSL::SSL::Context::Client.insecure
                  else
                    default_tls_context
                  end

    tls_start = Time.instant
    ssl_socket = OpenSSL::SSL::Socket::Client.new(
      socket,
      context: tls_context,
      sync_close: true,
      hostname: host,
    )
    tls_ms = elapsed_ms(tls_start)

    # DNS is folded into the CONNECT phase here: the tunnel is established by
    # the proxy, so the client never resolves the target host itself.
    client = PhasedClient.new(ssl_socket, host, port, 0.0, connect_ms, tls_ms)
    timeouts.apply(client)
    client
  end

  def self.read_proxy_connect_status(socket : IO) : Int32
    line = socket.gets
    raise IO::Error.new("Proxy CONNECT failed: empty response") unless line

    parts = line.split
    raise IO::Error.new("Proxy CONNECT failed: #{line.strip}") unless parts.size >= 2

    status_code = parts[1].to_i?
    raise IO::Error.new("Proxy CONNECT failed: #{line.strip}") unless status_code

    while header_line = socket.gets
      break if header_line == "\r\n" || header_line.strip.empty?
    end

    status_code
  end

  def self.connect_request(uri : URI, port : Int32, proxy : URI) : String
    host = uri.host || raise ArgumentError.new("URI host is required")
    request = String.build do |io|
      io << "CONNECT #{host}:#{port} HTTP/1.1\r\n"
      io << "Host: #{host}:#{port}\r\n"
      if auth = proxy_authorization(proxy)
        io << "Proxy-Authorization: #{auth}\r\n"
      end
      io << "\r\n"
    end
    request
  end

  def self.proxy_authorization(proxy : URI) : String?
    return unless user = proxy.user.presence
    password = proxy.password || ""
    "Basic #{Base64.strict_encode("#{user}:#{password}")}"
  end

  def self.tls_context_for(uri : URI, insecure : Bool)
    return false unless uri.scheme == "https"
    insecure ? OpenSSL::SSL::Context::Client.insecure : default_tls_context
  end

  def self.default_tls_context : OpenSSL::SSL::Context::Client
    context = OpenSSL::SSL::Context::Client.new
    {% if flag?(:darwin) %}
      unless ENV.has_key?("SSL_CERT_FILE") || ENV.has_key?("SSL_CERT_DIR")
        default_cert_file = String.new(LibCrypto.x509_get_default_cert_file)
        if !File.exists?(default_cert_file) && File.exists?(MACOS_SYSTEM_CA_BUNDLE)
          context.ca_certificates = MACOS_SYSTEM_CA_BUNDLE
        end
      end
    {% end %}
    context
  end

  # A request deadline that carries the limit it was derived from, so the error
  # can name the flag value without reaching back into the config.
  struct Deadline
    getter at : Time::Instant
    getter span : Time::Span

    def initialize(@at : Time::Instant, @span : Time::Span)
    end

    def exceeded? : Bool
      Time.instant >= @at
    end
  end

  # Socket-level deadlines. v5 set only connect and read, so a peer that
  # accepted the request and then stopped reading could block a worker forever.
  struct Timeouts
    getter timeout : Time::Span?
    getter request_timeout : Time::Span?

    def initialize(@timeout : Time::Span? = nil, @request_timeout : Time::Span? = nil)
    end

    def apply(client : HTTP::Client) : Nil
      return unless span = @timeout
      client.connect_timeout = span
      client.read_timeout = span
      client.write_timeout = span
    end

    # Absolute deadline for one request, or nil when --request-timeout is unset.
    def deadline_from(start : Time::Instant) : Deadline?
      @request_timeout.try { |span| Deadline.new(start + span, span) }
    end
  end

  def self.load_urls_from_file(path : String) : Array(URI)
    urls = [] of URI
    File.each_line(path) do |line|
      value = line.strip
      next if value.empty? || value.starts_with?("#")
      uri = URI.parse(value)
      unless uri.host && (uri.scheme == "http" || uri.scheme == "https")
        raise ArgumentError.new("Invalid URL '#{value}' in #{path}.")
      end
      urls << uri
    end
    raise ArgumentError.new("URL list must not be empty: #{path}") if urls.empty?
    urls
  end

  def self.display_url(urls : Array(URI)) : String
    return urls.first.to_s if urls.size == 1
    "#{urls.first} (+#{urls.size - 1} more)"
  end

  # HTTP::Request mutates the headers object it is handed (Host, Content-Length),
  # so every worker needs its own copy once the load fibers run in parallel.
  def self.clone_headers(headers : HTTP::Headers) : HTTP::Headers
    copy = HTTP::Headers.new
    headers.each do |name, values|
      copy[name] = values.size == 1 ? values.first : values
    end
    copy
  end
end
