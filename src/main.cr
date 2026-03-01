require "./cryload"

Signal::INT.trap do
  Cryload::Logger.log_final
  exit
end

Cryload::Cli.new
