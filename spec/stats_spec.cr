require "./spec_helper"

describe Cryload::Stats do
  it "starts empty with zeroed metrics" do
    stats = Cryload::Stats.new(10)

    stats.empty?.should be_true
    stats.total_request_count.should eq(0)
    stats.ok_requests.should eq(0)
    stats.not_ok_requests.should eq(0)
    stats.average_request_time.should eq(0.0)
    stats.max_request_time.should eq(0.0)
    stats.latency_stdev.should eq(0.0)
    stats.p95_request_time.should eq(0.0)
    stats.p99_request_time.should eq(0.0)
  end

  it "updates aggregate counters and latency stats" do
    stats = Cryload::Stats.new(10)

    stats.record_request(10.0, true)
    stats.record_request(20.0, false)
    stats.record_request(30.0, true)

    stats.empty?.should be_false
    stats.total_request_count.should eq(3)
    stats.ok_requests.should eq(2)
    stats.not_ok_requests.should eq(1)
    stats.average_request_time.should be_close(20.0, 0.001)
    stats.max_request_time.should be_close(30.0, 0.001)
    stats.latency_stdev.should be_close(8.1649, 0.001)
  end

  it "calculates p95 and p99 from histogram" do
    stats = Cryload::Stats.new(100)

    (1..100).each do |latency_ms|
      stats.record_request(latency_ms.to_f, true)
    end

    stats.p95_request_time.should eq(95.0)
    stats.p99_request_time.should eq(99.0)
  end
end
