function source = fileSourceClose(source)
%FILESOURCECLOSE Close the raw-file handle owned by a FileSource.
if ~source.closed && ~source.isWav && source.fid >= 0
    fclose(source.fid);
end
source.fid = -1;
source.closed = true;
end
