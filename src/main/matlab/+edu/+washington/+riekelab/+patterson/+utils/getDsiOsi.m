function [dsi, osi] = getDsiOsi(directions, data)
% GETDSIOSI
% 
% Syntax:
%   [dsi, osi] = getDsiOsi(directions, responses)
%
% Input:
%   directions          angles in degrees (all unique, between 0 and 360)
%   responses           response magnitude for each direction
%
% Output:
%   dsi                 direction selectivity index
%   osi                 orientation selectivity index
%
% History:
%   19Sep2020 - SSP
% -------------------------------------------------------------------------

    [peak_response, idx] = max(data);
    peak_direction = directions(idx);
    
    a = data(closestAngleIndex(directions, mod(peak_direction + 180, 360)));
    b = data(closestAngleIndex(directions, mod(peak_direction + 90, 360)));
    c = data(closestAngleIndex(directions, mod(peak_direction + 270, 360)));
    
    dsi = (peak_response - a) / (peak_response + eps);
    osi = (peak_response + b - c + a) / (peak_response + a + eps);
    
end

function idx = closestAngleIndex(directions, target)
    [~, idx] = min(abs(directions - target));
end
    
    