require "./spec_helper"

describe Cryload::RateLimiter do
  it "spaces requests according to the configured rate" do
    limiter = Cryload::RateLimiter.new(10)
    started_at = Time.instant

    3.times { limiter.acquire.should be_true }

    elapsed = (Time.instant - started_at).total_seconds
    elapsed.should be >= 0.15
    elapsed.should be < 0.5
  end

  it "stops acquiring after the deadline in duration mode" do
    limiter = Cryload::RateLimiter.new(1)
    deadline = Time.instant + 50.milliseconds

    limiter.acquire(deadline).should be_true
    limiter.acquire(deadline).should be_false
  end

  it "coordinates concurrent workers without overshooting rate" do
    limiter = Cryload::RateLimiter.new(20)
    started_at = Time.instant
    counter = Atomic(Int32).new(0)

    4.times do
      spawn do
        5.times do
          limiter.acquire
          counter.add(1)
        end
      end
    end

    4.times { Fiber.yield }
    sleep 200.milliseconds
    until counter.get == 20
      Fiber.yield
      break if (Time.instant - started_at).total_seconds > 2.0
    end

    elapsed = (Time.instant - started_at).total_seconds
    counter.get.should eq(20)
    elapsed.should be >= 0.8
  end
end
