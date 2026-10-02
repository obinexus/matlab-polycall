function value = textArg(value, name)
%TEXTARG Normalize a string scalar / character row vector argument to char.
if isstring(value)
    if ~isscalar(value)
        error("OBINexus:Polycall:ConfigType", "%s must be a string scalar.", name);
    end
    value = char(value);
elseif ischar(value)
    if ~isempty(value) && size(value, 1) ~= 1
        error("OBINexus:Polycall:ConfigType", "%s must be a character row vector.", name);
    end
else
    error("OBINexus:Polycall:ConfigType", "%s must be text.", name);
end
end
