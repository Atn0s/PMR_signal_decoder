function report = goldenRegression(varargin)
%GOLDENREGRESSION Compare MATLAB native output against Python JSON baselines.
p = inputParser;
p.addParameter('GoldenDir', fullfile(projectRoot(), 'golden', 'current'));
p.addParameter('PythonRoot', pybackend.defaultPythonRoot());
p.addParameter('StopOnMismatch', false);
p.parse(varargin{:});

specs = sampleSpecs(p.Results.PythonRoot);
items = repmat(emptyItem(), 0, 1);
for k = 1:numel(specs)
    spec = specs(k);
    goldenPath = fullfile(p.Results.GoldenDir, [spec.name '.json']);
    if exist(goldenPath, 'file') ~= 2
        items(end+1, 1) = skippedItem(spec.name, 'missing golden JSON'); %#ok<AGROW>
        continue;
    end
    samplePath = fullfile(p.Results.PythonRoot, spec.relPath);
    if exist(samplePath, 'file') ~= 2
        items(end+1, 1) = skippedItem(spec.name, 'missing sample file'); %#ok<AGROW>
        continue;
    end

    expected = readJsonPdus(goldenPath);
    actual = radio.scanFile(samplePath, ...
        'ProtocolNames', spec.protocols, ...
        'BlindSearch', spec.blindSearch, ...
        'SampleRate', spec.sampleRate, ...
        'PipelineBackend', 'matlab', ...
        'DecoderBackend', 'matlab');
    items(end+1, 1) = compareOne(spec.name, expected, actual); %#ok<AGROW>
end

report = struct();
report.items = items;
report.ok = all([items.ok] | [items.skipped]);
report.mismatchCount = nnz(~[items.ok] & ~[items.skipped]);
report.skippedCount = nnz([items.skipped]);
printReport(report);
if p.Results.StopOnMismatch && report.mismatchCount > 0
    error('tests:goldenRegression:Mismatch', ...
        'Golden regression found %d mismatched files.', report.mismatchCount);
end
end

function item = compareOne(name, expected, actual)
item = emptyItem();
item.name = name;
item.expectedCount = numel(expected);
item.actualCount = numel(actual);
expectedKeys = pduSignatures(expected);
actualKeys = pduSignatures(actual);
[missing, unexpected] = multisetDiff(expectedKeys, actualKeys);
item.missingCount = numel(missing);
item.unexpectedCount = numel(unexpected);
item.missingExamples = firstN(missing, 5);
item.unexpectedExamples = firstN(unexpected, 5);
item.ok = item.missingCount == 0 && item.unexpectedCount == 0;
end

function pdus = readJsonPdus(path)
raw = strtrim(fileread(path));
if isempty(raw)
    pdus = struct([]);
    return;
end
pdus = jsondecode(raw);
pdus = radio.normalizePdus(pdus);
end

function keys = pduSignatures(pdus)
pdus = radio.normalizePdus(pdus);
keys = cell(numel(pdus), 1);
for k = 1:numel(pdus)
    p = pdus(k);
    sig = struct();
    sig.protocol = char(radio.getField(p, 'protocol', ''));
    sig.type = char(radio.getField(p, 'type', ''));
    sig.src = canonicalValue(radio.getField(p, 'src', 0));
    sig.dst = canonicalValue(radio.getField(p, 'dst', 0));
    sig.ts = canonicalValue(radio.getField(p, 'ts', []));
    sig.flco = char(radio.getField(p, 'flco', ''));
    sig.fid = char(radio.getField(p, 'fid', ''));
    sig.extra = semanticExtra(p);
    keys{k} = jsonencode(sig);
end
end

function extra = semanticExtra(p)
names = { ...
    'nac', 'duid', 'duid_name', 'pdu_type', 'frame_category', ...
    'tgid', 'hdu_mfid', 'algid', 'kid', 'hdu_tgid', ...
    'lco', 'mfid', 'svc', 'lc_info', 'call_type', ...
    'es_algid', 'es_kid', 'color_code', 'sync_type', ...
    'superframe_part', 'stable_color_code', 'stable_color_repeats', ...
    'communication_mode', 'comms_format', 'emergency_priority', ...
    'call_type', 'closed_by', 'slot_number', 'frame_number'};
extra = struct();
for k = 1:numel(names)
    value = radio.getNestedField(p, ['extra.' names{k}], []);
    if ~isempty(value)
        extra.(names{k}) = canonicalValue(value);
    end
end
cch = radio.getNestedField(p, 'extra.cch', []);
if ~isempty(cch) && isstruct(cch)
    extra.cch_signature = cchSignature(cch);
end
end

function sig = cchSignature(cch)
sig = cell(numel(cch), 1);
for k = 1:numel(cch)
    item = struct();
    item.frame_number = canonicalValue(fieldOr(cch(k), 'frame_number', []));
    item.id_half = canonicalValue(fieldOr(cch(k), 'id_half', []));
    item.communication_mode = canonicalValue(fieldOr(cch(k), 'communication_mode', []));
    item.comms_format = canonicalValue(fieldOr(cch(k), 'comms_format', []));
    item.emergency_priority = canonicalValue(fieldOr(cch(k), 'emergency_priority', []));
    sig{k} = item;
end
end

function [missing, unexpected] = multisetDiff(expected, actual)
allKeys = [expected(:); actual(:)];
if isempty(allKeys)
    missing = {};
    unexpected = {};
    return;
end
[uniqueKeys, ~, idx] = unique(allKeys);
nExp = numel(expected);
expCounts = accumarray(idx(1:nExp), 1, [numel(uniqueKeys), 1], @sum, 0);
actCounts = accumarray(idx(nExp+1:end), 1, [numel(uniqueKeys), 1], @sum, 0);
missing = expandKeys(uniqueKeys, expCounts - actCounts);
unexpected = expandKeys(uniqueKeys, actCounts - expCounts);
end

function out = expandKeys(keys, counts)
out = {};
for k = 1:numel(keys)
    for m = 1:max(0, counts(k))
        out{end+1, 1} = keys{k}; %#ok<AGROW>
    end
end
end

function out = firstN(values, n)
out = values(1:min(n, numel(values)));
end

function printReport(report)
fprintf('\n=== Golden regression ===\n');
for k = 1:numel(report.items)
    item = report.items(k);
    if item.skipped
        fprintf('[SKIP] %-18s %s\n', item.name, item.reason);
    elseif item.ok
        fprintf('[ OK ] %-18s count=%d\n', item.name, item.actualCount);
    else
        fprintf('[DIFF] %-18s expected=%d actual=%d missing=%d unexpected=%d\n', ...
            item.name, item.expectedCount, item.actualCount, ...
            item.missingCount, item.unexpectedCount);
        printExamples('missing', item.missingExamples);
        printExamples('unexpected', item.unexpectedExamples);
    end
end
fprintf('Golden regression mismatches: %d, skipped: %d\n', ...
    report.mismatchCount, report.skippedCount);
end

function printExamples(label, examples)
for k = 1:numel(examples)
    fprintf('       %s: %s\n', label, examples{k});
end
end

function specs = sampleSpecs(root)
specs = repmat(struct( ...
    'name', '', ...
    'relPath', '', ...
    'protocols', {{}}, ...
    'sampleRate', [], ...
    'blindSearch', false), 0, 1);
specs(end+1) = makeSpec('dmr_1_78125', 'data/dmr_1_78125.rawiq', {'dmr'}, [], false);
specs(end+1) = makeSpec('dmr_2_78125', 'data/dmr_2_78125.rawiq', {'dmr'}, [], false);
specs(end+1) = makeSpec('p25_1_78125', 'data/p25_1_78125.rawiq', {'p25'}, [], false);
specs(end+1) = makeSpec('dpmr_1_48000', 'data/dpmr_1_48000.rawiq', {'dpmr'}, [], false);
specs(end+1) = makeSpec('wideband_2_5mhz', 'data/synthesized_wideband_2.5MHz.rawiq', {'dmr'}, [], true);
for k = 1:numel(specs)
    if exist(fullfile(root, specs(k).relPath), 'file') ~= 2
        specs(k).sampleRate = [];
    end
end
end

function spec = makeSpec(name, relPath, protocols, sampleRate, blindSearch)
spec = struct('name', name, 'relPath', relPath, 'protocols', {protocols}, ...
    'sampleRate', sampleRate, 'blindSearch', blindSearch);
end

function item = emptyItem()
item = struct( ...
    'name', '', ...
    'ok', false, ...
    'skipped', false, ...
    'reason', '', ...
    'expectedCount', 0, ...
    'actualCount', 0, ...
    'missingCount', 0, ...
    'unexpectedCount', 0, ...
    'missingExamples', {{}}, ...
    'unexpectedExamples', {{}});
end

function item = skippedItem(name, reason)
item = emptyItem();
item.name = name;
item.skipped = true;
item.reason = reason;
end

function value = canonicalValue(value)
if isstring(value)
    value = char(value);
elseif ischar(value)
    return;
elseif islogical(value)
    value = logical(value);
elseif isnumeric(value)
    if isempty(value)
        return;
    end
    if isscalar(value)
        if isnan(value)
            value = [];
        else
            value = double(value);
        end
    else
        value = double(value(:).');
    end
end
end

function value = fieldOr(s, name, defaultValue)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end

function root = projectRoot()
root = fileparts(fileparts(mfilename('fullpath')));
end
