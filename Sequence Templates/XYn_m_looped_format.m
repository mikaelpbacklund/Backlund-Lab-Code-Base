function [varargout] = XYn_m_looped_format(h,p)
%Creates XYN sequence based on given parameters
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
defaultParameters.templateScanCalculation = true;

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
if min(exportedTauByTwo) <= 10
   error('τ/2 cannot be shorter than (sum(IQ buffers) + (3/4)*π + RF reduction) + 10 = %d',scanInfo.reducedTauByTwoTime+10)
end

%% Sequence Creation

%Note: to get the looping behavior to be correct without messing up the τ/2
%pulses, it is necessary to separate the end xy8 from the looped section

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

   %Looped xy8 (only relevant if >1 XY8s)
   if p.setsXYN > 1

      %Create pulse for τ/2 to begin but be excluded from loop
      clear pulseInfo
      pulseInfo.activeChannels = {addedSignal};
      pulseInfo.duration = mean(exportedTauByTwo);
      pulseInfo.notes = 'Scanned τ/2';
      pulseInfo.contextInfo = p.setsXYN-1;%how many loops there will be
      pulseInfo.directionType = 'START LOOP';
      h = addPulse(h,pulseInfo);

      %Loop: x τ y τ x τ y τ y τ x τ y x τ

      %Begin loop
      h = condensedAddPulse(h,{'RF',addedSignal},totalPiTime,'π x');
      h = condensedAddPulse(h,{addedSignal},mean(exportedTau),'Scanned τ');
      h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
      h = condensedAddPulse(h,{addedSignal},mean(exportedTau),'Scanned τ');
      h = condensedAddPulse(h,{'RF',addedSignal},totalPiTime,'π x');
      h = condensedAddPulse(h,{addedSignal},mean(exportedTau),'Scanned τ');
      h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
      h = condensedAddPulse(h,{addedSignal},mean(exportedTau),'Scanned τ');
      h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
      h = condensedAddPulse(h,{addedSignal},mean(exportedTau),'Scanned τ');
      h = condensedAddPulse(h,{'RF',addedSignal},totalPiTime,'π x');
      h = condensedAddPulse(h,{addedSignal},mean(exportedTau),'Scanned τ');
      h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
      h = condensedAddPulse(h,{addedSignal},mean(exportedTau),'Scanned τ');
      h = condensedAddPulse(h,{'RF',addedSignal},totalPiTime,'π x');

      clear pulseInfo
      pulseInfo.activeChannels = {addedSignal};
      pulseInfo.duration = mean(exportedTau);
      pulseInfo.notes = 'Scanned τ';
      pulseInfo.directionType = 'END LOOP';
      h = addPulse(h,pulseInfo);

      %End loop

   else
      %Scanned (τ/2) between π/2 and π pulses
      h = condensedAddPulse(h,{addedSignal},mean(exportedTauByTwo),'Scanned τ/2');
   end

   %Ending xy8
   h = condensedAddPulse(h,{'RF',addedSignal},totalPiTime,'π x');
   h = condensedAddPulse(h,{addedSignal},mean(exportedTau),'Scanned τ');
   h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
   h = condensedAddPulse(h,{addedSignal},mean(exportedTau),'Scanned τ');
   h = condensedAddPulse(h,{'RF',addedSignal},totalPiTime,'π x');
   h = condensedAddPulse(h,{addedSignal},mean(exportedTau),'Scanned τ');
   h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
   h = condensedAddPulse(h,{addedSignal},mean(exportedTau),'Scanned τ');
   h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
   h = condensedAddPulse(h,{addedSignal},mean(exportedTau),'Scanned τ');
   h = condensedAddPulse(h,{'RF',addedSignal},totalPiTime,'π x');
   h = condensedAddPulse(h,{addedSignal},mean(exportedTau),'Scanned τ');
   h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
   h = condensedAddPulse(h,{addedSignal},mean(exportedTau),'Scanned τ');
   h = condensedAddPulse(h,{'RF',addedSignal},totalPiTime,'π x');

   %Scanned (τ/2) between π/2 and π pulses
   h = condensedAddPulse(h,{addedSignal},mean(exportedTauByTwo),'Scanned τ/2');

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

%Output pulse blaster object
varargout{1} = h;

%% Scan Calculations

if p.templateScanCalculation
   %Finds pulses designated as τ which will be scanned
   scanInfo.address = findPulses(h,'notes','τ','contains');
   for ii = 1:numel(scanInfo.address)
      switch ii
         case {1,numel(scanInfo.address)/2,numel(scanInfo.address)/2+1,numel(scanInfo.address)}
            scanInfo.bounds{ii} = exportedTauByTwo;
         otherwise
            scanInfo.bounds{ii} = exportedTau;
      end
   end

   % if isfield(p,'useCompensatingPulses') && p.useCompensatingPulses
   %    compensatingPulses = findPulses(h,'notes','intermission','contains');
   %    for ii = 1:numel(compensatingPulses)
   %       scanInfo.bounds{end+1} = p.intermissionBufferDuration + [intermissionScanBound 0];
   %       scanInfo.address(end+1) = compensatingPulses(ii);
   %    end
   % end
   scanInfo.nSteps = p.scanNSteps;
   scanInfo.parameter = 'duration';
   scanInfo.identifier = 'Pulse Blaster';
   scanInfo.notes = sprintf('XY%d-%d (π: %d ns, RF: %.3f GHz)',p.nXY,p.setsXYN,round(p.piTime),p.RFResonanceFrequency);
   scanInfo.RFFrequency = p.RFResonanceFrequency;

   %Output scan info
   varargout{2} = scanInfo;
end
end
