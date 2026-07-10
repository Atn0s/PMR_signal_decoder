function [pdus, report] = decodeIq(iq, sampleRate, cfg)
%DECODEIQ Standalone NXDN96 decode from centered complex IQ.
if nargin < 3 || isempty(cfg)
    cfg = nxdn.config();
end
[y, frontendInfo] = nxdn.frontend(iq, sampleRate, cfg);
[pdus, report] = nxdn.decode(y, cfg);
report.frontend = frontendInfo;
end
