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

    hasPending = scanner.basebandPendingCount > 0;
    if hasPending
        expectedStart = scanner.basebandPendingStartSample + ...
            uint64(scanner.basebandPendingCount);
        noncontiguous = inputChunk.sourceSampleStart ~= expectedStart;
    else
        noncontiguous = false;
    end
    if hasPending && (inputChunk.discontinuity || noncontiguous)
        [scanner, boundaryChunk] = takePending( ...
            scanner, scanner.basebandPendingCount);
        chunks{end+1, 1} = boundaryChunk;
    end

    values = double(inputChunk.iq(:));
    consumed = 0;
    firstSegment = true;
    while consumed < numel(values)
        if scanner.basebandPendingCount == 0
            startSample = inputChunk.sourceSampleStart + uint64(consumed);
            discontinuity = firstSegment && ...
                logical(inputChunk.discontinuity || noncontiguous);
            droppedSamples = uint64(0);
            if firstSegment
                droppedSamples = uint64(inputChunk.droppedSourceSamples);
                if noncontiguous && inputChunk.sourceSampleStart > expectedStart
                    droppedSamples = droppedSamples + ...
                        inputChunk.sourceSampleStart - expectedStart;
                end
            end
            scanner = beginPending(scanner, startSample, ...
                discontinuity, droppedSamples);
        end
        available = scanner.coordinatorChunkSamples - ...
            scanner.basebandPendingCount;
        take = min(available, numel(values) - consumed);
        destination = scanner.basebandPendingCount + (1:take);
        source = consumed + (1:take);
        scanner.basebandPendingIq(destination) = values(source);
        scanner.basebandPendingCount = ...
            scanner.basebandPendingCount + take;
        consumed = consumed + take;
        firstSegment = false;
        if scanner.basebandPendingCount == scanner.coordinatorChunkSamples
            [scanner, completeChunk] = takePending( ...
                scanner, scanner.coordinatorChunkSamples);
            chunks{end+1, 1} = completeChunk; %#ok<AGROW>
        end
    end
end

if p.Results.Flush && scanner.basebandPendingCount > 0
    [scanner, finalChunk] = takePending( ...
        scanner, scanner.basebandPendingCount);
    chunks{end+1, 1} = finalChunk;
end
end

function scanner = beginPending( ...
        scanner, startSample, discontinuity, droppedSamples)
scanner.basebandPendingStartSample = uint64(startSample);
scanner.basebandPendingDiscontinuity = logical(discontinuity);
scanner.basebandPendingDroppedSamples = uint64(droppedSamples);
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
scanner.basebandPendingCount = 0;
scanner.basebandPendingStartSample = chunk.sourceSampleEnd;
scanner.basebandPendingDiscontinuity = false;
scanner.basebandPendingDroppedSamples = uint64(0);
scanner.basebandNextSequenceNumber = ...
    scanner.basebandNextSequenceNumber + uint64(1);
end
