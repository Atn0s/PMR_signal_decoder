function pdus = scanIq(iq, varargin)
%SCANIQ Write a temporary float32 rawiq file and decode it through Python.
p = inputParser;
p.addParameter('SampleRate', 48000.0);
p.addParameter('ProtocolNames', {});
p.addParameter('PythonRoot', '');
p.addParameter('PythonExecutable', '');
p.parse(varargin{:});

iq = iq(:);
tmpPath = [tempname '.rawiq'];
cleanupIq = onCleanup(@() deleteIfExists(tmpPath));

interleaved = zeros(numel(iq) * 2, 1, 'single');
interleaved(1:2:end) = single(real(iq));
interleaved(2:2:end) = single(imag(iq));

fid = fopen(tmpPath, 'wb');
if fid < 0
    error('pybackend:scanIq:TempOpenFailed', ...
        'Unable to write temporary IQ file: %s', tmpPath);
end
cleaner = onCleanup(@() fclose(fid));
fwrite(fid, interleaved, 'single');
clear cleaner;

pdus = pybackend.scanFile(tmpPath, ...
    'SampleRate', p.Results.SampleRate, ...
    'ProtocolNames', p.Results.ProtocolNames, ...
    'IqDType', 'float32', ...
    'PythonRoot', p.Results.PythonRoot, ...
    'PythonExecutable', p.Results.PythonExecutable);
end

function deleteIfExists(path)
if exist(path, 'file') == 2
    delete(path);
end
end

