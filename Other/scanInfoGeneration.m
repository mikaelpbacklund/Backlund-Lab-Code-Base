setsXY = 8;
paramToList = 'pi';%pi/tau
pb = app.ex.pulseBlaster;
piSet = 52;
tauSet = 200;
RFRamp = 8;

if strcmpi(paramToList,'pi')
   locList = findPulses(pb,'notes','π','contains');   
   halfLocList = findPulses(pb,'notes','π/2','contains');   
   n = piSet;
elseif strcmpi(paramToList,'tau') %#ok<*UNRCH>
   locList = findPulses(pb,'notes','τ','contains');
   halfLocList = findPulses(pb,'notes','τ/2','contains');   
   n = tauSet;
else
   error('invalid param')
end
for jj = 1:numel(halfLocList)
   halfLocList(jj) = find(locList==halfLocList(jj));
end

nLocs = numel(locList);
numList = '';
for ii = 1:nLocs
   if ismember(ii,halfLocList)
      val = round(num2str((n/2)+RFRamp));
   else
      val = num2str(n+RFRamp);
   end
   
   numList(end+1:end+numel(val)) = val;
   numList(end+1) = ','; %#ok<SAGROW>
end
numList(end) = [];