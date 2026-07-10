function specs = protocolRegistry()
%PROTOCOLREGISTRY Return protocol specs matching the Python ProtocolSpec shape.
specs = [dmr.spec(), p25.spec(), dpmr.spec(), nxdn.spec(), tetra.spec()];
end
