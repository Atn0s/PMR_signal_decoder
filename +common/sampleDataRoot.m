function root = sampleDataRoot()
%SAMPLEDATAROOT Locate optional external IQ samples used by tests/examples.
root = getenv('RADIO_SAMPLE_DATA_ROOT');
if isempty(root)
    root = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
        'signal_data');
end
end
