module Cryload
  class RateLimiter
    @interval_ns : Int64
    @reference : Time::Instant
    @next_slot : Atomic(Int64)

    def initialize(rate_limit : Int32)
      @interval_ns = (1_000_000_000.0 / rate_limit).round.to_i64
      @reference = Time.instant
      @next_slot = Atomic(Int64).new(0_i64)
    end

    def acquire(deadline : Time::Instant? = nil) : Bool
      deadline_ns = deadline ? elapsed_ns(deadline) : nil

      loop do
        now_ns = elapsed_ns(Time.instant)
        current_ns = @next_slot.get
        scheduled_ns = current_ns > now_ns ? current_ns : now_ns
        return false if deadline_ns && scheduled_ns >= deadline_ns

        next_ns = scheduled_ns + @interval_ns
        if @next_slot.compare_and_set(current_ns, next_ns)
          sleep_ns = scheduled_ns - now_ns
          sleep Time::Span.new(nanoseconds: sleep_ns) if sleep_ns > 0
          return true
        end
      end
    end

    private def elapsed_ns(instant : Time::Instant) : Int64
      ((instant - @reference).total_nanoseconds).to_i64
    end
  end
end
