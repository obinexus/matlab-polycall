#include "mex.h"

#include <stdint.h>

#include "matlab_polycall.h"

void mexFunction(
    int nlhs,
    mxArray *plhs[],
    int nrhs,
    const mxArray *prhs[]
) {
    char *config_path;
    int32_t status;

    if (nrhs != 1) {
        mexErrMsgIdAndTxt(
            "OBINexus:Polycall:ArgumentCount",
            "matlab_polycall_mex requires one configuration path."
        );
    }
    if (nlhs > 1) {
        mexErrMsgIdAndTxt(
            "OBINexus:Polycall:OutputCount",
            "matlab_polycall_mex returns at most one status value."
        );
    }
    if (!mxIsChar(prhs[0])) {
        mexErrMsgIdAndTxt(
            "OBINexus:Polycall:ConfigType",
            "The configuration path must be a character vector."
        );
    }

    config_path = mxArrayToUTF8String(prhs[0]);
    if (config_path == NULL) {
        mexErrMsgIdAndTxt(
            "OBINexus:Polycall:ConfigEncoding",
            "The configuration path could not be converted to UTF-8."
        );
    }

    status = matlab_polycall_run_config(config_path);
    mxFree(config_path);

    if (nlhs == 1) {
        plhs[0] = mxCreateNumericMatrix(1, 1, mxINT32_CLASS, mxREAL);
        *((int32_T *)mxGetData(plhs[0])) = (int32_T)status;
    }
}
