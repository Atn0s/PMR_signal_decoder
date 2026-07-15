function source = fileLoopSourceClose(source)
%FILELOOPSOURCECLOSE Close a replay source and its underlying file.
if ~source.closed
    source.fileSource = radio.stream.fileSourceClose(source.fileSource);
end
source.closed = true;
end
