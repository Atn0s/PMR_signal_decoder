function exe = pythonExecutable()
%PYTHONEXECUTABLE Resolve the Python executable used by the CLI bridge.
exe = getenv('DMR_DEMO_PYTHON');
if isempty(exe)
    projectPython = '/home/lzkj/miniconda3/envs/DMR_demo/bin/python';
    if exist(projectPython, 'file') == 2
        exe = projectPython;
    else
        exe = 'python3';
    end
end
end
