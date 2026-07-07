function result = runAnalyzeSample()
%RUNANALYZESAMPLE Open the default DMR sample in the MATLAB analyzer.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
sample = fullfile(pybackend.defaultPythonRoot(), 'data', 'dmr_1_78125.rawiq');
result = viz.analyzeFile(sample, 'ProtocolNames', {'dmr'});
end

