classdef (Abstract) Model < matlab.mixin.Copyable
    properties (Abstract)
        Parameters mftyre.v62.Parameters
        File char
        Description string
        Version {isnumeric}
    end
end