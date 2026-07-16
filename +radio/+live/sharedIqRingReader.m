function reader = sharedIqRingReader(descriptor, startSequence)
%SHAREDIQRINGREADER Open one ordered consumer endpoint.
mapping = radio.live.sharedIqRingOpen(descriptor, true);
if nargin < 2 || isempty(startSequence)
    startSequence = uint64(mapping.Data.writeSequence) + uint64(1);
end
reader = struct();
reader.descriptor = descriptor;
reader.mapping = mapping;
reader.nextSequence = uint64(startSequence);
reader.readCount = uint64(0);
reader.lastSourceSampleEnd = uint64(mapping.Data.sourceSampleEnd);
end
