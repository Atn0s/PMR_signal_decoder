function [states, race] = serialProbeRace(snapshot, states, varargin)
%SERIALPROBERACE Run eligible protocol probes sequentially with race semantics.
p = inputParser;
p.addParameter('EpochId', uint64(1));
p.addParameter('Generation', uint64(1));
p.addParameter('ProtocolNames', {});
p.addParameter('Registry', []);
p.parse(varargin{:});

registry = p.Results.Registry;
if isempty(registry)
    registry = radio.stream.probeRegistry(p.Results.ProtocolNames);
end
if isempty(states)
    states = repmat(radio.stream.probeStateInit( ...
        registry(1), p.Results.EpochId, p.Results.Generation, ...
        snapshot.sourceSampleStart), numel(registry), 1);
    for k = 1:numel(registry)
        states(k) = radio.stream.probeStateInit( ...
            registry(k), p.Results.EpochId, p.Results.Generation, ...
            snapshot.sourceSampleStart);
    end
end
if numel(states) ~= numel(registry)
    error('radio:stream:serialProbeRace:StateCount', ...
        'Probe state count does not match registry count.');
end

results = repmat(emptyResult(), numel(registry), 1);
for k = 1:numel(registry)
    if states(k).epochId ~= uint64(p.Results.EpochId) || ...
            states(k).generation ~= uint64(p.Results.Generation)
        error('radio:stream:serialProbeRace:StaleState', ...
            'Probe state epoch/generation does not match the active race.');
    end
    [states(k), results(k)] = radio.stream.runProtocolProbe( ...
        states(k), snapshot, registry(k));
end

race = radio.stream.summarizeProbeResults( ...
    results, p.Results.EpochId, p.Results.Generation);
end

function result = emptyResult()
state = struct('epochId', uint64(0), 'generation', uint64(0), ...
    'protocol', '');
chunk = radio.stream.makeIqChunk(complex(zeros(0, 1)), 1, 0);
result = radio.stream.makeProbeResult(state, 'pending', chunk);
end
