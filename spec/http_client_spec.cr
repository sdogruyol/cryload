require "./spec_helper"

describe Cryload do
  describe ".load_urls_from_file" do
    it "loads http(s) URLs and skips blanks and comments" do
      path = File.join(Dir.tempdir, "cryload-urls-#{Random.rand(100_000)}.txt")
      File.write(path, <<-URLS)
        # primary
        http://localhost:3000

        https://example.com/api
      URLS

      urls = Cryload.load_urls_from_file(path)
      urls.size.should eq(2)
      urls[0].to_s.should eq("http://localhost:3000")
      urls[1].to_s.should eq("https://example.com/api")
    ensure
      File.delete?(path) if path
    end

    it "raises when the file has no valid URLs" do
      path = File.join(Dir.tempdir, "cryload-urls-empty-#{Random.rand(100_000)}.txt")
      File.write(path, "# only comments\n\n")

      expect_raises(ArgumentError, /must not be empty/) do
        Cryload.load_urls_from_file(path)
      end
    ensure
      File.delete?(path) if path
    end
  end

  describe ".display_url" do
    it "shows a single URL unchanged" do
      urls = [URI.parse("http://localhost:3000")]
      Cryload.display_url(urls).should eq("http://localhost:3000")
    end

    it "summarizes multiple URLs" do
      urls = [
        URI.parse("http://localhost:3000"),
        URI.parse("http://localhost:4000"),
      ]
      Cryload.display_url(urls).should eq("http://localhost:3000 (+1 more)")
    end
  end
end
