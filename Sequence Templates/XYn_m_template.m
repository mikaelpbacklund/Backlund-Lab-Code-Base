function [varargout] = XYn_m_template(h,p)
%Creates Spin Echo sequence based on given parameters
%h is pulse blaster object, p is parameters structure
%τ is defined as time between the center of one π pulse and the next
%τ/2 cannot be shorter than (sum(IQ buffers) + (3/4)*π + RF reduction)

%Creates default parameter structure
defaultParameters.RFResonanceFrequency = [];
defaultParameters.piTime = [];
defaultParameters.scanBounds = [];
defaultParameters.scanNSteps = [];
defaultParameters.scanStepSize = [];
defaultParameters.setsXYN = [];
defaultParameters.nXY = 8;%default number of XY pulses per set
defaultParameters.sequenceTimePerDataPoint = 1;
defaultParameters.collectionDuration = 800;
defaultParameters.collectionBufferDuration = 1000;
defaultParameters.repolarizationDuration = 7000;
defaultParameters.intermissionBufferDuration = 2500;
defaultParameters.RFRampTime = 0;
defaultParameters.AOMCompensation = 0;
defaultParameters.IQBuffers = [0 0];
defaultParameters.dataOnBuffer = 0;
defaultParameters.extraBuffer = 0;
defaultParameters.useCompensatingPulses = 0;

parameterFieldNames = string(fieldnames(defaultParameters));

%If no pulse blaster object is given, returns default parameter structure and list of field names
if isempty(h)
   varargout{1} = defaultParameters;%returns default parameter structure as first output

   varargout{2} = parameterFieldNames;%returns list of field names as second output
   return
end

if ~isstruct(p)
   error('Parameter input must be a structure')
end

%Check if required parameters fields are present
mustContainField(p,parameterFieldNames);

if isempty(p.RFResonanceFrequency) || isempty(p.scanBounds) || (isempty(p.scanNSteps) && isempty(p.scanStepSize))
   error('Parameter input must contain RFResonanceFrequency, scanBounds and (scanNSteps or scanStepSize)')
end

%Calculates number of steps if only step size is given
if isempty(p.scanNSteps)
   p.scanNSteps = ceil(abs(p.scanBounds(2)-p.scanBounds(1))/p.scanStepSize)+1;
end

%Calculates the duration of the τ pulse that will be sent to pulse blaster
scanInfo.reducedTauTime = sum(p.IQBuffers)+p.piTime+p.RFRampTime;
scanInfo.reducedTauByTwoTime = sum(p.IQBuffers)+(3/4)*p.piTime+p.RFRampTime;
exportedTau = p.scanBounds - scanInfo.reducedTauTime;
exportedTauByTwo = (p.scanBounds ./ 2) - scanInfo.reducedTauByTwoTime;

%Error check for τ/2 duration (τ/2 always shorter than τ)
if min(exportedTauByTwo) <= 0
   error('τ/2 cannot be shorter than (sum(IQ buffers) + (3/4)*π + RF reduction) + 10 = %d',scanInfo.reducedTauByTwoTime+10)
end

%% Sequence Creation

%Deletes prior sequence
h = deleteSequence(h);
h.nTotalLoops = 1;%Will be overwritten later, used to find time for 1 loop
h.useTotalLoop = true;

halfTotalPiTime = round(p.piTime/2 + p.RFRampTime);
totalPiTime = p.piTime + p.RFRampTime;

for rs = 1:2 %singal half and reference half
   %Adds whether signal channel is on or off
   if rs == 1
      addedSignal = [];
   else
      addedSignal = 'Signal';
   end

   %π/2 to create superposition
   h = condensedAddPulse(h,{'RF',addedSignal},halfTotalPiTime,'π/2 x');

   %Scanned (τ/2) between π/2 and π pulses
   h = condensedAddPulse(h,{addedSignal},mean(exportedTauByTwo),'Scanned τ/2');

   for m = 1:p.setsXYN
      for n = 1:p.nXY/2
          %for 4: x-y-x-y
          %for 8: x-y-x-y-y-x-y-x
         if mod(n,4) == 0 || mod(n,4) == 1
            h = condensedAddPulse(h,{'RF',addedSignal},totalPiTime,'π x');
            h = condensedAddPulse(h,{addedSignal},mean(exportedTau),'Scanned τ');
            h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
            h = condensedAddPulse(h,{addedSignal},mean(exportedTau),'Scanned τ');
         else
            h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
            h = condensedAddPulse(h,{addedSignal},mean(exportedTau),'Scanned τ');
            h = condensedAddPulse(h,{'RF',addedSignal},totalPiTime,'π x');
            h = condensedAddPulse(h,{addedSignal},mean(exportedTau),'Scanned τ');
         end
      end
   end

   %modify final tau to tau/2
   h = modifyPulse(h,numel(h.userSequence),'duration',mean(exportedTauByTwo),false);
   h = modifyPulse(h,numel(h.userSequence),'notes','Scanned τ/2',false);

   %π/2 to create collapse superposition to either 0 or -1 state for reference or signal
   if rs == 1
      h = condensedAddPulse(h,{'RF','I','Q',addedSignal},halfTotalPiTime,'π/2 -x');
      h = condensedAddPulse(h,{'Data','AOM',addedSignal},p.collectionDuration,'Reference data collection');
   else
      h = condensedAddPulse(h,{'RF',addedSignal},halfTotalPiTime,'π/2 x');
      h = condensedAddPulse(h,{'Data','AOM',addedSignal},p.collectionDuration,'Signal data collection');
   end
end

%Completes sequence with standard changes for template
%3rd input is for amount of time compensating pulse needs to be, dependent on tau
%duration and number
intermissionScanBound = diff(p.scanBounds).*p.setsXYN.*p.nXY;
h = completeSequence(h,p,intermissionScanBound);

%% Scan Calculations

%Finds pulses designated as τ which will be scanned
scanInfo.address = findPulses(h,'notes','τ','contains');

%Info regarding the scan
for ii = 1:numel(scanInfo.address)
   scanInfo.bounds{ii} = exportedTau;
end
for ii = [1,numel(scanInfo.bounds)/2,numel(scanInfo.bounds)/2+1,numel(scanInfo.bounds)]
    scanInfo.bounds{ii} = exportedTauByTwo;
end
if isfield(p,'useCompensatingPulses') && p.useCompensatingPulses
    compensatingPulses = findPulses(h,'notes','intermission','contains');
    for ii = 1:numel(compensatingPulses)        
        scanInfo.bounds{end+1} = p.intermissionBufferDuration + [intermissionScanBound 0];
        scanInfo.address(end+1) = compensatingPulses(ii);
    end
end
scanInfo.nSteps = p.scanNSteps;
scanInfo.parameter = 'duration';
scanInfo.identifier = 'Pulse Blaster';
scanInfo.notes = sprintf('XY%d-%d (π: %d ns, RF: %.3f GHz)',p.nXY,p.setsXYN,round(p.piTime),p.RFResonanceFrequency);
scanInfo.RFFrequency = p.RFResonanceFrequency;

%% Outputs
varargout{1} = h;%returns pulse blaster object
varargout{2} = scanInfo;%returns scan info

end
