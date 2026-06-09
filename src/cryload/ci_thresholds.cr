module Cryload
  struct CiThresholds
    property? fail_on_error : Bool
    property? fail_on_transport_error : Bool
    property max_fail_rate : Float64?
    property max_p99_ms : Float64?

    def initialize(
      @fail_on_error : Bool = false,
      @fail_on_transport_error : Bool = false,
      @max_fail_rate : Float64? = nil,
      @max_p99_ms : Float64? = nil,
    )
    end
  end
end
