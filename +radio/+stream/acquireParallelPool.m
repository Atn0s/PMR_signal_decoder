function [pool, info] = acquireParallelPool(varargin)
%ACQUIREPARALLELPOOL Reuse or create the process pool used by decoders.
p = inputParser;
p.addParameter('NumWorkers', 5);
p.addParameter('AllowCreate', true);
p.parse(varargin{:});

info = struct( ...
    'available', false, ...
    'created', false, ...
    'reused', false, ...
    'profile', '', ...
    'jobStorageLocation', '', ...
    'numWorkers', 0, ...
    'requestedWorkers', double(p.Results.NumWorkers), ...
    'reason', '');
pool = [];

if exist('parpool', 'file') ~= 2 || exist('parfeval', 'file') ~= 2 || ...
        ~license('test', 'Distrib_Computing_Toolbox')
    info.reason = 'parallel_computing_toolbox_unavailable';
    return;
end

pool = gcp('nocreate');
if ~isempty(pool)
    if isa(pool, 'parallel.ThreadPool')
        pool = [];
        info.reason = 'existing_thread_pool_is_not_supported';
        return;
    end
    info.available = true;
    info.reused = true;
    info.profile = pool.Cluster.Profile;
    info.numWorkers = pool.NumWorkers;
    return;
end
if ~p.Results.AllowCreate
    info.reason = 'parallel_pool_not_running';
    return;
end

try
    cluster = parcluster('local');
    jobStorageLocation = tempname;
    [created, message] = mkdir(jobStorageLocation);
    if ~created
        error('radio:stream:acquireParallelPool:JobStorage', ...
            'Unable to create parallel job storage: %s', message);
    end
    cluster.JobStorageLocation = jobStorageLocation;
    workerCount = max(1, round(p.Results.NumWorkers));
    pool = parpool(cluster, min(workerCount, cluster.NumWorkers));
    info.available = true;
    info.created = true;
    info.profile = cluster.Profile;
    info.jobStorageLocation = jobStorageLocation;
    info.numWorkers = pool.NumWorkers;
catch ME
    pool = [];
    info.reason = sprintf('%s: %s', ME.identifier, ME.message);
end
end
