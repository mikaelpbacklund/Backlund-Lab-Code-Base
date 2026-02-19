function [varargout] = Correlation_looped(h,p)
%Creates Correlation sequence based on given parameters
%h is pulse blaster object, p is parameters structure
%τ is defined as time between the center of one π pulse and the next
%τ/2 cannot be shorter than (sum(IQ buffers) + (3/4)*π + RFRampTime)

%Creates default parameter structure
defaultParameters.RFResonanceFrequency = [];
defaultParameters.piTime = [];
defaultParameters.tauDuration = [];%
defaultParameters.scanBounds = [];
defaultParameters.scanNSteps = [];
defaultParameters.scanStepSize = [];
defaultParameters.setsXYN = [];
defaultParameters.nXY = 8;%default number of XY pulses per set
defaultParameters.sequenceTimePerDataPoint = 5;
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
   p.scanNSteps = ceil(abs((p.scanBounds(2)-p.scanBounds(1))/p.scanStepSize)+1);
end

%Calculates the duration of the τ pulse that will be sent to pulse blaster
reducedTauDuration = p.tauDuration - (p.piTime+p.RFRampTime);
reducedTauByTwoDuration =  (p.tauDuration/2) - ((3/4)*p.piTime+p.RFRampTime);

%Error check for τ/2 duration (τ/2 always shorter than τ)
if reducedTauByTwoDuration < 0
   error('τ/2 cannot be shorter than (sum(IQ buffers) + (3/4)*π + RF reduction)')
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
   for corrSet = 1:2

      %π/2 to create superposition
      h = condensedAddPulse(h,{'RF',addedSignal},halfTotalPiTime,'π/2 x');

      %Looped xy8 (only relevant if >1 XY8s)
      if p.setsXYN > 1

         %Create pulse for τ/2 to begin but be excluded from loop
         clear pulseInfo
         pulseInfo.activeChannels = {addedSignal};
         pulseInfo.duration = reducedTauByTwoDuration;
         pulseInfo.notes = 'Scanned τ/2';
         pulseInfo.contextInfo = p.setsXYN-1;%how many loops there will be
         pulseInfo.directionType = 'START LOOP';
         h = addPulse(h,pulseInfo);

         %Loop: x τ y τ x τ y τ y τ x τ y x τ

         %Begin loop
         h = condensedAddPulse(h,{'RF',addedSignal},totalPiTime,'π x');
         h = condensedAddPulse(h,{addedSignal},reducedTauDuration,'Scanned τ');
         h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
         h = condensedAddPulse(h,{addedSignal},reducedTauDuration,'Scanned τ');
         h = condensedAddPulse(h,{'RF',addedSignal},totalPiTime,'π x');
         h = condensedAddPulse(h,{addedSignal},reducedTauDuration,'Scanned τ');
         h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
         h = condensedAddPulse(h,{addedSignal},reducedTauDuration,'Scanned τ');
         h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
         h = condensedAddPulse(h,{addedSignal},reducedTauDuration,'Scanned τ');
         h = condensedAddPulse(h,{'RF',addedSignal},totalPiTime,'π x');
         h = condensedAddPulse(h,{addedSignal},reducedTauDuration,'Scanned τ');
         h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
         h = condensedAddPulse(h,{addedSignal},reducedTauDuration,'Scanned τ');
         h = condensedAddPulse(h,{'RF',addedSignal},totalPiTime,'π x');

         clear pulseInfo
         pulseInfo.activeChannels = {addedSignal};
         pulseInfo.duration = reducedTauDuration;
         pulseInfo.notes = 'Scanned τ';
         pulseInfo.directionType = 'END LOOP';
         h = addPulse(h,pulseInfo);

         %End loop

      else
         %Scanned (τ/2) between π/2 and π pulses
         h = condensedAddPulse(h,{addedSignal},reducedTauByTwoDuration,'Scanned τ/2');
      end

      %Ending xy8
      h = condensedAddPulse(h,{'RF',addedSignal},totalPiTime,'π x');
      h = condensedAddPulse(h,{addedSignal},reducedTauDuration,'Scanned τ');
      h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
      h = condensedAddPulse(h,{addedSignal},reducedTauDuration,'Scanned τ');
      h = condensedAddPulse(h,{'RF',addedSignal},totalPiTime,'π x');
      h = condensedAddPulse(h,{addedSignal},reducedTauDuration,'Scanned τ');
      h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
      h = condensedAddPulse(h,{addedSignal},reducedTauDuration,'Scanned τ');
      h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
      h = condensedAddPulse(h,{addedSignal},reducedTauDuration,'Scanned τ');
      h = condensedAddPulse(h,{'RF',addedSignal},totalPiTime,'π x');
      h = condensedAddPulse(h,{addedSignal},reducedTauDuration,'Scanned τ');
      h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
      h = condensedAddPulse(h,{addedSignal},reducedTauDuration,'Scanned τ');
      h = condensedAddPulse(h,{'RF',addedSignal},totalPiTime,'π x');

      %Scanned (τ/2) between π/2 and π pulses
      h = condensedAddPulse(h,{addedSignal},reducedTauByTwoDuration,'Scanned τ/2');

      if corrSet == 1
         h = condensedAddPulse(h,{'RF','I',addedSignal},halfTotalPiTime,'π/2 y');
         h = condensedAddPulse(h,{addedSignal},mean(p.scanBounds),'Scanned t corr');
      elseif rs == 1 %corrSet 2
         h = condensedAddPulse(h,{'RF','I',addedSignal},halfTotalPiTime,'π/2 y');
         h = condensedAddPulse(h,{'Data','AOM',addedSignal},p.collectionDuration,'Reference data collection');
      else %rs 2, corrSet 2
         h = condensedAddPulse(h,{'RF','Q',addedSignal},halfTotalPiTime,'π/2 -y');
         h = condensedAddPulse(h,{'Data','AOM',addedSignal},p.collectionDuration,'Reference data collection');
      end

   end
end

%Completes sequence with standard changes for template
h = completeSequence(h,p);

%% Scan Calculations

%Finds pulses designated as t corr which will be scanned
scanInfo.address = findPulses(h,'notes','t corr','contains');

nAddresses = numel(scanInfo.address);
%Info regarding the scan
for ii = 1:numel(scanInfo.address)
   scanInfo.bounds{ii} = p.scanBounds;
end

%Adds compensating pulses to scan
if p.useCompensatingPulses
   scanInfo.address(end+1:end+numel(compensatingPulses)) = compensatingPulses;
   intermissionBounds = [p.intermissionBufferDuration+diff(p.scanBounds),p.intermissionBufferDuration];
   for ii = nAddresses+1:numel(scanInfo.address)
      scanInfo.bounds{ii} = intermissionBounds;
   end
end

scanInfo.nSteps = p.scanNSteps;
scanInfo.parameter = 'duration';
scanInfo.identifier = 'Pulse Blaster';
scanInfo.notes = sprintf('XY%d-%d Correlation (tau: %d ns)',p.nXY,p.setsXYN,p.tauDuration);
scanInfo.RFFrequency = p.RFResonanceFrequency;

%% Outputs
varargout{1} = h;%returns pulse blaster object
varargout{2} = scanInfo;%returns scan info

end
