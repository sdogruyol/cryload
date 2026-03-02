module Cryload
  # Represents an HTTP request.
  class Request
    @start_time : Time::Instant
    @end_time : Time::Instant
    @status_code : Int32

    def initialize(http_client, uri, method : String, headers : HTTP::Headers, body : String?)
      @start_time = Time.instant
      req = HTTP::Request.new(method, uri.request_target, headers, body)
      response = http_client.exec(req)
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
  end
end
