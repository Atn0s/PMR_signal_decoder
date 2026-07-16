function descriptor = sharedIqRingCreate(sampleRateHz, chunkSamples, varargin)
%SHAREDIQRINGCREATE Create a bounded cross-process wideband-IQ ring.
p = inputParser;
p.addParameter('CenterFrequencyHz', 0);
p.addParameter('CapacitySec', 2.0);
p.addParameter('Path', '');
p.parse(varargin{:});
validateattributes(sampleRateHz, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'});
validateattributes(chunkSamples, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'integer', 'positive'});
validateattributes(p.Results.CapacitySec, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'});
capacityChunks = max(2, ceil( ...
    p.Results.CapacitySec * sampleRateHz / chunkSamples));
path = char(p.Results.Path);
if isempty(path), path = [tempname, '.pmr-iq-ring']; end

descriptor = struct( ...
    'path', path, ...
    'magic', uint64(1380535890), ...
    'version', uint32(1), ...
    'capacityChunks', uint32(capacityChunks), ...
    'chunkSamples', uint32(chunkSamples), ...
    'sampleRateHz', double(sampleRateHz), ...
    'centerFrequencyHz', double(p.Results.CenterFrequencyHz), ...
    'capacitySec', double(capacityChunks * chunkSamples / sampleRateHz));
[~, byteCount] = radio.live.sharedIqRingLayout(descriptor);

parent = fileparts(path);
if ~isempty(parent) && exist(parent, 'dir') ~= 7
    error('radio:live:sharedIqRingCreate:Directory', ...
        'Shared-ring directory does not exist: %s', parent);
end
fid = fopen(path, 'w', 'ieee-le');
if fid < 0
    error('radio:live:sharedIqRingCreate:Open', ...
        'Unable to create shared IQ ring: %s', path);
end
cleanup = onCleanup(@() fclose(fid));
remaining = double(byteCount);
zeroBlock = zeros(min(2^20, remaining), 1, 'uint8');
while remaining > 0
    count = min(numel(zeroBlock), remaining);
    written = fwrite(fid, zeroBlock(1:count), 'uint8');
    if written ~= count
        error('radio:live:sharedIqRingCreate:Allocate', ...
            'Unable to allocate %.1f MiB shared IQ ring.', ...
            byteCount / 2^20);
    end
    remaining = remaining - written;
end
clear cleanup;

mapping = radio.live.sharedIqRingOpenUninitialized(descriptor);
mapping.Data.magic = descriptor.magic;
mapping.Data.version = descriptor.version;
mapping.Data.capacityChunks = descriptor.capacityChunks;
mapping.Data.chunkSamples = descriptor.chunkSamples;
mapping.Data.writeSequence = uint64(0);
mapping.Data.sourceSampleEnd = uint64(0);
mapping.Data.terminal = uint32(0);
mapping.Data.writerStopped = uint32(0);
mapping.Data.consumerSequence = uint64(0);
mapping.Data.overrunCount = uint64(0);
clear mapping;
end
