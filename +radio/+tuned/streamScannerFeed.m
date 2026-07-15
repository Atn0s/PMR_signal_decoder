function [scanner, output] = streamScannerFeed(scanner, widebandChunk)
%STREAMSCANNERFEED Route one wideband block through DDC and protocol race.
if scanner.finalized
    error('radio:tuned:streamScannerFeed:Finalized', ...
        'A finalized tuned stream scanner cannot accept more input.');
end
radio.stream.validateIqChunk(widebandChunk);
if widebandChunk.sampleRateHz ~= scanner.inputSampleRateHz
    error('radio:tuned:streamScannerFeed:SampleRate', ...
        'Wideband input sample rate changed.');
end
if widebandChunk.centerFrequencyHz ~= scanner.inputCenterFrequencyHz
    error('radio:tuned:streamScannerFeed:CenterFrequency', ...
        'Retuning requires a new tuned stream scanner.');
end

[scanner.ddc, basebandChunk] = ...
    radio.tuned.ddcFeed(scanner.ddc, widebandChunk);
[scanner, output] = radio.tuned.streamScannerFeedBaseband( ...
    scanner, widebandChunk, basebandChunk);
end
