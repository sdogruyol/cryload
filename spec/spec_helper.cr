require "spec"
require "../src/cryload"

PROJECT_ROOT = File.expand_path("..", __DIR__)
CRYLOAD_BIN = File.join(PROJECT_ROOT, "bin", "cryload")

unless File.exists?(CRYLOAD_BIN)
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
