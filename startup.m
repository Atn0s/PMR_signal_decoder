function startup()
%STARTUP Add the radio decoder project to the MATLAB path.
rootDir = fileparts(mfilename('fullpath'));
addpath(rootDir);
addpath(fullfile(rootDir, 'examples'));
addpath(fullfile(rootDir, 'tools'));
end
