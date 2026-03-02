require "./cryload"

Process.on_terminate do
  Cryload::Logger.log_final
  exit
end

Cryload::Cli.new
