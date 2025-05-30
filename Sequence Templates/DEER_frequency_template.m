function [varargout] = DEER_frequency_template(h,p)
%Creates DEER sequence based on given parameters
%h is pulse blaster object, p is parameters structure
%τ cannot be shorter than (sum(IQ buffers) + (3/4)*π + RFRampTime)
%RF2 duration restricted by tau time (and pi time if single pulse)

%Creates default parameter structure (for ensuring correct names primarily)
defaultParameters.RF1ResonanceFrequency = [];
defaultParameters.piTime = [];
defaultParameters.tauTime = [];
defaultParameters.scanBounds = [];
defaultParameters.scanNSteps = [];
defaultParameters.scanStepSize = [];
defaultParameters.sequenceTimePerDataPoint = 1;
defaultParameters.RF2Duration = [];
defaultParameters.nRF2Pulses = 1;%1 or 2, changes how pulse sequence is arranged
defaultParameters.collectionDuration = 1000;
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

if isempty(p.RF1ResonanceFrequency) || isempty(p.scanBounds) || isempty(p.RF2Duration) ||(isempty(p.scanNSteps) && isempty(p.scanStepSize))
   error('Parameter input must contain RF1ResonanceFrequency, scanBounds, RF2Duration, and (scanNSteps or scanStepSize)')
end

if p.nRF2Pulses == 1  
   if  p.RF2Duration > p.tauTime + p.piTime
      error('RF2 duration (%d) cannot be longer than τ duration (%d) + π duration (%d)',p.RF2Duration,p.tauTime,p.piTime)
   end
elseif p.nRF2Pulses == 2
   if  p.RF2Duration > p.tauTime + 30
      error('RF2 duration (%d) cannot be longer than τ duration (%d) + 30',p.RF2Duration,p.tauTime)
   end
else
   error('Number of RF2 pulses must be either 1 or 2')
end

%Calculates number of steps if only step size is given
if isempty(p.scanNSteps)
   p.scanNSteps = ceil(abs((p.scanBounds(2)-p.scanBounds(1))/p.scanStepSize))+1;
end

%% Sequence Creation

%Deletes prior sequence
h = deleteSequence(h);
h.nTotalLoops = 1;%Will be overwritten later, used to find time for 1 loop
h.useTotalLoop = true;

halfTotalPiTime = p.piTime/2 + p.RFRampTime;
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
   
   if p.nRF2Pulses == 1   

      durationDifference = p.RF2Duration - p.piTime;
      if durationDifference == 0 %RF1 matches RF2
         h = condensedAddPulse(h,{addedSignal},p.tauTime,'τ');
         h = condensedAddPulse(h,{'RF','I','RF2',addedSignal},totalPiTime,'π y + rf2');
         h = condensedAddPulse(h,{addedSignal},p.tauTime,'τ');
      elseif durationDifference > 0 %RF2 is longer than RF1
         h = condensedAddPulse(h,{addedSignal},p.tauTime-durationDifference/2,'τ - rf2 time');
         h = condensedAddPulse(h,{'RF2',addedSignal},durationDifference/2,'rf2');
         h = condensedAddPulse(h,{'RF','I','RF2',addedSignal},totalPiTime,'π y + rf2');
         h = condensedAddPulse(h,{'RF2',addedSignal},durationDifference/2,'rf2');
         h = condensedAddPulse(h,{addedSignal},p.tauTime-durationDifference/2,'τ - rf2 time');
      else%RF1 is longer than RF2
         h = condensedAddPulse(h,{addedSignal},p.tauTime,'τ');
         h = condensedAddPulse(h,{'RF','I',addedSignal},-durationDifference/2,'π y');
         h = condensedAddPulse(h,{'RF','I','RF2',addedSignal},p.RF2Duration,'π y + rf2');
         h = condensedAddPulse(h,{'RF','I',addedSignal},-durationDifference/2,'π y');         
         h = condensedAddPulse(h,{addedSignal},p.tauTime,'τ');
      end

   else

      h = condensedAddPulse(h,{addedSignal},30,'30 ns of τ');
      h = condensedAddPulse(h,{'RF2',addedSignal},p.RF2Duration,'rf2');
      h = condensedAddPulse(h,{addedSignal},p.tauTime - p.RF2Duration - 30 - (3/4)*p.piTime,'remainder of τ');
      h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
      h = condensedAddPulse(h,{addedSignal},30,'30 ns of τ');
      h = condensedAddPulse(h,{'RF2',addedSignal},p.RF2Duration,'rf2');
      h = condensedAddPulse(h,{addedSignal},p.tauTime - p.RF2Duration - 30 - (3/4)*p.piTime,'remainder of τ');
   end

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
p.useCompensatingPulses = 0;
h = completeSequence(h,p);

%% Scan Calculations
%Info regarding the scan
scanInfo.bounds = p.scanBounds;
if ~isempty(p.scanStepSize)
scanInfo.stepSize = p.scanStepSize;
else
scanInfo.nSteps = p.scanNSteps;
end
scanInfo.parameter = 'frequency';
scanInfo.identifier = 'windfreak';
scanInfo.notes = sprintf('DEER (π: %d ns, τ = %d ns, RF: %.3f GHz, RF2: %d ns)',round(p.piTime),round(p.tauTime),p.RF1ResonanceFrequency,p.RF2Duration);
scanInfo.SRSFrequency = p.RF1ResonanceFrequency;

%% Outputs
varargout{1} = h;%returns pulse blaster object
varargout{2} = scanInfo;%returns scan info

end
