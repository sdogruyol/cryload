module Cryload
  # Respresents an HTTP::get request
  class Request
    @start_time : Time
    @end_time : Time
    @status_code : Int32

    def initialize(http_client, uri)
      @start_time = Time.local
      response = http_client.get uri.request_target
      @end_time = Time.local
      @status_code = response.status_code
    end

    # Calculates time taken for the request (in miliseconds)
    def time_taken
      (@end_time - @start_time).to_f * 1000.0
    end

    # Checks if response status_code is in between 200.300 meaning
    # the request was successful
    def is_ok?
      200 <= @status_code <= 300
    end
  end
end
