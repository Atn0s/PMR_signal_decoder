function [scanner, output, newPdus, closedEpochs] = ...
        streamScannerCoordinatorFeed(scanner, chunk)
%STREAMSCANNERCOORDINATORFEED Feed one detection-sized baseband micro-batch.
[scanner.coordinator, output] = ...
    radio.stream.raceCoordinatorFeed(scanner.coordinator, chunk);
if ~isempty(output.selectedProtocol)
    scanner.lastSelectedProtocol = output.selectedProtocol;
end
newPdus = emittedPdus(output);
newPdus = stampTunedStreamPdus(newPdus, scanner);
closedEpochs = output.closedEpochs;
scanner.pdus = appendStruct(scanner.pdus, newPdus);
scanner.closedEpochs = appendUniqueEpochs( ...
    scanner.closedEpochs, closedEpochs);
scanner.events = appendStruct(scanner.events, output.events);
scanner.basebandSampleCount = scanner.basebandSampleCount + ...
    uint64(numel(chunk.iq));
scanner.basebandNextSample = chunk.sourceSampleEnd;
end

function pdus = emittedPdus(output)
pdus = struct([]);
eventTypes = {};
if ~isempty(output.events), eventTypes = {output.events.type}; end
if any(strcmp(eventTypes, 'CATCHUP_COMPLETE')) && ...
        ~isempty(output.lastCatchup)
    pdus = appendStruct(pdus, output.lastCatchup.pdus);
end
if ~isempty(output.decoder) && isfield(output.decoder, 'newPdus')
    pdus = appendStruct(pdus, output.decoder.newPdus);
end
end

function pdus = stampTunedStreamPdus(pdus, scanner)
for k = 1:numel(pdus)
    basebandSample = radio.getNestedField( ...
        pdus(k), 'extra.stream.source_sample', uint64(0));
    widebandSample = uint64(max(0, round( ...
        double(basebandSample) * scanner.ddc.decimationFactor)));
    if ~isfield(pdus(k), 'extra') || ~isstruct(pdus(k).extra)
        pdus(k).extra = struct();
    end
    pdus(k).extra.tuned = struct( ...
        'channel_id', uint64(scanner.channelId), ...
        'input_center_frequency_hz', scanner.inputCenterFrequencyHz, ...
        'target_frequency_hz', scanner.targetCenterFrequencyHz, ...
        'frequency_offset_hz', scanner.frequencyOffsetHz, ...
        'input_sample_rate_hz', scanner.inputSampleRateHz, ...
        'baseband_sample_rate_hz', scanner.basebandSampleRateHz, ...
        'decimation_factor', scanner.ddc.decimationFactor, ...
        'wideband_source_sample_approx', widebandSample, ...
        'mapping_includes_filter_delay', false);
end
pdus = radio.normalizePdus(pdus);
end

function value = appendStruct(value, items)
if isempty(items), return; end
if isempty(value), value = items(:); else, value = [value(:); items(:)]; end
end

function epochs = appendUniqueEpochs(epochs, items)
for k = 1:numel(items)
    if isempty(epochs) || ~any([epochs.epochId] == items(k).epochId)
        epochs(end+1, 1) = items(k); %#ok<AGROW>
    end
end
end
