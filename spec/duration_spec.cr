require "./spec_helper"

describe Cryload::Duration do
  describe ".parse" do
    it "reads a bare number as seconds" do
      Cryload::Duration.parse("30", "-d").should eq(30.seconds)
      Cryload::Duration.parse("1", "-d").should eq(1.second)
    end

    it "reads a bare fractional number as fractional seconds" do
      Cryload::Duration.parse("0.5", "-d").should eq(500.milliseconds)
      Cryload::Duration.parse("1.5", "-d").should eq(1500.milliseconds)
    end

    it "parses zero so --warmup 0 means no warmup" do
      Cryload::Duration.parse("0", "--warmup").should eq(Time::Span.zero)
      Cryload::Duration.parse("0s", "--warmup").should eq(Time::Span.zero)
    end

    it "parses every unit suffix" do
      Cryload::Duration.parse("500ms", "--request-timeout").should eq(500.milliseconds)
      Cryload::Duration.parse("30s", "-d").should eq(30.seconds)
      Cryload::Duration.parse("2m", "-d").should eq(120.seconds)
      Cryload::Duration.parse("1h", "-d").should eq(3600.seconds)
    end

    it "parses composed units" do
      Cryload::Duration.parse("1h30m", "-d").should eq(90.minutes)
      Cryload::Duration.parse("1m30s", "-d").should eq(90.seconds)
      Cryload::Duration.parse("1h30m15s", "-d").should eq(3600.seconds + 1800.seconds + 15.seconds)
    end

    it "treats 90s and 1m30s as the same span" do
      Cryload::Duration.parse("90s", "-d").should eq(Cryload::Duration.parse("1m30s", "-d"))
    end

    it "parses fractional units" do
      Cryload::Duration.parse("1.5s", "--timeout").should eq(1500.milliseconds)
      Cryload::Duration.parse("0.5m", "-d").should eq(30.seconds)
      Cryload::Duration.parse("2.5ms", "--request-timeout").should eq(2500.microseconds)
    end

    it "is case insensitive" do
      Cryload::Duration.parse("30S", "-d").should eq(30.seconds)
      Cryload::Duration.parse("1H30M", "-d").should eq(90.minutes)
      Cryload::Duration.parse("500MS", "-d").should eq(500.milliseconds)
    end

    it "ignores surrounding whitespace" do
      Cryload::Duration.parse("  30s  ", "-d").should eq(30.seconds)
      Cryload::Duration.parse("\t1h30m\n", "-d").should eq(90.minutes)
      Cryload::Duration.parse(" 45 ", "-d").should eq(45.seconds)
    end

    it "rejects an empty value and names the flag" do
      expect_raises(ArgumentError, /Invalid duration '' for --warmup/) do
        Cryload::Duration.parse("", "--warmup")
      end
      expect_raises(ArgumentError, /for --timeout/) do
        Cryload::Duration.parse("   ", "--timeout")
      end
    end

    it "rejects non-numeric text" do
      expect_raises(ArgumentError, /Invalid duration 'abc' for -d/) do
        Cryload::Duration.parse("abc", "-d")
      end
    end

    it "rejects an unknown unit" do
      expect_raises(ArgumentError, /Invalid duration '5x' for -d/) do
        Cryload::Duration.parse("5x", "-d")
      end
    end

    it "rejects garbage between tokens instead of skipping it" do
      expect_raises(ArgumentError, /Invalid duration '10x5s' for -d/) do
        Cryload::Duration.parse("10x5s", "-d")
      end
    end

    it "rejects trailing garbage" do
      expect_raises(ArgumentError, /Invalid duration '5s!' for --request-timeout/) do
        Cryload::Duration.parse("5s!", "--request-timeout")
      end
    end

    it "rejects a bare unit with no amount" do
      expect_raises(ArgumentError, /Invalid duration 's' for -d/) do
        Cryload::Duration.parse("s", "-d")
      end
    end

    it "rejects a negative duration" do
      expect_raises(ArgumentError, /Invalid duration '-5s' for -d/) do
        Cryload::Duration.parse("-5s", "-d")
      end
      expect_raises(ArgumentError, /Invalid duration '-5' for -d/) do
        Cryload::Duration.parse("-5", "-d")
      end
    end

    it "rejects whitespace between the amount and the unit" do
      expect_raises(ArgumentError, /Invalid duration '5 s' for -d/) do
        Cryload::Duration.parse("5 s", "-d")
      end
    end

    it "rejects values a Time::Span cannot hold instead of overflowing" do
      ["inf", "nan", "1e10", "99999999999h"].each do |raw|
        expect_raises(ArgumentError, /Invalid duration '#{Regex.escape(raw)}' for -d/) do
          Cryload::Duration.parse(raw, "-d")
        end
      end
    end
  end

  describe ".format" do
    it "formats a zero span as 0s" do
      Cryload::Duration.format(Time::Span.zero).should eq("0s")
    end

    it "renders the canonical spelling of each shape" do
      Cryload::Duration.format(500.milliseconds).should eq("500ms")
      Cryload::Duration.format(30.seconds).should eq("30s")
      Cryload::Duration.format(2.minutes).should eq("2m")
      Cryload::Duration.format(90.minutes).should eq("1h30m")
    end

    it "round-trips through parse" do
      ["500ms", "30s", "2m", "1h30m"].each do |raw|
        span = Cryload::Duration.parse(raw, "-d")
        formatted = Cryload::Duration.format(span)
        Cryload::Duration.parse(formatted, "-d").should eq(span)
      end
    end

    it "formats spans whose hour count overflows Int32 seconds" do
      Cryload::Duration.format(600_000.hours).should eq("600000h")
    end
  end
end
