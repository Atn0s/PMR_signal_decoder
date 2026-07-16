function writer = sharedIqRingWriter(descriptor)
%SHAREDIQRINGWRITER Open the single-writer endpoint of a shared IQ ring.
mapping = radio.live.sharedIqRingOpen(descriptor, true);
writer = struct();
writer.descriptor = descriptor;
writer.mapping = mapping;
writer.nextSequence = uint64(mapping.Data.writeSequence) + uint64(1);
writer.writeCount = uint64(0);
end
