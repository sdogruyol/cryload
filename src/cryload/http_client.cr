require "openssl"

module Cryload
  DEFAULT_MAX_REDIRECTS = 5

  def self.proxy_request_target(uri : URI) : String
    port = effective_port(uri)
    "#{uri.scheme}://#{uri.host}:#{port}#{uri.request_target}"
  end

  def self.effective_port(uri : URI) : Int32
    uri.port || (uri.scheme == "https" ? 443 : 80)
  end

  def self.create_http_client(uri, timeout_seconds : Int32? = nil, insecure : Bool = false, proxy : URI? = nil)
    return create_direct_http_client(uri, timeout_seconds, insecure) unless proxy

    if uri.scheme == "https"
      create_https_proxy_client(uri, proxy, timeout_seconds, insecure)
    else
      create_http_proxy_client(uri, proxy, timeout_seconds, insecure)
    end
  end

  def self.create_direct_http_client(uri, timeout_seconds : Int32? = nil, insecure : Bool = false)
    port = effective_port(uri)
    tls_context = tls_context_for(uri, insecure)
    client = HTTP::Client.new uri.host.not_nil!, port: port, tls: tls_context
    apply_timeouts(client, timeout_seconds)
    client
  end

  def self.create_http_proxy_client(uri, proxy : URI, timeout_seconds : Int32? = nil, insecure : Bool = false)
    proxy_port = effective_port(proxy)
    client = HTTP::Client.new proxy.host.not_nil!, port: proxy_port, tls: tls_context_for(proxy, insecure)
    apply_timeouts(client, timeout_seconds)
    client
  end

  def self.create_https_proxy_client(uri, proxy : URI, timeout_seconds : Int32? = nil, insecure : Bool = false)
    port = effective_port(uri)
    proxy_port = effective_port(proxy)
    socket = TCPSocket.new(proxy.host.not_nil!, proxy_port)
    socket << connect_request(uri, port, proxy)

    status_code = read_proxy_connect_status(socket)
    unless status_code == 200
      socket.close
      raise IO::Error.new("Proxy CONNECT failed with status #{status_code}")
    end

    tls_context = if insecure
                    OpenSSL::SSL::Context::Client.insecure
                  else
                    OpenSSL::SSL::Context::Client.new
                  end
    ssl_socket = OpenSSL::SSL::Socket::Client.new(
      socket,
      context: tls_context,
      sync_close: true,
      hostname: uri.host.not_nil!,
    )

    client = HTTP::Client.new(ssl_socket, host: uri.host.not_nil!, port: port)
    apply_timeouts(client, timeout_seconds)
    client
  end

  def self.read_proxy_connect_status(socket : IO) : Int32
    line = socket.gets
    raise IO::Error.new("Proxy CONNECT failed: empty response") unless line

    parts = line.split
    raise IO::Error.new("Proxy CONNECT failed: #{line.strip}") unless parts.size >= 2

    status_code = parts[1].to_i?
    raise IO::Error.new("Proxy CONNECT failed: #{line.strip}") unless status_code

    while (header_line = socket.gets)
      break if header_line == "\r\n" || header_line.strip.empty?
    end

    status_code
  end

  def self.connect_request(uri : URI, port : Int32, proxy : URI) : String
    host = uri.host.not_nil!
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
    insecure ? OpenSSL::SSL::Context::Client.insecure : true
  end

  def self.apply_timeouts(client : HTTP::Client, timeout_seconds : Int32?)
    return unless timeout = timeout_seconds
    span = timeout.seconds
    client.connect_timeout = span
    client.read_timeout = span
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
end
