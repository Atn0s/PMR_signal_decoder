function source = fileSourceInit(path, varargin)
%FILESOURCEINIT Open a raw or stereo-WAV IQ file as a chunk source.
p = inputParser;
p.addParameter('SampleRateHz', []);
p.addParameter('ChunkDurationSec', radio.stream.defaultConfig().chunkDurationSec);
p.addParameter('ChunkSamples', []);
p.addParameter('DType', 'int16');
p.addParameter('Scale', []);
p.addParameter('ChannelId', 1);
p.addParameter('CenterFrequencyHz', 0);
p.parse(varargin{:});

path = char(path);
if exist(path, 'file') ~= 2
    error('radio:stream:fileSourceInit:NotFound', ...
        'IQ input file does not exist: %s', path);
end
isWav = common.isWavIq(path);
sampleRateHz = p.Results.SampleRateHz;
if isempty(sampleRateHz)
    sampleRateHz = common.detectSampleRate(path);
end
if isempty(sampleRateHz) || ~isscalar(sampleRateHz) || sampleRateHz <= 0
    error('radio:stream:fileSourceInit:SampleRate', ...
        'SampleRateHz is required when it cannot be inferred.');
end

dtype = normalizeDType(p.Results.DType);
scale = p.Results.Scale;
if isempty(scale)
    scale = common.defaultIqScale(dtype.name);
end
if ~isscalar(scale) || ~isfinite(scale) || scale == 0
    error('radio:stream:fileSourceInit:Scale', ...
        'Scale must be a finite non-zero scalar.');
end

if isempty(p.Results.ChunkSamples)
    chunkSamples = max(1, round(sampleRateHz * p.Results.ChunkDurationSec));
else
    chunkSamples = p.Results.ChunkSamples;
end
validateattributes(chunkSamples, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive', 'integer'});

fid = -1;
if isWav
    info = audioinfo(path);
    if info.NumChannels < 2
        error('radio:stream:fileSourceInit:WavChannels', ...
            'WAV IQ input must have at least two channels.');
    end
    if ~isempty(p.Results.SampleRateHz) && info.SampleRate ~= sampleRateHz
        error('radio:stream:fileSourceInit:WavSampleRate', ...
            'Requested sample rate does not match WAV metadata.');
    end
    sampleRateHz = info.SampleRate;
    totalSamples = uint64(info.TotalSamples);
else
    fid = fopen(path, 'rb');
    if fid < 0
        error('radio:stream:fileSourceInit:OpenFailed', ...
            'Unable to open IQ input: %s', path);
    end
    info = dir(path);
    totalSamples = uint64(floor(double(info.bytes) / ...
        double(2 * dtype.bytes)));
end

source = struct( ...
    'path', path, ...
    'isWav', isWav, ...
    'fid', fid, ...
    'sampleRateHz', double(sampleRateHz), ...
    'chunkSamples', double(chunkSamples), ...
    'dtypeName', dtype.name, ...
    'freadPrecision', dtype.freadPrecision, ...
    'scale', double(scale), ...
    'channelId', p.Results.ChannelId, ...
    'centerFrequencyHz', double(p.Results.CenterFrequencyHz), ...
    'totalSamples', totalSamples, ...
    'nextSample', uint64(0), ...
    'nextSequenceNumber', uint64(0), ...
    'closed', false);
end

function dtype = normalizeDType(value)
switch lower(char(value))
    case 'int8'
        dtype = struct('name', 'int8', 'freadPrecision', '*int8', 'bytes', 1);
    case 'int16'
        dtype = struct('name', 'int16', 'freadPrecision', '*int16', 'bytes', 2);
    case 'int32'
        dtype = struct('name', 'int32', 'freadPrecision', '*int32', 'bytes', 4);
    case {'single', 'float32'}
        dtype = struct('name', 'single', 'freadPrecision', '*single', 'bytes', 4);
    case {'double', 'float64'}
        dtype = struct('name', 'double', 'freadPrecision', '*double', 'bytes', 8);
    otherwise
        error('radio:stream:fileSourceInit:DType', ...
            'Unsupported IQ dtype: %s', char(value));
end
end
