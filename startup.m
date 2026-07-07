function startup()
%STARTUP Add the migration project to the MATLAB path.
rootDir = fileparts(mfilename('fullpath'));
addpath(rootDir);
addpath(fullfile(rootDir, 'examples'));
addpath(fullfile(rootDir, 'tools'));
end
