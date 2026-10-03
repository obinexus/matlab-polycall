function outputPath = build_matlab_polycall(varargin)
%BUILD_MATLAB_POLYCALL Build the MEX gateway against an installed libpolycall.
%   build_matlab_polycall(PREFIX) uses PREFIX/include/polycall and
%   PREFIX/lib (the layout `cmake --install` and the release archives use);
%   extra arguments are passed to mex. Example:
%       build_matlab_polycall("C:\polycall")          % polycall.lib / libpolycall.dll.a
%       build_matlab_polycall("/opt/polycall")        % libpolycall.so
%   At run time the shared library must be found: PATH (polycall.dll /
%   libpolycall.dll) on Windows, LD_LIBRARY_PATH or the system library path
%   (libpolycall.so.1) on Linux.

root = fileparts(mfilename("fullpath"));
if nargin < 1
    error("OBINexus:Polycall:Build", "pass the libpolycall install prefix");
end
prefix = string(varargin{1});
outputDirectory = fullfile(root, "lib");
if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end

% Bind every libpolycall symbol at load time: an old 1.0 library then fails
% with an "undefined symbol" load error instead of terminating MATLAB on the
% first call (Windows import tables always bind at load).
linkFlags = {};
if ismac
    linkFlags = {'LDFLAGS=$LDFLAGS -Wl,-bind_at_load'};
elseif isunix
    linkFlags = {'LDFLAGS=$LDFLAGS -Wl,-z,now'};
end

mex("-R2018a", ...
    "-I" + fullfile(root, "include"), ...
    "-I" + fullfile(prefix, "include", "polycall"), ...
    fullfile(root, "src", "matlab_polycall_mex.c"), ...
    fullfile(root, "src", "matlab_polycall.c"), ...
    "-L" + fullfile(prefix, "lib"), "-lpolycall", ...
    linkFlags{:}, ...
    varargin{2:end}, ...
    "-outdir", outputDirectory, ...
    "-output", "matlab_polycall_mex");

outputPath = fullfile(outputDirectory, "matlab_polycall_mex." + mexext);
end
