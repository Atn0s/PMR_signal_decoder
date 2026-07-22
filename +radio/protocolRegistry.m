function specs = protocolRegistry()
%PROTOCOLREGISTRY Return native decoder specifications.
specs = [dmr.spec(), p25.spec(), dpmr.spec(), nxdn.spec(), tetra.spec()];
end
