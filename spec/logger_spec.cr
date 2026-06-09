require "./spec_helper"
require "csv"

describe Cryload::Logger do
  it "builds structured JSON documents from stats" do
    stats = Cryload::Stats.new(3, url: "http://example.test/run")
    stats.record_response(10.0, 200, 12)
    stats.record_response(20.0, 404, 8)
    stats.record_error(5.0, "Socket::ConnectError")

    parsed = JSON.parse(Cryload::Logger.json_document(stats))

    parsed["url"].as_s.should eq("http://example.test/run")
    parsed["summary"]["requests"].as_i.should eq(3)
    parsed["summary"]["responses"].as_i.should eq(2)
    parsed["summary"]["transport_errors"].as_i.should eq(1)
    parsed["summary"]["failure_rate_percent"].as_f.should eq(66.67)
    parsed["latency_ms"]["p50"].as_f.should eq(10.0)
    parsed["status"]["successful_count"].as_i.should eq(1)
    parsed["status"]["failed_count"].as_i.should eq(1)
    parsed["status"]["codes"].as_a.size.should eq(2)
    parsed["status"]["transport_errors"].as_a.first["category"].as_s.should eq("Socket::ConnectError")
    parsed["latency_histogram"].as_a.size.should be > 0
  end

  it "builds CSV documents with stable headers and values" do
    stats = Cryload::Stats.new(2, url: "http://example.test/csv", duration_mode: true)
    stats.record_response(15.0, 201, 100)
    stats.record_response(25.0, 201, 50)

    rows = CSV.parse(Cryload::Logger.csv_document(stats))
    rows.size.should eq(2)

    headers = rows[0]
    values = rows[1]

    headers[0].should eq("url")
    headers[1].should eq("duration_mode")
    values[0].should eq("http://example.test/csv")
    values[1].should eq("true")
    values[2].should eq("2")
    values[3].should eq("2")
    values[4].should eq("0")
    values[headers.index!("latency_p95_ms")].should eq("25.0")
    values[headers.index!("status_successful_count")].should eq("2")
  end
end
