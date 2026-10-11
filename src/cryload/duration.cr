module Cryload
  # Parses the duration syntax shared by `-d`, `--timeout`, `--request-timeout`
  # and `--warmup`. A bare number means seconds, so every v5 invocation keeps
  # working; unit suffixes can be combined (`1h30m`).
  module Duration
    extend self

    TOKEN = /(\d+(?:\.\d+)?)(ms|s|m|h)/

    SECONDS_PER_UNIT = {
      "ms" => 0.001,
      "s"  => 1.0,
      "m"  => 60.0,
      "h"  => 3600.0,
    }

    def parse(raw : String, flag : String) : Time::Span
      text = raw.strip.downcase
      raise ArgumentError.new(message(raw, flag)) if text.empty?

      if plain = text.to_f64?
        raise ArgumentError.new(message(raw, flag)) if plain < 0
        return span(plain, raw, flag)
      end

      total_seconds = 0.0
      consumed = 0
      text.scan(TOKEN) do |match|
        # Anchoring each token to the end of the previous one rejects garbage
        # between or around the tokens (`10x5s`, `5s!`) instead of silently
        # skipping it, which a bare scan would do.
        raise ArgumentError.new(message(raw, flag)) unless match.begin == consumed
        total_seconds += match[1].to_f * SECONDS_PER_UNIT[match[2]]
        consumed = match.end
      end

      raise ArgumentError.new(message(raw, flag)) unless consumed == text.size && consumed > 0
      span(total_seconds, raw, flag)
    end

    def format(span : Time::Span) : String
      total_ms = span.total_milliseconds
      return "0s" if total_ms <= 0
      return "#{trim(total_ms)}ms" if total_ms < 1000

      hours = span.total_hours.to_i64
      minutes = span.minutes
      seconds = span.total_seconds - (hours * 3600) - (minutes * 60)

      String.build do |io|
        io << hours << 'h' if hours > 0
        io << minutes << 'm' if minutes > 0
        io << trim(seconds) << 's' if seconds > 0 || (hours == 0 && minutes == 0)
      end
    end

    # `Time::Span` holds Int64 nanoseconds (~292 years); NaN, infinity and
    # anything beyond that would otherwise surface as an OverflowError.
    private def span(total_seconds : Float64, raw : String, flag : String) : Time::Span
      nanoseconds = total_seconds * 1_000_000_000.0
      unless nanoseconds.finite? && nanoseconds < Int64::MAX.to_f
        raise ArgumentError.new(message(raw, flag))
      end
      Time::Span.new(nanoseconds: nanoseconds.round.to_i64)
    end

    private def trim(value : Float64) : String
      rounded = value.round(3)
      rounded == rounded.trunc ? rounded.to_i64.to_s : rounded.to_s
    end

    private def message(raw : String, flag : String) : String
      "Invalid duration '#{raw}' for #{flag}: use seconds (30) or a unit suffix (500ms, 30s, 2m, 1h30m)."
    end
  end
end
