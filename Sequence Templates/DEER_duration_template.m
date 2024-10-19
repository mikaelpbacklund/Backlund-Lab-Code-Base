function [varargout] = DEER_duration_template(h,p)
%Creates DEER sequence based on given parameters
%h is pulse blaster object, p is parameters structure
%τ cannot be shorter than (sum(IQ buffers) + (3/4)*π + extraRF)
%RF2 duration restricted by tau time (and pi time if single pulse)

%Creates default parameter structure (for ensuring correct names primarily)
defaultParameters.RF1ResonanceFrequency = [];
defaultParameters.piTime = [];
defaultParameters.tauTime = [];
defaultParameters.RF2DurationStart = [];
defaultParameters.RF2DurationEnd = [];
defaultParameters.RF2DurationNSteps = [];
defaultParameters.RF2DurationStepSize = [];
defaultParameters.RF2Frequency = [];
defaultParameters.nRF2Pulses = 1;%1 or 2, changes how pulse sequence is arranged
defaultParameters.timePerDataPoint = 1;
defaultParameters.collectionDuration = 1000;
defaultParameters.collectionBufferDuration = 1000;
defaultParameters.repolarizationDuration = 7000;
defaultParameters.intermissionBufferDuration = 2500;
defaultParameters.extraRF = 0;
defaultParameters.AOM_DAQCompensation = 0;
defaultParameters.IQPreBufferDuration = 0;
defaultParameters.IQPostBufferDuration = 0;

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

if any(isempty({p.RFResonanceFrequency,p.RF2DurationStart,p.RF2DurationEnd,p.RF2Frequency})) || (isempty(p.RF2DurationNSteps) && isempty(p.RF2DurationStepSize))
   error('Parameter input must contain RFResonanceFrequency, RF2DurationStart, RF2DurationEnd, RF2Duration, and (RF2DurationNSteps or RF2DurationStepSize)')
end

if p.nRF2Pulses == 1  
   if  p.RF2DurationEnd > p.tauTime + p.piTime || p.RF2DurationStart > p.tauTime + p.piTime
      error('RF2 duration cannot be longer than τ duration (%d) + π duration (%d)',p.tauTime,p.piTime)
   end
   if (p.RFDurationStart < p.piTime && p.RFDurationEnd > p.piTime) ||...
         (p.RFDurationStart > p.piTime && p.RFDurationEnd < p.piTime)
      error('RF2 duration cannot be scanned through pi time (%d). Please make scan either entirely less or entirely greater than pi time',p.piTime)
   end   
elseif p.nRF2Pulses == 2
   if  p.RF2DurationStart > p.tauTime + 30 || p.RF2DurationEnd > p.tauTime + 30
      error('RF2 duration cannot be longer than τ duration (%d) + 30',p.tauTime)
   end
else
   error('Number of RF2 pulses must be either 1 or 2')
end

%Calculates number of steps if only step size is given
if isempty(p.frequencyNSteps)
   p.frequencyNSteps = ceil(abs((p.frequencyEnd-p.frequencyStart)/p.frequencyStepSize));
end

%Creates single array for I/Q pre and post buffers
IQBuffers = [p.IQPreBufferDuration,p.IQPostBufferDuration];

%% Sequence Creation

%Deletes prior sequence
h = deleteSequence(h);
h.nTotalLoops = 1;%Will be overwritten later, used to find time for 1 loop
h.useTotalLoop = true;

halfTotalPiTime = p.piTime/2 + p.extraRF;
totalPiTime = p.piTime + p.extraRF;

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

      if p.piTime > p.RF2DurationStart %All RF2 durations less than RF1 pi time
         h = condensedAddPulse(h,{addedSignal},p.tauTime,'τ');
         h = condensedAddPulse(h,{'RF','I',addedSignal},49,'scanned (duration difference/2)');
         h = condensedAddPulse(h,{'RF','I','RF2',addedSignal},99,'scanned π y + rf2');
         h = condensedAddPulse(h,{'RF','I',addedSignal},49,'inverse scanned π y');         
         h = condensedAddPulse(h,{addedSignal},p.tauTime,'τ');
      else
         h = condensedAddPulse(h,{addedSignal},99,'inverse scanned τ - (duration difference/2)');
         h = condensedAddPulse(h,{'RF2',addedSignal},49,'scanned rf2 duration difference/2');
         h = condensedAddPulse(h,{'RF','I','RF2',addedSignal},totalPiTime,'π y + rf2');
         h = condensedAddPulse(h,{'RF2',addedSignal},49,'scanned rf2 duration difference/2');
         h = condensedAddPulse(h,{addedSignal},99,'inverse scanned τ - (duration difference/2)');
      end

   else

      h = condensedAddPulse(h,{addedSignal},30,'30 ns of τ');
      h = condensedAddPulse(h,{'RF2',addedSignal},49,'scanned rf2');
      h = condensedAddPulse(h,{addedSignal},99,'inverse scanned remainder of τ');
      h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
      h = condensedAddPulse(h,{addedSignal},30,'30 ns of τ');
      h = condensedAddPulse(h,{'RF2',addedSignal},49,'scanned rf2');
      h = condensedAddPulse(h,{addedSignal},99,'inverse scanned remainder of τ');
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

%See function for more detail. Modifies base sequence with necessary things to function properly
h = standardTemplateModifications(h,p.intermissionBufferDuration,p.repolarizationDuration,p.collectionBufferDuration,p.AOM_DAQCompensation,IQBuffers);

%Changes number of loops to match desired time
h.nTotalLoops = floor(p.timePerDataPoint/h.sequenceDurations.user.totalSeconds);

%Sends the completed sequence to the pulse blaster
h = sendToInstrument(h);

%% Scan Calculations
%God this is gonna be nonsense

if p.nRF2Pulses == 1
   %short rf2
   %First addresses to be scanned are remainder π
   %They will have a duration of (pitime - rf2time)/2
   %Second addresses to be scanned are rf2+pi
   %They will have a duration of rf2time
   % h = condensedAddPulse(h,{'RF','I',addedSignal},-durationDifference/2,'inverse scanned π y');
   % h = condensedAddPulse(h,{'RF','I','RF2',addedSignal},99,'scanned π y + rf2');
   %long rf2   
   %First addresses to be scanned are remainder rf2
   %They will have a duration of (pitime - pitime)/2
   %Second addresses to be scanned are rf2+pi
   %They will have a duration of pitime
   % h = condensedAddPulse(h,{addedSignal},99,'inverse scanned τ - (duration difference/2)');
   % h = condensedAddPulse(h,{'RF2',addedSignal},49,'scanned rf2 duration difference/2');
else
   %First addresses to be scanned are remainder tau
   %They will have a duration of (tautime - rf2time)/2
   %Second addresses to be scanned are rf2
   %They will have a duration of rf2time
   % h = condensedAddPulse(h,{'RF2',addedSignal},49,'scanned rf2');
   % h = condensedAddPulse(h,{addedSignal},99,'inverse scanned remainder of τ');
end

%If notes contain "inverse", scanned value is flipped
%If notes contain remained




%Info regarding the scan
scanInfo.bounds = [p.frequencyStart,p.frequencyEnd];
scanInfo.nSteps = p.frequencyNSteps;
scanInfo.parameter = 'frequency';
scanInfo.identifier = 'windfreak';
scanInfo.notes = sprintf('DEER (π: %d ns, τ = %d, RF: %.3f GHz, RF2 duration: %d)',round(p.piTime),round(p.tauTime),p.RFResonanceFrequency,p.RF2Duration);
scanInfo.RFFrequency = p.RFResonanceFrequency;

%% Outputs
varargout{1} = h;%returns pulse blaster object
varargout{2} = scanInfo;%returns scan info

end
