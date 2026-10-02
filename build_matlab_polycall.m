function outputPath = build_matlab_polycall(varargin)
%BUILD_MATLAB_POLYCALL Build the MEX gateway against an installed libpolycall.
%   build_matlab_polycall(PREFIX) uses PREFIX/include/polycall and
%   PREFIX/lib (the layout `cmake --install` and the release archives use);
%   extra arguments are passed to mex. Example:
%       build_matlab_polycall("C:\polycall")          % polycall.lib / libpolycall.dll.a
%       build_matlab_polycall("/opt/polycall")        % libpolycall.so

root = fileparts(mfilename("fullpath"));
if nargin < 1
    error("OBINexus:Polycall:Build", "pass the libpolycall install prefix");
end
prefix = string(varargin{1});
outputDirectory = fullfile(root, "lib");
if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end

mex("-R2018a", ...
    "-I" + fullfile(root, "include"), ...
    "-I" + fullfile(prefix, "include", "polycall"), ...
    fullfile(root, "src", "matlab_polycall_mex.c"), ...
    fullfile(root, "src", "matlab_polycall.c"), ...
    "-L" + fullfile(prefix, "lib"), "-lpolycall", ...
    varargin{2:end}, ...
    "-outdir", outputDirectory, ...
    "-output", "matlab_polycall_mex");

outputPath = fullfile(outputDirectory, "matlab_polycall_mex." + mexext);
end
