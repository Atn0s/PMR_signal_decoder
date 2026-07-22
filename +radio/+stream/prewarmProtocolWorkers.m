function report = prewarmProtocolWorkers(protocolNames, varargin)
%PREWARMPROTOCOLWORKERS Warm every protocol on every process worker.
p = inputParser;
p.addParameter('NumWorkers', 5);
p.addParameter('Pool', []);
p.addParameter('DurationSec', 0.20);
p.addParameter('TimeoutSec', 120);
p.parse(varargin{:});

if nargin < 1 || isempty(protocolNames)
    specs = radio.protocolRegistry();
    protocolNames = {specs.name};
else
    protocolNames = radio.normalizeProtocolNames(protocolNames);
end

pool = p.Results.Pool;
poolInfo = struct('available', ~isempty(pool), 'reason', 'provided_pool');
if isempty(pool)
    [pool, poolInfo] = radio.stream.acquireParallelPool( ...
        'NumWorkers', p.Results.NumWorkers);
end
report = struct( ...
    'success', false, ...
    'protocols', {protocolNames}, ...
    'numWorkers', 0, ...
    'elapsedSec', 0, ...
    'poolInfo', poolInfo, ...
    'workerReports', [], ...
    'errorReason', '');
if isempty(pool)
    report.errorReason = poolInfo.reason;
    return;
end
report.numWorkers = pool.NumWorkers;

token = tic;
try
    future = parfevalOnAll(pool, ...
        @radio.stream.prewarmProtocolWorker, 1, ...
        protocolNames, p.Results.DurationSec);
    while ~strcmp(char(future.State), 'finished')
        if toc(token) >= p.Results.TimeoutSec
            cancel(future);
            report.errorReason = 'protocol_worker_prewarm_timeout';
            report.elapsedSec = toc(token);
            return;
        end
        pause(0.02);
    end
    workerReports = fetchOutputs(future);
    report.workerReports = workerReports;
    report.success = workerReportsSucceeded(workerReports, pool.NumWorkers);
    if ~report.success
        report.errorReason = 'one_or_more_worker_protocol_warmups_failed';
    end
catch ME
    report.errorReason = sprintf('%s: %s', ME.identifier, ME.message);
end
report.elapsedSec = toc(token);
end

function tf = workerReportsSucceeded(value, expectedWorkers)
if isa(value, 'Composite')
    items = cell(1, numel(value));
    for k = 1:numel(value), items{k} = value{k}; end
elseif iscell(value)
    items = value(:).';
elseif isstruct(value)
    items = num2cell(value(:).');
else
    items = {value};
end
tf = numel(items) == expectedWorkers;
for k = 1:numel(items)
    tf = tf && isstruct(items{k}) && isfield(items{k}, 'success') && ...
        logical(items{k}.success);
end
end
