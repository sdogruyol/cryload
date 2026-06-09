require "http/server"
require "openssl"

module TestTls
  CERT = File.join(Dir.tempdir, "cryload-spec-cert.pem")
  KEY  = File.join(Dir.tempdir, "cryload-spec-key.pem")

  unless File.exists?(CERT) && File.exists?(KEY)
    status = Process.run(
      "openssl",
      ["req", "-x509", "-newkey", "rsa:2048", "-keyout", KEY, "-out", CERT, "-days", "1", "-nodes", "-subj", "/CN=localhost"],
      output: Process::Redirect::Close,
      error: Process::Redirect::Close,
    )
    raise "Failed to generate self-signed TLS certificate for specs" unless status.success?
  end

  def self.server_context : OpenSSL::SSL::Context::Server
    context = OpenSSL::SSL::Context::Server.new
    context.certificate_chain = CERT
    context.private_key = KEY
    context
  end

  def self.start(&handler : HTTP::Server::Context ->)
    server = HTTP::Server.new(&handler)
    address = server.bind_tls("127.0.0.1", 0, server_context)
    spawn { server.listen }
    sleep 50.milliseconds
    {server, address.port}
  end
end
