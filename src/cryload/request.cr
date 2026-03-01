module Cryload
  # Respresents an HTTP::get request
  class Request
    @start_time : Time::Instant
    @end_time : Time::Instant
    @status_code : Int32

    def initialize(http_client, uri)
      @start_time = Time.instant
      response = http_client.get uri.request_target
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
