function [scanner, chunks] = streamScannerQueueBaseband( ...
        scanner, inputChunk, varargin)
%STREAMSCANNERQUEUEBASEBAND Batch DDC output for the protocol coordinator.
p = inputParser;
p.addParameter('Flush', false);
p.parse(varargin{:});
chunks = cell(0, 1);

if ~isempty(inputChunk)
    radio.stream.validateIqChunk(inputChunk);
    if inputChunk.sampleRateHz ~= scanner.basebandSampleRateHz
        error('radio:tuned:streamScannerQueueBaseband:SampleRate', ...
            'Baseband sample rate changed inside one tuned stream.');
    end
    if ~isequal(inputChunk.channelId, scanner.channelId)
        error('radio:tuned:streamScannerQueueBaseband:ChannelId', ...
            'Baseband channel ID changed inside one tuned stream.');
    end

    hasPending = ~isempty(scanner.basebandPendingIq);
    if hasPending
        expectedStart = scanner.basebandPendingStartSample + ...
            uint64(numel(scanner.basebandPendingIq));
        noncontiguous = inputChunk.sourceSampleStart ~= expectedStart;
    else
        noncontiguous = false;
    end
    if hasPending && (inputChunk.discontinuity || noncontiguous)
        [scanner, boundaryChunk] = takePending( ...
            scanner, numel(scanner.basebandPendingIq));
        chunks{end+1, 1} = boundaryChunk;
    end

    if isempty(scanner.basebandPendingIq)
        scanner.basebandPendingStartSample = inputChunk.sourceSampleStart;
        scanner.basebandPendingDiscontinuity = ...
            logical(inputChunk.discontinuity || noncontiguous);
        scanner.basebandPendingDroppedSamples = ...
            uint64(inputChunk.droppedSourceSamples);
        if noncontiguous && inputChunk.sourceSampleStart > expectedStart
            scanner.basebandPendingDroppedSamples = ...
                scanner.basebandPendingDroppedSamples + ...
                inputChunk.sourceSampleStart - expectedStart;
        end
    end
    scanner.basebandPendingIq = [scanner.basebandPendingIq; ...
        double(inputChunk.iq(:))];

    while numel(scanner.basebandPendingIq) >= ...
            scanner.coordinatorChunkSamples
        [scanner, completeChunk] = takePending( ...
            scanner, scanner.coordinatorChunkSamples);
        chunks{end+1, 1} = completeChunk; %#ok<AGROW>
    end
end

if p.Results.Flush && ~isempty(scanner.basebandPendingIq)
    [scanner, finalChunk] = takePending( ...
        scanner, numel(scanner.basebandPendingIq));
    chunks{end+1, 1} = finalChunk;
end
end

function [scanner, chunk] = takePending(scanner, count)
count = double(count);
iq = scanner.basebandPendingIq(1:count);
chunk = radio.stream.makeIqChunk( ...
    iq, scanner.basebandSampleRateHz, ...
    scanner.basebandPendingStartSample, ...
    'ChannelId', scanner.channelId, ...
    'SequenceNumber', scanner.basebandNextSequenceNumber, ...
    'CenterFrequencyHz', scanner.targetCenterFrequencyHz, ...
    'Discontinuity', scanner.basebandPendingDiscontinuity, ...
    'DroppedSourceSamples', scanner.basebandPendingDroppedSamples);
scanner.basebandPendingIq = scanner.basebandPendingIq(count+1:end);
scanner.basebandPendingStartSample = chunk.sourceSampleEnd;
scanner.basebandPendingDiscontinuity = false;
scanner.basebandPendingDroppedSamples = uint64(0);
scanner.basebandNextSequenceNumber = ...
    scanner.basebandNextSequenceNumber + uint64(1);
end
