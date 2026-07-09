function result = scanFileWindows(path, varargin)
%SCANFILEWINDOWS TETRA-only full-file multi-window DMO control scan.
p = inputParser;
p.addParameter('SampleRate', []);
p.addParameter('IqDType', 'int16');
p.addParameter('OutputDir', '');
p.addParameter('WriteOutputs', true);
p.addParameter('ShowProgress', true);
p.addParameter('MaxWindows', []);
p.addParameter('WindowSec', []);
p.addParameter('OverlapSec', []);
p.addParameter('MergeGapSec', []);
p.addParameter('PrePadSec', []);
p.addParameter('PostPadSec', []);
p.parse(varargin{:});

cfg = tetra.config();
cfg = applyOverrides(cfg, p.Results);

iq = common.readRawIq(path, 'DType', p.Results.IqDType);
fs = p.Results.SampleRate;
if isempty(fs)
    fs = common.detectSampleRate(path);
end
if isempty(fs)
    error('tetra:scanFileWindows:MissingSampleRate', ...
        'Sample rate is required; pass SampleRate or use WAV metadata.');
end
iq = iq(:);
iq = iq - mean(iq);

[iq72, up, down] = common.resampleTo(iq, fs, cfg.frontendSampleRateHz);
fs72 = cfg.frontendSampleRateHz;
[windows, envelope] = tetra.scanActiveWindows(iq72, fs72, cfg);
if ~isempty(p.Results.MaxWindows)
    windows = windows(1:min(numel(windows), p.Results.MaxWindows));
end

if p.Results.ShowProgress
    fprintf('TETRA full-file scan: %.3f s input, %d active scan windows\n', ...
        numel(iq72) / fs72, numel(windows));
end

events = repmat(emptyPdu(), 0, 1);
windowReports = repmat(emptyWindowReport(), 0, 1);
for k = 1:numel(windows)
    w = windows(k);
    seg = iq72(w.startSample:w.endSample);
    context = struct();
    context.activeStartSec = w.startSec;
    context.activeEndSec = w.endSec;
    context.scanWindowIndex = w.index;
    [pdus, diag] = tetra.decodeIqWindow(seg, fs72, cfg, context);
    pdus = adjustPdusForWindow(pdus, w, cfg);
    pdus = dropSessionPdus(pdus);
    events = appendPdus(events, pdus);
    windowReports = appendWindowReport(windowReports, makeWindowReport(w, diag, numel(pdus)));
    if p.Results.ShowProgress
        fprintf('  window %02d/%02d %.3f-%.3f s: events=%d DSB=%d DNB=%d STCH=%d\n', ...
            k, numel(windows), w.startSec, w.endSec, numel(pdus), ...
            getSlotCount(diag, 'dsbCount'), getSlotCount(diag, 'dnbCount'), ...
            getSlotCount(diag, 'stchDecodedCount'));
    end
end

events = deduplicateScanPdus(sortPdusByTime(events));
sessions = tetra.sessionizePdus(events);
pdus = appendPdus(events, sessions);
pdus = radio.normalizePdus(pdus);
lines = radio.formatLines(pdus);

result = struct();
result.path = char(path);
result.inputSampleRateHz = fs;
result.targetSampleRateHz = fs72;
result.resampleUp = up;
result.resampleDown = down;
result.inputSamples = numel(iq);
result.resampledSamples = numel(iq72);
result.durationSec = numel(iq72) / fs72;
result.windows = windows;
result.windowReports = windowReports;
result.envelope = stripEnvelope(envelope);
result.summary = makeSummary(pdus, windows, windowReports);
result.pdus = pdus;
result.lines = lines;

outputDir = char(p.Results.OutputDir);
if isempty(outputDir)
    outputDir = '';
end
result.outputDir = outputDir;
if p.Results.WriteOutputs && ~isempty(outputDir)
    writeOutputs(result, outputDir);
end
end

function cfg = applyOverrides(cfg, opts)
if ~isempty(opts.WindowSec)
    cfg.fullScanWindowSec = opts.WindowSec;
end
if ~isempty(opts.OverlapSec)
    cfg.fullScanOverlapSec = opts.OverlapSec;
end
if ~isempty(opts.MergeGapSec)
    cfg.fullScanMergeGapSec = opts.MergeGapSec;
end
if ~isempty(opts.PrePadSec)
    cfg.fullScanPrePadSec = opts.PrePadSec;
end
if ~isempty(opts.PostPadSec)
    cfg.fullScanPostPadSec = opts.PostPadSec;
end
end

function pdus = adjustPdusForWindow(pdus, w, cfg)
pdus = radio.normalizePdus(pdus);
for k = 1:numel(pdus)
    extra = pdus(k).extra;
    extra.scan_window_index = w.index;
    extra.scan_window_start_s = w.startSec;
    extra.scan_window_end_s = w.endSec;
    extra.scan_window_mode = w.mode;
    extra.scan_window_split_index = w.splitIndex;
    extra.scan_window_start_sample = w.startSample;
    extra.scan_window_end_sample = w.endSample;
    if isfield(extra, 'slot_start_bit') && ~isempty(extra.slot_start_bit)
        extra.window_relative_slot_start_bit = extra.slot_start_bit;
        extra.absolute_slot_start_bit = bitIndexFromTime(extra.start_time_s, cfg);
        extra.slot_start_bit = extra.absolute_slot_start_bit;
    end
    if isfield(extra, 'slot_end_bit') && ~isempty(extra.slot_end_bit)
        extra.window_relative_slot_end_bit = extra.slot_end_bit;
        extra.absolute_slot_end_bit = bitIndexFromTime(extra.end_time_s, cfg);
        extra.slot_end_bit = extra.absolute_slot_end_bit;
    end
    if isfield(extra, 'start_bit') && ~isempty(extra.start_bit)
        extra.window_relative_start_bit = extra.start_bit;
        extra.absolute_start_bit = bitIndexFromTime(extra.start_time_s, cfg);
        extra.start_bit = extra.absolute_start_bit;
    end
    if isfield(extra, 'end_bit') && ~isempty(extra.end_bit)
        extra.window_relative_end_bit = extra.end_bit;
        extra.absolute_end_bit = bitIndexFromTime(extra.end_time_s, cfg);
        extra.end_bit = extra.absolute_end_bit;
    end
    pdus(k).extra = extra;
end
end

function bitIndex = bitIndexFromTime(sec, cfg)
if isempty(sec) || isnan(sec)
    bitIndex = NaN;
else
    bitIndex = round(double(sec) * 2 * cfg.symbolRateHz) + 1;
end
end

function pdus = dropSessionPdus(pdus)
if isempty(pdus)
    return;
end
keep = ~strcmp({pdus.type}, 'TETRA_SESSION');
pdus = pdus(keep);
end

function out = deduplicateScanPdus(pdus)
out = repmat(emptyPdu(), 0, 1);
if isempty(pdus)
    return;
end
seen = containers.Map('KeyType', 'char', 'ValueType', 'logical');
for k = 1:numel(pdus)
    key = scanPduKey(pdus(k));
    if isKey(seen, key)
        continue;
    end
    seen(key) = true;
    out = appendPdus(out, pdus(k));
end
end

function key = scanPduKey(pdu)
startTime = radio.getNestedField(pdu, 'extra.start_time_s', NaN);
if isnan(startTime)
    startTime = radio.getNestedField(pdu, 'extra.end_time_s', 0);
end
timeBucket = round(double(startTime) / 0.005);
key = jsonencode({ ...
    char(radio.getField(pdu, 'type', '')), ...
    radio.getField(pdu, 'src', 0), ...
    radio.getField(pdu, 'dst', 0), ...
    char(radio.getField(pdu, 'flco', '')), ...
    char(radio.getNestedField(pdu, 'extra.logical_channel', '')), ...
    char(radio.getNestedField(pdu, 'extra.block_name', '')), ...
    timeBucket});
end

function pdus = sortPdusByTime(pdus)
if isempty(pdus)
    return;
end
t = NaN(numel(pdus), 1);
for k = 1:numel(pdus)
    t(k) = radio.getNestedField(pdus(k), 'extra.start_time_s', ...
        radio.getNestedField(pdus(k), 'extra.end_time_s', k));
end
[~, order] = sort(t);
pdus = pdus(order);
end

function report = makeWindowReport(w, diag, pduCount)
report = emptyWindowReport();
report.index = w.index;
report.startSec = w.startSec;
report.endSec = w.endSec;
report.durationSec = w.durationSec;
report.mode = w.mode;
report.splitIndex = w.splitIndex;
report.meanPowerDb = w.meanPowerDb;
report.peakPowerDb = w.peakPowerDb;
report.pduCount = pduCount;
report.coarseFrequencyOffsetHz = diag.coarseFrequencyOffsetHz;
report.residualCorrectionHz = diag.residualCorrectionHz;
report.timingPhaseSamples = diag.timingPhaseSamples;
report.timingErrorRad = diag.timingErrorRad;
report.decisionVariant = diag.decisionVariant;
report.symbolCount = diag.symbolCount;
report.bitCount = diag.bitCount;
report.trainingCandidateCount = diag.training.candidateCount;
report.trainingGoodCount = diag.training.goodCount;
if isfield(diag, 'slots') && ~isempty(diag.slots)
    report.confirmedBursts = diag.slots.confirmedCount;
    report.dsbCount = diag.slots.dsbCount;
    report.dnbCount = diag.slots.dnbCount;
    report.dmacSyncDecodedCount = diag.slots.dmacSyncDecodedCount;
    report.stchDecodedCount = diag.slots.stchDecodedCount;
    report.schFDecodedCount = diag.slots.schFDecodedCount;
    report.timingAssignedCount = diag.slots.timingAssignedCount;
end
end

function n = getSlotCount(diag, fieldName)
n = 0;
if isfield(diag, 'slots') && isfield(diag.slots, fieldName)
    n = diag.slots.(fieldName);
end
end

function summary = makeSummary(pdus, windows, reports)
summary = struct();
summary.windowCount = numel(windows);
summary.decodedWindowCount = nnz([reports.pduCount] > 0);
summary.pduCount = numel(pdus);
summary.dmacSyncCount = countType(pdus, 'TETRA_DMAC_SYNC');
summary.stchCount = countType(pdus, 'TETRA_STCH');
summary.schfCount = countType(pdus, 'TETRA_SCHF');
summary.tchCandidateCount = countType(pdus, 'TETRA_TCH_CANDIDATE');
summary.sessionCount = countType(pdus, 'TETRA_SESSION');
summary.confirmedBurstCount = sum([reports.confirmedBursts]);
summary.dsbCount = sum([reports.dsbCount]);
summary.dnbCount = sum([reports.dnbCount]);
end

function n = countType(pdus, typeName)
if isempty(pdus)
    n = 0;
else
    n = nnz(strcmp({pdus.type}, typeName));
end
end

function envelope = stripEnvelope(envelope)
envelope = rmfield(envelope, intersect(fieldnames(envelope), ...
    {'windowPowerDb', 'windowTimesSec', 'activeMask'}));
end

function writeOutputs(result, outputDir)
if exist(outputDir, 'dir') ~= 7
    mkdir(outputDir);
end
save(fullfile(outputDir, 'full_file_scan_summary.mat'), 'result');
radio.writeJson(result.pdus, fullfile(outputDir, 'tetra_pdus.json'));
writeLines(result.lines, fullfile(outputDir, 'tetra_lines.txt'));
writeWindowCsv(result.windowReports, fullfile(outputDir, 'windows.csv'));
end

function writeLines(lines, path)
fid = fopen(path, 'w');
if fid < 0
    error('tetra:scanFileWindows:OpenFailed', 'Unable to write %s', path);
end
cleaner = onCleanup(@() fclose(fid));
for k = 1:numel(lines)
    fprintf(fid, '%s\n', lines{k});
end
end

function writeWindowCsv(reports, path)
fid = fopen(path, 'w');
if fid < 0
    error('tetra:scanFileWindows:OpenFailed', 'Unable to write %s', path);
end
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, 'index,start_s,end_s,duration_s,events,confirmed,dsb,dnb,dmac_sync,stch,schf,timing_error_rad,fo_hz,variant\n');
for k = 1:numel(reports)
    r = reports(k);
    fprintf(fid, '%d,%.6f,%.6f,%.6f,%d,%d,%d,%d,%d,%d,%d,%.6g,%.6g,%s\n', ...
        r.index, r.startSec, r.endSec, r.durationSec, r.pduCount, ...
        r.confirmedBursts, r.dsbCount, r.dnbCount, r.dmacSyncDecodedCount, ...
        r.stchDecodedCount, r.schFDecodedCount, r.timingErrorRad, ...
        r.coarseFrequencyOffsetHz, r.decisionVariant);
end
end

function out = appendPdus(out, items)
if isempty(items)
    return;
end
if isempty(out)
    out = items(:);
else
    out = [out; items(:)];
end
end

function out = appendWindowReport(out, item)
if isempty(out)
    out = item;
else
    out(end+1, 1) = item;
end
end

function pdu = emptyPdu()
pdu = struct( ...
    'protocol', '', ...
    'type', '', ...
    'src', 0, ...
    'dst', 0, ...
    'ts', [], ...
    'flco', '', ...
    'fid', '', ...
    'extra', struct(), ...
    'raw_bits', []);
end

function r = emptyWindowReport()
r = struct( ...
    'index', 0, ...
    'startSec', 0, ...
    'endSec', 0, ...
    'durationSec', 0, ...
    'mode', '', ...
    'splitIndex', 0, ...
    'meanPowerDb', NaN, ...
    'peakPowerDb', NaN, ...
    'pduCount', 0, ...
    'coarseFrequencyOffsetHz', NaN, ...
    'residualCorrectionHz', NaN, ...
    'timingPhaseSamples', NaN, ...
    'timingErrorRad', NaN, ...
    'decisionVariant', '', ...
    'symbolCount', 0, ...
    'bitCount', 0, ...
    'trainingCandidateCount', 0, ...
    'trainingGoodCount', 0, ...
    'confirmedBursts', 0, ...
    'dsbCount', 0, ...
    'dnbCount', 0, ...
    'dmacSyncDecodedCount', 0, ...
    'stchDecodedCount', 0, ...
    'schFDecodedCount', 0, ...
    'timingAssignedCount', 0);
end
