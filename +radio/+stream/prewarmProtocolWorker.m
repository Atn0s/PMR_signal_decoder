function report = prewarmProtocolWorker(protocolNames, durationSec)
%PREWARMPROTOCOLWORKER Exercise decoder entry points in one process worker.
if nargin < 1 || isempty(protocolNames)
    specs = radio.protocolRegistry();
    protocolNames = {specs.name};
else
    protocolNames = radio.normalizeProtocolNames(protocolNames);
end
if nargin < 2 || isempty(durationSec)
    durationSec = 0.20;
end

specs = radio.protocolRegistry();
items = repmat(struct( ...
    'protocol', '', 'elapsedSec', 0, 'success', false, ...
    'errorReason', ''), numel(protocolNames), 1);
for k = 1:numel(protocolNames)
    protocol = protocolNames{k};
    index = find(strcmp({specs.name}, protocol), 1);
    if isempty(index)
        items(k).protocol = protocol;
        items(k).errorReason = 'protocol_not_registered';
        continue;
    end
    sampleRateHz = specs(index).targetSampleRateHz;
    count = max(256, round(durationSec * sampleRateHz));
    n = (0:count-1).';
    iq = 1e-3 .* complex( ...
        sin(2 .* pi .* n ./ 97) + 0.3 .* sin(2 .* pi .* n ./ 31), ...
        cos(2 .* pi .* n ./ 89) + 0.2 .* cos(2 .* pi .* n ./ 43));
    snapshot = radio.stream.makeIqChunk(single(iq), sampleRateHz, 0);
    token = tic;
    try
        radio.stream.decodeProtocolWindow(protocol, snapshot);
        if strcmp(protocol, 'P25')
            % The synchronization scan may not reach BCH decoding on a
            % no-signal vector; exercise that cold path explicitly.
            p25.decodeNid(false(64, 1));
        elseif strcmp(protocol, 'NXDN')
            % The locked path uses a causal 120 kS/s frontend rather than
            % the offline 48 kS/s window frontend.  Warm that System object
            % and its frame-state functions on every process worker too.
            streamFs = 125000;
            streamCount = round(max(0.25, durationSec) * streamFs);
            streamChunk = radio.stream.makeIqChunk( ...
                complex(zeros(streamCount, 1, 'single')), streamFs, 0);
            streamState = nxdn.streamInit(streamFs, nxdn.config(), ...
                'SourceSampleStart', uint64(0));
            nxdn.streamDecodeChunk(streamState, streamChunk);
        end
        items(k).success = true;
    catch ME
        items(k).errorReason = sprintf('%s: %s', ...
            ME.identifier, ME.message);
    end
    items(k).protocol = protocol;
    items(k).elapsedSec = toc(token);
end

task = getCurrentTask();
taskId = 0;
if ~isempty(task)
    taskId = task.ID;
end
report = struct( ...
    'taskId', double(taskId), ...
    'protocols', {protocolNames}, ...
    'items', items, ...
    'success', all([items.success]), ...
    'elapsedSec', sum([items.elapsedSec]));
end
