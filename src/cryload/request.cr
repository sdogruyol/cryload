module Cryload
  class Request
    getter :time_taken

    def initialize(http_client, uri)
      start_time = Time.now
      response = http_client.get uri.full_path
      end_time = Time.now
      @time_taken = (end_time - start_time).to_f * 1000.0
      @status_code = response.status_code
    end

    def is_ok?
      @status_code.between?(200, 300)
    end

  end
end
