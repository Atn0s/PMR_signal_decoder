function pdus = postprocess(pdus)
%POSTPROCESS Normalize TETRA PDUs for the shared radio output layer.
pdus = radio.normalizePdus(pdus);
end
