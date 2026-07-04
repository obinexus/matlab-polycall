function tests = test_matlab_polycall
tests = functiontests(localfunctions);
end

function testSuccessStatus(testCase)
verifyEqual(testCase, ...
    obinexus.polycall.runConfig("matlab-polycallrc"), int32(0));
end

function testFailureStatus(testCase)
verifyEqual(testCase, ...
    obinexus.polycall.runConfig("__status_37__"), int32(37));
end

function testFailureCondition(testCase)
verifyError(testCase, ...
    @() obinexus.polycall.runConfigOrError("__status_37__"), ...
    "OBINexus:Polycall:CoreFailure");
end
