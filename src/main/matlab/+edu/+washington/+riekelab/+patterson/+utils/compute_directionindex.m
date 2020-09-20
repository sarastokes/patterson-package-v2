function [di, oi] = compute_directionindex( angles, rates )
% COMPUTE_DIRECTIONINDEX
%     DI = COMPUTE_DIRECTIONINDEX( ANGLES, RATES )
%
%     Takes ANGLES in degrees
%
%     di = (maxrate - rate(stimulus in oppositedirection))/maxrate
%            di == 1 means maximally selective
%            di == 0 means not selective
% -------------------------------------------------------------------------
  
  [~,ind]=max(rates);
  ang=angles(ind);
	
  j1 = findclosest(angles,mod(ang,360));
  j2 = findclosest(angles,mod(ang+180,360));
  j3 = findclosest(angles,mod(ang+90,360));
  j4 = findclosest(angles,mod(ang+270,360));
  m1 = rates(j1); 
  m2 = rates(j2);
  m3 = rates(j3); 
  m4 = rates(j4);
  di = (m1-m2)/(m1+0.0001); % direction index
  oi = (m1+m2-m3-m4)/(0.0001+(m1+m2)); % orientation

  di=round(100*di)/100;
  oi=round(100*oi)/100;
  
  % SSP added 5Mar2018
  fprintf('\tDSI = %.2f, OSI = %.2f\n', di, oi);
  
end

% SSP added 19Sep2020
function [idx, value] = findclosest(data, target)
  value = NaN(size(target));
  idx = NaN(size(target));
  for i = 1:length(target(:))
      [~, idx(i)] = min(abs(data - target(i)));
      value(i) = data(idx(i));
  end
end