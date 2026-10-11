module Cryload
  # Open-loop pacer: slots are reserved on an absolute schedule anchored to the
  # benchmark start, so the requested rate is a constant arrival rate rather
  # than a per-worker throttle.
  #
  # The schedule is never re-anchored to "now". v5 clamped the next slot to the
  # current time, so when every worker blocked on a stalled target nobody
  # advanced the schedule and the missed slots were erased: the run silently
  # issued fewer requests than asked for and the outage never showed up in the
  # percentiles. Keeping the schedule monotonic turns that backlog into
  # measurable send delay, which is what corrected latency is computed from.
  class RateLimiter
    # One request per ~32 years. Anything slower has a slot interval that no
    # longer fits the Int64 nanosecond schedule.
    MIN_RATE = 1e-9

    getter interval_ns : Int64
    getter reference : Time::Instant

    # Shared by the limiter and by the report, so the number of slots the
    # schedule hands out is computed exactly one way.
    def self.interval_ns_for(rate : Float64) : Int64
      interval = (1_000_000_000.0 / rate).round.to_i64
      interval < 1 ? 1_i64 : interval
    end

    # Slots the schedule hands out over `span`, counting the slot at offset 0.
    def self.scheduled_count(rate : Float64, span : Time::Span) : Int64
      return 0_i64 unless span.positive?
      (span.total_nanoseconds / interval_ns_for(rate)).ceil.to_i64
    end

    def initialize(rate : Float64, @reference : Time::Instant = Time.instant)
      @interval_ns = RateLimiter.interval_ns_for(rate)
      @next_slot = Atomic(Int64).new(0_i64)
    end

    # Reserves the next slot and sleeps until it is due. Returns the instant the
    # request was *scheduled* for, which is the baseline for corrected latency,
    # or nil when the reserved slot falls at or past `deadline` (run is over).
    def acquire(deadline : Time::Instant? = nil) : Time::Instant?
      deadline_ns = deadline.try { |instant| elapsed_ns(instant) }

      loop do
        current_ns = @next_slot.get
        return if deadline_ns && current_ns >= deadline_ns

        _, succeeded = @next_slot.compare_and_set(current_ns, current_ns + @interval_ns)
        next unless succeeded

        scheduled = @reference + Time::Span.new(nanoseconds: current_ns)
        pending = scheduled - Time.instant
        sleep pending if pending.positive?
        return scheduled
      end
    end

    private def elapsed_ns(instant : Time::Instant) : Int64
      (instant - @reference).total_nanoseconds.to_i64
    end
  end
end
