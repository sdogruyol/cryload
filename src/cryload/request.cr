module Cryload
  # Represents an HTTP request.
  class Request
    REDIRECT_STATUS_CODES = {301, 302, 303, 307, 308}

    @start_time : Time::Instant
    @end_time : Time::Instant
    @status_code : Int32

    getter :status_code

    def initialize(http_client, uri, method : String, headers : HTTP::Headers, body : String?, timeout_seconds : Int32? = nil, insecure : Bool = false, follow_redirects : Bool = false)
      @start_time = Time.instant
      response = exec_request http_client, uri, method, headers, body, timeout_seconds, insecure, follow_redirects
      @end_time = Time.instant
      @status_code = response.status_code
    end

    # Calculates time taken for the request (in milliseconds).
    # Uses monotonic clock (Time.instant) to avoid negative values from system clock adjustments.
    def time_taken
      (@end_time - @start_time).total_seconds * 1000.0
    end

    # Checks if response status_code is in between 200.300 meaning
    # the request was successful
    def is_ok?
      (200..299).includes?(@status_code)
    end

    private def exec_request(http_client, uri, method, headers, body, timeout_seconds : Int32?, insecure : Bool, follow_redirects : Bool)
      current_client = http_client
      current_uri = uri
      current_method = method
      current_body = body
      redirects_remaining = Cryload::DEFAULT_MAX_REDIRECTS

      loop do
        request = HTTP::Request.new(current_method, current_uri.request_target, headers, current_body)
        response = current_client.exec(request)
        return response unless follow_redirects
        return response unless redirect?(response)
        return response if redirects_remaining <= 0

        location = response.headers["Location"]?
        return response unless location

        next_uri = resolve_redirect_uri(current_uri, location)
        redirects_remaining -= 1

        if {301, 302, 303}.includes?(response.status_code) && current_method != "HEAD"
          current_method = "GET"
          current_body = nil
        end

        current_client = same_origin?(current_uri, next_uri) ? current_client : Cryload.create_http_client(next_uri, timeout_seconds, insecure)
        current_uri = next_uri
      end
    end

    private def redirect?(response)
      REDIRECT_STATUS_CODES.includes?(response.status_code)
    end

    private def same_origin?(left : URI, right : URI)
      left.scheme == right.scheme &&
        left.host == right.host &&
        effective_port(left) == effective_port(right)
    end

    private def effective_port(uri : URI)
      uri.port || (uri.scheme == "https" ? 443 : 80)
    end

    private def resolve_redirect_uri(current_uri : URI, location : String)
      redirect_uri = URI.parse(location)
      return redirect_uri if redirect_uri.host && redirect_uri.scheme

      URI.new(
        scheme: current_uri.scheme,
        host: current_uri.host,
        port: current_uri.port,
        path: resolve_redirect_path(current_uri, redirect_uri.path),
        query: redirect_uri.query,
      )
    end

    private def resolve_redirect_path(current_uri : URI, redirect_path : String)
      return redirect_path if redirect_path.starts_with?("/")
      return current_uri.path.presence || "/" if redirect_path.empty?

      base_path = current_uri.path
      base_segments = (base_path.empty? ? "/" : base_path).split("/")
      base_segments.pop unless base_path.ends_with?("/")

      redirect_path.split("/").each do |segment|
        next if segment.empty? || segment == "."
        if segment == ".."
          base_segments.pop if base_segments.size > 1
        else
          base_segments << segment
        end
      end

      resolved = base_segments.join("/")
      resolved = "/#{resolved}" unless resolved.starts_with?("/")
      resolved.empty? ? "/" : resolved
    end
  end
end
