function report = runGoldenRegression(varargin)
%RUNGOLDENREGRESSION Run MATLAB smoke tests and golden checks.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
tests.runAll();
report = tests.goldenRegression(varargin{:});
end
