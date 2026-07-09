function y = frontend(iqDec, sampleRate, cfg)
%FRONTEND Preserve complex IQ for the TETRA pi/4-DQPSK decoder.
if nargin < 3 || isempty(cfg)
    cfg = tetra.config();
end
if nargin < 2 || isempty(sampleRate)
    sampleRate = cfg.frontendSampleRateHz;
end
y = struct( ...
    'iq', iqDec(:), ...
    'sampleRate', sampleRate);
end
