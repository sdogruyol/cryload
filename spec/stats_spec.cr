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

    stats.record_response(10.0, 200)
    stats.record_response(20.0, 404)
    stats.record_response(30.0, 201)

    stats.empty?.should be_false
    stats.total_request_count.should eq(3)
    stats.response_count.should eq(3)
    stats.transport_error_count.should eq(0)
    stats.ok_requests.should eq(2)
    stats.not_ok_requests.should eq(1)
    stats.average_request_time.should be_close(20.0, 0.001)
    stats.max_request_time.should be_close(30.0, 0.001)
    stats.latency_stdev.should be_close(8.1649, 0.001)
    stats.status_code_counts.should eq({200 => 1_i64, 201 => 1_i64, 404 => 1_i64})
  end

  it "calculates p95 and p99 from histogram" do
    stats = Cryload::Stats.new(100)

    (1..100).each do |latency_ms|
      stats.record_response(latency_ms.to_f, 200)
    end

    stats.p50_request_time.should eq(50.0)
    stats.p90_request_time.should eq(90.0)
    stats.p95_request_time.should eq(95.0)
    stats.p99_request_time.should eq(99.0)
    stats.p999_request_time.should eq(100.0)
  end

  it "tracks transport errors without losing run progress" do
    stats = Cryload::Stats.new(5)

    stats.record_error(5.0, "Socket::ConnectError")
    stats.record_response(15.0, 200)

    stats.total_request_count.should eq(2)
    stats.response_count.should eq(1)
    stats.transport_error_count.should eq(1)
    stats.error_counts.should eq({"Socket::ConnectError" => 1_i64})
    stats.final_exit_code.should eq(0)
  end

  it "returns a failing exit code when every attempt is a transport error" do
    stats = Cryload::Stats.new(2)

    stats.record_error(5.0, "Socket::ConnectError")
    stats.record_error(8.0, "Socket::ConnectError")

    stats.final_exit_code.should eq(1)
  end
end
