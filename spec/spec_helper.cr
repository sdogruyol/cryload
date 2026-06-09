require "spec"
require "../src/cryload"

PROJECT_ROOT = File.expand_path("..", __DIR__)
CRYLOAD_BIN  = File.join(PROJECT_ROOT, "bin", "cryload")

def cryload_sources_mtime : Time
  paths = Dir.glob(File.join(PROJECT_ROOT, "src", "**", "*.cr")) + [File.join(PROJECT_ROOT, "shard.yml")]
  paths.max_of { |path| File.info(path).modification_time }
end

needs_build = !File.exists?(CRYLOAD_BIN) ||
              File.info(CRYLOAD_BIN).modification_time < cryload_sources_mtime

if needs_build
  STDERR.puts "Building cryload for specs..."
  status = Process.run("shards", ["build"], chdir: PROJECT_ROOT)
  raise "Failed to build cryload binary (exit #{status.exit_code})" unless status.success?
end

def run_cryload(args : Array(String), *, output : IO, error : IO? = nil, chdir : String = PROJECT_ROOT)
  if error
    Process.run(CRYLOAD_BIN, args, output: output, error: error, chdir: chdir)
  else
    Process.run(CRYLOAD_BIN, args, output: output, chdir: chdir)
  end
end
