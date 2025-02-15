function outNum = magnetStrength(inNum,analysisType)
%Finds the RF frequency of the lower peak in GHz based on the magent
%strength in Gauss or vice versa
if strcmp(analysisType,'strength')
   outNum = ((2.87-inNum)/2.8)*1000; %magnet strength in Gauss
elseif strcmp(analysisType,'RF')
   outNum = 2.87 - (inNum * (2.8/1000)); %RF frequency in GHz
else
   error('MagnetStrength second argument must be strength or RF')
end
end

