# Crystal 1.21.1 (crystal-lang/crystal#17436) made non-blocking `connect` read
# the socket's SO_ERROR after waiting, but then raises
# `Socket::ConnectError.from_errno`, which reads the global errno, still holding
# the stale EINPROGRESS/EAGAIN. A refused connection is thus reported as
# "Operation now in progress" and `ErrorCategory` can no longer tell
# connect_refused from connect_failed. These overrides are the upstream methods
# with the SO_ERROR value passed through `from_os_error`, as the io_uring loop
# already does. Drop once the minimum supported Crystal carries the fix.
{% if flag?(:unix) && compare_versions(Crystal::VERSION, "1.21.1") >= 0 %}
  {% if Crystal::EventLoop.has_constant?(:Polling) %}
    abstract class Crystal::EventLoop::Polling < Crystal::EventLoop
      def connect(socket : ::Socket, address : ::Socket::Addrinfo | ::Socket::Address, timeout : Time::Span?) : IO::Error?
        ret = LibC.connect(socket.fd, address, address.size)
        return unless ret == -1

        errno = Errno.value

        loop do
          case errno
          when Errno::EINPROGRESS, Errno::EALREADY
            wait_writable(socket, timeout) do
              return IO::TimeoutError.new("Connect timed out")
            end
            errno = Crystal::System::Socket.system_error(socket.fd)
            return if errno.none?
          else
            return ::Socket::ConnectError.from_os_error("connect", errno)
          end
        end
      end
    end
  {% end %}

  {% if Crystal::EventLoop.has_constant?(:LibEvent) %}
    class Crystal::EventLoop::LibEvent < Crystal::EventLoop
      def connect(socket : ::Socket, address : ::Socket::Addrinfo | ::Socket::Address, timeout : ::Time::Span?) : IO::Error?
        ret = LibC.connect(socket.fd, address, address.size)
        return unless ret == -1

        errno = Errno.value

        loop do
          case errno
          when Errno::EINPROGRESS, Errno::EALREADY
            socket.evented_wait_writable(timeout: timeout) do
              return IO::TimeoutError.new("connect timed out")
            end
            errno = Crystal::System::Socket.system_error(socket.fd)
            return if errno.none?
          else
            return ::Socket::ConnectError.from_os_error("connect", errno)
          end
        end
      end
    end
  {% end %}
{% end %}
