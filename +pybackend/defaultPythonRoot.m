function root = defaultPythonRoot()
%DEFAULTPYTHONROOT Resolve the current Python decoder project root.
root = getenv('DMR_DEMO_PYTHON_ROOT');
if isempty(root)
    root = '/home/lzkj/lzkj_workspace/python_docs/DMR_demo';
end
end

