require "./spec_helper"

describe Cryload::Cli::Validator do
  it "parses single and ranged success status codes" do
    ranges = Cryload::Cli::Validator.parse_success_status_ranges("200-299,301,304")
    ranges.should eq([200..299, 301..301, 304..304])
  end

  it "rejects invalid success status ranges" do
    expect_raises(ArgumentError, /Invalid success status range/) do
      Cryload::Cli::Validator.parse_success_status_ranges("500-400")
    end
  end

  it "validates http(s) URLs" do
    Cryload::Cli::Validator.valid_url?("http://localhost:3000").should be_true
    Cryload::Cli::Validator.valid_url?("https://example.com/api").should be_true
    Cryload::Cli::Validator.valid_url?("ftp://example.com").should be_false
    Cryload::Cli::Validator.valid_url?("not-a-url").should be_false
  end

  it "validates cookie format" do
    Cryload::Cli::Validator.valid_cookie?("session=abc").should be_true
    Cryload::Cli::Validator.valid_cookie?("invalid").should be_false
  end
end

describe Cryload::Cli::OptionsBuilder do
  it "merges cookies into request headers" do
    options = Cryload::Cli::Options.new
    options.cookies = ["session=abc", "theme=dark"]
    headers = Cryload::Cli::OptionsBuilder.build_headers(options)
    headers["Cookie"].should eq("session=abc; theme=dark")
  end

  it "resolves json output format from --json flag" do
    options = Cryload::Cli::Options.new
    options.json = true
    Cryload::Cli::OptionsBuilder.resolve_output_format(options).should eq("json")
  end
end
