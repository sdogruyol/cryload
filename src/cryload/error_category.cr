module Cryload
  # Raised when a request exceeds `--request-timeout`. Deliberately not an
  # `IO::Error`: HTTP::Client retries some IO errors on a reused connection, and
  # a deadline breach must abort instead of being replayed.
  class RequestTimeoutError < Exception
    def initialize(limit : Time::Span)
      super("Request exceeded --request-timeout of #{Duration.format(limit)}")
    end
  end

  # Raised when TCP connect exceeds `--timeout`. The stdlib event loops report
  # that as a bare `IO::TimeoutError("Connect timed out")`, which is otherwise
  # indistinguishable from a read timeout.
  class ConnectTimeoutError < IO::TimeoutError
  end

  # Maps transport exceptions onto a fixed vocabulary. v5 reported Crystal
  # exception class names, which made the JSON report a hostage of stdlib
  # refactors; these names are part of the documented schema instead.
  module ErrorCategory
    extend self

    DNS_FAILURE       = "dns_failure"
    CONNECT_REFUSED   = "connect_refused"
    CONNECT_TIMEOUT   = "connect_timeout"
    CONNECT_FAILED    = "connect_failed"
    READ_TIMEOUT      = "read_timeout"
    WRITE_TIMEOUT     = "write_timeout"
    REQUEST_TIMEOUT   = "request_timeout"
    CONNECTION_RESET  = "connection_reset"
    CONNECTION_CLOSED = "connection_closed"
    TLS_ERROR         = "tls_error"
    PROXY_ERROR       = "proxy_error"
    PROTOCOL_ERROR    = "protocol_error"
    OTHER             = "other"

    ALL = [
      DNS_FAILURE, CONNECT_REFUSED, CONNECT_TIMEOUT, CONNECT_FAILED,
      READ_TIMEOUT, WRITE_TIMEOUT, REQUEST_TIMEOUT, CONNECTION_RESET,
      CONNECTION_CLOSED, TLS_ERROR, PROXY_ERROR, PROTOCOL_ERROR, OTHER,
    ]

    def of(ex : Exception) : String
      case ex
      when RequestTimeoutError      then REQUEST_TIMEOUT
      when Socket::Addrinfo::Error  then DNS_FAILURE
      when Socket::ConnectError     then connect_category(ex.message)
      when ConnectTimeoutError      then CONNECT_TIMEOUT
      when OpenSSL::SSL::Error      then TLS_ERROR
      when OpenSSL::Error           then TLS_ERROR
      when IO::EOFError             then CONNECTION_CLOSED
      when IO::TimeoutError         then timeout_category(ex.message)
      when Socket::Error, IO::Error then io_category(ex.message)
      else                               OTHER
      end
    end

    private def connect_category(message : String?) : String
      text = message.to_s.downcase
      return CONNECT_TIMEOUT if text.includes?("timed out") || text.includes?("timeout")
      return CONNECT_REFUSED if text.includes?("refused")
      CONNECT_FAILED
    end

    # `IO::TimeoutError` carries no direction, so the message is the only signal
    # available; reads dominate in practice, hence the default.
    private def timeout_category(message : String?) : String
      message.to_s.downcase.includes?("write") ? WRITE_TIMEOUT : READ_TIMEOUT
    end

    private def io_category(message : String?) : String
      text = message.to_s.downcase
      return PROXY_ERROR if text.includes?("proxy")
      return CONNECTION_RESET if text.includes?("reset") || text.includes?("broken pipe")
      return CONNECTION_CLOSED if text.includes?("closed") || text.includes?("end of")
      return PROTOCOL_ERROR if text.includes?("http") || text.includes?("chunked")
      OTHER
    end
  end
end
