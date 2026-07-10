%% Standalone NXDN96 data-PDU decoder
% This entry does not use or modify the unified scanner registry.

TARGET_FILE = fullfile(fileparts(mfilename('fullpath')), ...
    'signal_data', 'nxdn96_1_78125.rawiq');
SAMPLE_RATE = [];
IQ_DTYPE = 'int16';
DEDUPLICATE = true;
WRITE_JSON = false;
JSON_PATH = fullfile(tempdir, 'nxdn96_pdus.json');

%% Run
projectRoot = fileparts(mfilename('fullpath'));
addpath(projectRoot);
startup;

if isempty(SAMPLE_RATE)
    SAMPLE_RATE = common.detectSampleRate(TARGET_FILE);
end
iq = common.readRawIq(TARGET_FILE, 'DType', IQ_DTYPE);
[rawPdus, report] = nxdn.decodeIq(iq, SAMPLE_RATE, nxdn.config());
if DEDUPLICATE
    pdus = nxdn.deduplicatePdus(rawPdus);
else
    pdus = rawPdus; %#ok<UNRCH>
end

fprintf('\n=== NXDN96 standalone: %s ===\n', TARGET_FILE);
fprintf('Sample rate: %.0f Hz\n', SAMPLE_RATE);
fprintf('Sync candidates: %d\n', numel(report.syncCandidates));
fprintf('Valid frames: %d\n', report.validFrameCount);
fprintf('CRC-valid channel blocks: %d\n', report.validChannelBlockCount);
fprintf('Raw PDUs: %d, displayed PDUs: %d\n\n', numel(rawPdus), numel(pdus));
for k = 1:numel(pdus)
    fprintf('%s\n', nxdn.formatPdu(pdus(k)));
end
if WRITE_JSON
    radio.writeJson(pdus, JSON_PATH, 'IncludeRawBits', true); %#ok<UNRCH>
    fprintf('\nJSON written: %s\n', JSON_PATH);
end
