function pdus = postprocess(pdus)
%POSTPROCESS Normalize native NXDN PDU structs.
pdus = radio.normalizePdus(pdus);
end
