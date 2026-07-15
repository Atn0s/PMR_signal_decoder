function result = refineCarrier(snapshot, clickedFrequencyHz, varargin)
%REFINECARRIER Refine a clicked carrier using moving energy and centroid.
p = inputParser;
p.addParameter('BandwidthHz', 12500);
p.addParameter('SearchRadiusHz', []);
p.addParameter('Spectrum', 'average');
p.parse(varargin{:});
validateattributes(clickedFrequencyHz, {'numeric'}, ...
    {'scalar', 'real', 'finite'});
validateattributes(p.Results.BandwidthHz, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'});
if isempty(p.Results.SearchRadiusHz)
    searchRadiusHz = max(50000, 2 * p.Results.BandwidthHz);
else
    searchRadiusHz = p.Results.SearchRadiusHz;
    validateattributes(searchRadiusHz, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'positive'});
end
if ~snapshot.hasEstimate
    error('radio:scope:refineCarrier:NoSpectrum', ...
        'At least one spectrum update is required before selecting a carrier.');
end

frequencyHz = double(snapshot.frequencyHz(:));
switch lower(char(p.Results.Spectrum))
    case 'average'
        power = double(snapshot.averagePsd(:));
    case {'max', 'maxhold', 'max-hold'}
        power = double(snapshot.maxHoldPsd(:));
    otherwise
        error('radio:scope:refineCarrier:Spectrum', ...
            'Spectrum must be average or maxhold.');
end
binHz = median(diff(frequencyHz));
indices = find(abs(frequencyHz - clickedFrequencyHz) <= searchRadiusHz);
if isempty(indices)
    error('radio:scope:refineCarrier:OutsideSpectrum', ...
        'Clicked frequency is outside the live spectrum.');
end
smoothingBins = max(3, round(p.Results.BandwidthHz / abs(binHz)));
smoothed = movmean(power, smoothingBins, 'Endpoints', 'shrink');
[~, localIndex] = max(smoothed(indices));
peakIndex = indices(localIndex);
halfBins = max(1, floor(smoothingBins / 2));
region = max(1, peakIndex-halfBins):min(numel(power), peakIndex+halfBins);
localNoise = median(power(indices));
weights = max(0, power(region) - localNoise);
if sum(weights) > 0
    refinedFrequencyHz = sum(frequencyHz(region) .* weights) / sum(weights);
else
    refinedFrequencyHz = frequencyHz(peakIndex);
end
result = struct( ...
    'clickedFrequencyHz', double(clickedFrequencyHz), ...
    'refinedFrequencyHz', double(refinedFrequencyHz), ...
    'offsetHz', double(refinedFrequencyHz - snapshot.centerFrequencyHz), ...
    'bandwidthHz', double(p.Results.BandwidthHz), ...
    'searchRadiusHz', double(searchRadiusHz), ...
    'peakBinFrequencyHz', double(frequencyHz(peakIndex)), ...
    'peakPower', double(power(peakIndex)), ...
    'noisePower', double(localNoise));
end
