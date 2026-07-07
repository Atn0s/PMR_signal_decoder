function tf = isWavIq(filename)
%ISWAVIQ True when a file looks like RIFF/WAVE IQ.
[~, ~, ext] = fileparts(char(filename));
if any(strcmpi(ext, {'.wav', '.wave'}))
    tf = true;
    return;
end

fid = fopen(filename, 'rb');
if fid < 0
    tf = false;
    return;
end
cleaner = onCleanup(@() fclose(fid));
header = fread(fid, 12, '*uint8')';
tf = numel(header) >= 12 && ...
    isequal(char(header(1:4)), 'RIFF') && ...
    isequal(char(header(9:12)), 'WAVE');
end

