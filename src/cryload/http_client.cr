module Cryload
  DEFAULT_MAX_REDIRECTS = 5

  def self.create_http_client(uri, timeout_seconds : Int32? = nil, insecure : Bool = false)
    port = uri.port || (uri.scheme == "https" ? 443 : 80)
    tls_context = if uri.scheme == "https"
                    insecure ? OpenSSL::SSL::Context::Client.insecure : true
                  else
                    false
                  end
    client = HTTP::Client.new uri.host.not_nil!, port: port, tls: tls_context
    if (timeout = timeout_seconds)
      span = timeout.seconds
      client.connect_timeout = span
      client.read_timeout = span
    end
    client
  end
end
