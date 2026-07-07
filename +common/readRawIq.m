function iq = readRawIq(filename, varargin)
%READRAWIQ Read interleaved raw IQ or stereo PCM WAV as complex samples.
p = inputParser;
p.addParameter('DType', 'int16');
p.addParameter('Scale', []);
p.parse(varargin{:});
dtype = char(p.Results.DType);
scale = p.Results.Scale;

if common.isWavIq(filename)
    iq = readWavIq(filename);
    return;
end

fid = fopen(filename, 'rb');
if fid < 0
    error('common:readRawIq:OpenFailed', 'Unable to open IQ file: %s', filename);
end
cleaner = onCleanup(@() fclose(fid));

matlabType = normalizeDType(dtype);
data = fread(fid, inf, ['*' matlabType]);
if isempty(data)
    iq = complex(zeros(0, 1));
    return;
end

iData = data(1:2:end);
qData = data(2:2:end);
n = min(numel(iData), numel(qData));
if isempty(scale)
    scale = common.defaultIqScale(dtype);
end
if scale == 0
    error('common:readRawIq:BadScale', 'IQ scale must be non-zero.');
end

iq = (double(iData(1:n)) + 1i * double(qData(1:n))) ./ double(scale);
iq = iq(:);
end

function dtype = normalizeDType(dtype)
switch lower(char(dtype))
    case {'int8'}
        dtype = 'int8';
    case {'int16'}
        dtype = 'int16';
    case {'int32'}
        dtype = 'int32';
    case {'single', 'float32'}
        dtype = 'single';
    case {'double', 'float64'}
        dtype = 'double';
    otherwise
        error('common:readRawIq:UnsupportedDType', 'Unsupported IQ dtype: %s', dtype);
end
end

function iq = readWavIq(filename)
try
    [samples, ~] = audioread(filename);
catch err
    error('common:readRawIq:WavReadFailed', ...
        'Unable to read WAV IQ file %s: %s', filename, err.message);
end
if size(samples, 2) < 2
    error('common:readRawIq:WavChannels', ...
        'WAV IQ input must have at least two channels.');
end
iq = complex(samples(:, 1), samples(:, 2));
end

