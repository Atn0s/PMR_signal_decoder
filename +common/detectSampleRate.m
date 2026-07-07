function fs = detectSampleRate(path)
%DETECTSAMPLERATE Infer sample rate from filename or WAV metadata.
path = char(path);
[~, base, ext] = fileparts(path);
name = [base ext];

tokens = regexp(name, '_(\d{4,9})\.rawiq$', 'tokens', 'once');
if ~isempty(tokens)
    fs = str2double(tokens{1});
    return;
end

tokens = regexp(name, '(\d+(?:\.\d+)?)\s*[mM][hH][zZ]\.rawiq$', 'tokens', 'once');
if ~isempty(tokens)
    fs = round(str2double(tokens{1}) * 1e6);
    return;
end

if common.isWavIq(path)
    try
        info = audioinfo(path);
        fs = info.SampleRate;
        return;
    catch
    end
end

fs = [];
end

