module Cryload
  # Respresents an HTTP::get request
  class Request
    # Initializes with
    # http_client :: HTTP::Client
    # uri :: URI
    def initialize(http_client, uri)
      @start_time = Time.now
      response = http_client.get uri.full_path
      @end_time = Time.now
      @status_code = response.status_code
    end

    # Calculates time taken for the request (in miliseconds)
    def time_taken
      (@end_time - @start_time).to_f * 1000.0
    end

    # Checks if response status_code is in between 200.300 meaning
    # the request was successful
    def is_ok?
      200 < @status_code < 300
    end
  end
end
