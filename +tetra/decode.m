function pdus = decode(y, cfg)
%DECODE Native MATLAB TETRA DMO control PDU decode from centered IQ.
if nargin < 2 || isempty(cfg)
    cfg = tetra.config();
end
cfg = applyScanWindow(cfg);

if isstruct(y)
    iq = y.iq(:);
    fs = y.sampleRate;
else
    iq = y(:);
    fs = cfg.frontendSampleRateHz;
end
if isempty(iq)
    pdus = struct([]);
    return;
end
iq = iq - mean(iq);

[iq72, ~, ~] = common.resampleTo(iq, fs, cfg.frontendSampleRateHz);
fs72 = cfg.frontendSampleRateHz;
[activeIq, activeInfo] = tetra.activeWindow(iq72, fs72, cfg);
if isempty(activeIq)
    pdus = struct([]);
    return;
end

context = struct();
context.activeStartSec = activeInfo.startSec;
context.activeEndSec = activeInfo.endSec;
[pdus, ~] = tetra.decodeIqWindow(activeIq, fs72, cfg, context);
end

function cfg = applyScanWindow(cfg)
cfg.activePrePadSec = getCfg(cfg, 'scanActivePrePadSec', cfg.activePrePadSec);
cfg.activePostPadSec = getCfg(cfg, 'scanActivePostPadSec', cfg.activePostPadSec);
cfg.activeMaxSec = getCfg(cfg, 'scanActiveMaxSec', cfg.activeMaxSec);
end

function value = getCfg(cfg, name, defaultValue)
if isfield(cfg, name)
    value = cfg.(name);
else
    value = defaultValue;
end
end
