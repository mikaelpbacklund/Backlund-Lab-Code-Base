function outNum = ResonanceDip(inNum,analysisType,nucleusType,gyroRatio)
%UNTITLED5 Summary of this function goes here
%   Detailed explanation goes here
if strcmp(nucleusType,'1H')
   gyroRatio = 42.58e2; %1/Gauss/s
elseif strcmp(nucleusType,'19F')
   gyroRatio = 40.05e2; %1/Gauss/s
elseif strcmp(nucleusType,'13C')
   gyroRatio = 10.71e2; %1/Gauss/s
elseif strcmp(nucleusType,'31P')
   gyroRatio = 17.24e2; %1/Gauss/s
elseif strcmp(nucleusType,'electron')
   gyroRatio = 27204e2; %1/Gauss/s
elseif strcmp(nucleusType,'manual')
   narginchk(4,4)
else
   error('ResonanceDip nucleus type (3rd argument) must be 1H, 19F, 13C, 31P, electron, or manual. If manual, 4th argument must be the gyromagnetic ratio.')
end

if strcmp(analysisType,'time')
   freq = gyroRatio * inNum; %Hz
   outNum = 1/(2*freq); %s
   outNum = outNum * 1e9; %ns
elseif strcmp(analysisType,'magnet strength')
   inNum = inNum *1e-9; %s
   freq = 1/(2*inNum); %Hz
   outNum = freq/gyroRatio; %Gauss
else
   error('ResonanceDip analysis type (2nd argument) must be time or magnet strength.')
end
end

