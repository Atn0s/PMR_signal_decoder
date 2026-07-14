function info = captureInfo(path, varargin)
%CAPTUREINFO Resolve file metadata needed by the tuned transition path.
p = inputParser;
p.addParameter('SampleRate', []);
p.addParameter('CenterFrequencyHz', []);
p.addParameter('IqDType', 'int16');
p.addParameter('HeaderBytes', []);
p.parse(varargin{:});

path = char(path);
fileInfo = dir(path);
if isempty(fileInfo)
    error('radio:tuned:captureInfo:NotFound', ...
        'IQ input file does not exist: %s', path);
end
[~, ~, extension] = fileparts(path);
isBvsp = strcmpi(extension, '.bvsp');
isWav = common.isWavIq(path);

info = struct( ...
    'path', path, ...
    'format', 'raw', ...
    'isBvsp', isBvsp, ...
    'isWav', isWav, ...
    'headerBytes', 0, ...
    'sampleRateHz', 0, ...
    'centerFrequencyHz', 0, ...
    'bandwidthHz', 0, ...
    'totalSamples', uint64(0), ...
    'durationSec', 0, ...
    'device', '', ...
    'fileIndex', uint32(0), ...
    'declaredFileBytes', uint64(0), ...
    'fileBytes', uint64(fileInfo.bytes), ...
    'iqDType', lower(char(p.Results.IqDType)));

if isBvsp
    info = readBvspHeader(info, fileInfo.bytes);
    if ~isempty(p.Results.HeaderBytes) && ...
            p.Results.HeaderBytes ~= info.headerBytes
        error('radio:tuned:captureInfo:BvspHeaderBytes', ...
            'Observed BVSP captures require a 112-byte header.');
    end
    if ~strcmp(info.iqDType, 'int16')
        error('radio:tuned:captureInfo:BvspDType', ...
            'BVSP payloads are interleaved little-endian int16 IQ.');
    end
elseif isWav
    audio = audioinfo(path);
    if audio.NumChannels < 2
        error('radio:tuned:captureInfo:WavChannels', ...
            'WAV IQ input must have at least two channels.');
    end
    info.format = 'wav';
    info.sampleRateHz = double(audio.SampleRate);
    info.totalSamples = uint64(audio.TotalSamples);
    info.centerFrequencyHz = optionalScalar( ...
        p.Results.CenterFrequencyHz, 0);
    if ~isempty(p.Results.SampleRate) && ...
            p.Results.SampleRate ~= info.sampleRateHz
        error('radio:tuned:captureInfo:WavSampleRate', ...
            'Requested sample rate does not match WAV metadata.');
    end
    if ~isempty(p.Results.HeaderBytes) && p.Results.HeaderBytes ~= 0
        error('radio:tuned:captureInfo:WavHeaderBytes', ...
            'HeaderBytes must be zero for WAV input.');
    end
else
    info.format = 'raw';
    info.headerBytes = optionalScalar(p.Results.HeaderBytes, 0);
    validateattributes(info.headerBytes, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'nonnegative', 'integer'});
    info.sampleRateHz = p.Results.SampleRate;
    if isempty(info.sampleRateHz)
        info.sampleRateHz = common.detectSampleRate(path);
    end
    if isempty(info.sampleRateHz)
        error('radio:tuned:captureInfo:MissingSampleRate', ...
            'SampleRate is required for a headerless IQ file.');
    end
    info.centerFrequencyHz = optionalScalar( ...
        p.Results.CenterFrequencyHz, 0);
    bytesPerScalar = dtypeBytes(info.iqDType);
    payloadBytes = fileInfo.bytes - info.headerBytes;
    if payloadBytes < 0 || mod(payloadBytes, 2 * bytesPerScalar) ~= 0
        error('radio:tuned:captureInfo:PayloadAlignment', ...
            'Raw IQ payload is not aligned to complete I/Q sample pairs.');
    end
    info.totalSamples = uint64(payloadBytes / (2 * bytesPerScalar));
end

validateattributes(info.sampleRateHz, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'});
validateattributes(info.centerFrequencyHz, {'numeric'}, ...
    {'scalar', 'real', 'finite'});
if info.totalSamples == 0
    error('radio:tuned:captureInfo:Empty', 'IQ input has no samples.');
end
info.durationSec = double(info.totalSamples) / info.sampleRateHz;
end

function info = readBvspHeader(info, actualFileBytes)
if actualFileBytes < 112
    error('radio:tuned:captureInfo:BvspTooShort', ...
        'BVSP file is shorter than its 112-byte header.');
end
fid = fopen(info.path, 'rb', 'ieee-le');
if fid < 0
    error('radio:tuned:captureInfo:OpenFailed', ...
        'Unable to open BVSP input: %s', info.path);
end
cleanup = onCleanup(@() fclose(fid));
info.format = 'bvsp-usrp-ci16';
info.headerBytes = 112;
info.declaredFileBytes = uint64(readScalar(fid, 8, 'uint64=>double'));
info.fileIndex = uint32(readScalar(fid, 28, 'uint32=>double'));
if fseek(fid, 32, 'bof') ~= 0
    error('radio:tuned:captureInfo:HeaderSeek', ...
        'Unable to read BVSP device metadata.');
end
deviceBytes = fread(fid, 16, '*uint8').';
zeroIndex = find(deviceBytes == 0, 1);
if ~isempty(zeroIndex)
    deviceBytes = deviceBytes(1:zeroIndex-1);
end
info.device = char(deviceBytes);
info.sampleRateHz = readScalar(fid, 48, 'uint32=>double');
info.bandwidthHz = readScalar(fid, 52, 'uint32=>double');
info.centerFrequencyHz = 1000 * ...
    readScalar(fid, 56, 'uint32=>double');
clear cleanup;

if info.declaredFileBytes ~= 0 && ...
        info.declaredFileBytes ~= uint64(actualFileBytes)
    error('radio:tuned:captureInfo:BvspSizeMismatch', ...
        'BVSP header file size does not match the input file.');
end
payloadBytes = actualFileBytes - info.headerBytes;
if mod(payloadBytes, 4) ~= 0
    error('radio:tuned:captureInfo:PayloadAlignment', ...
        'BVSP payload is not aligned to interleaved int16 IQ.');
end
info.totalSamples = uint64(payloadBytes / 4);
end

function value = readScalar(fid, byteOffset, precision)
if fseek(fid, byteOffset, 'bof') ~= 0
    error('radio:tuned:captureInfo:HeaderSeek', ...
        'Unable to seek in BVSP header.');
end
value = fread(fid, 1, precision);
if isempty(value)
    error('radio:tuned:captureInfo:HeaderRead', ...
        'Incomplete BVSP header.');
end
end

function value = optionalScalar(value, fallback)
if isempty(value), value = fallback; end
validateattributes(value, {'numeric'}, ...
    {'scalar', 'real', 'finite'});
value = double(value);
end

function bytes = dtypeBytes(dtype)
switch lower(char(dtype))
    case 'int8'
        bytes = 1;
    case 'int16'
        bytes = 2;
    case {'int32', 'single', 'float32'}
        bytes = 4;
    case {'double', 'float64'}
        bytes = 8;
    otherwise
        error('radio:tuned:captureInfo:DType', ...
            'Unsupported IQ dtype: %s', char(dtype));
end
end
