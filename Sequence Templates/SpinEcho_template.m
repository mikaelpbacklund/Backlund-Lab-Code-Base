function [varargout] = SpinEcho_template(h,p)
%Creates Spin Echo sequence based on given parameters
%h is pulse blaster object, p is parameters structure
%τ cannot be shorter than (sum(IQ buffers) + (3/4)*π + extraRF)

parameterFieldNames = ["RFResonanceFrequency","piTime","tauStart","tauEnd","tauNSteps","tauStepSize",...
   "timePerDataPoint","collectionDuration","collectionBufferDuration","repolarizationDuration",...
   "intermissionBufferDuration","extraRF","AOM_DAQCompensation","IQPreBufferDuration","IQPostBufferDuration"];

%If no pulse blaster object is given, returns default parameter structure and list of field names
if isempty(h)
   %Creates default parameter structure
   parameterStructure.RFResonanceFrequency = [];
   parameterStructure.piTime = [];
   parameterStructure.tauStart = [];
   parameterStructure.tauEnd = [];
   parameterStructure.tauNSteps = [];
   parameterStructure.tauStepSize = [];
   parameterStructure.timePerDataPoint = 1;
   parameterStructure.collectionDuration = 1000;
   parameterStructure.collectionBufferDuration = 1000;
   parameterStructure.repolarizationDuration = 7000;
   parameterStructure.intermissionBufferDuration = 2500;
   parameterStructure.extraRF = 0;
   parameterStructure.AOM_DAQCompensation = 0;
   parameterStructure.IQPreBufferDuration = 0;
   parameterStructure.IQPostBufferDuration = 0;

   varargout{1} = parameterStructure;%returns default parameter structure as first output

   varargout{2} = parameterFieldNames;%returns list of field names as second output
   return
end

if ~isstruct(p)
   error('Parameter input must be a structure')
end

%Check if required parameters fields are present
mustContainField(p,parameterFieldNames);

if isempty(p.RFResonanceFrequency) || isempty(p.tauStart) || isempty(p.tauEnd) || (isempty(p.tauNSteps) && isempty(p.tauStepSize))
   error('Parameter input must contain RFResonanceFrequency, tauStart, tauEnd and (tauNSteps or tauStepSize)')
end

%Calculates number of steps if only step size is given
if isempty(p.tauNSteps)
   p.tauNSteps = ceil(abs((p.tauEnd-p.tauStart)/p.tauStepSize));
end

%Creates single array for I/Q pre and post buffers
IQBuffers = [p.IQPreBufferDuration,p.IQPostBufferDuration];

%Calculates the duration of the τ pulse that will be sent to pulse blaster
exportedTauStart = p.tauStart - (sum(IQBuffers)+(3/4)*p.piTime+p.extraRF);
exportedTauEnd = p.tauEnd - (sum(IQBuffers)+(3/4)*p.piTime+p.extraRF);

%Error check for τ duration
if min([exportedTauStart,exportedTauEnd]) <= 0
   error('τ cannot be shorter than (sum(IQ buffers) + (3/4)*π + extra RF)')
end

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

   %Scanned τ between π/2 and π pulses
   h = condensedAddPulse(h,{addedSignal},99,'Scanned τ');

   %π to rotate around y and generate echo
   h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');

   %Scanned τ between π and π/2 pulses
   h = condensedAddPulse(h,{addedSignal},99,'Scanned τ');

   %π/2 to create collapse superposition to either 0 or -1 state for reference or signal
   if rs == 1
      h = condensedAddPulse(h,{'RF','I','Q',addedSignal},halfTotalPiTime,'π/2 -x');
      h = condensedAddPulse(h,{'Data','AOM',addedSignal},p.collectionDuration,'Reference data collection');
   else
      h = condensedAddPulse(h,{'RF',addedSignal},halfTotalPiTime,'π/2 -x');
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

%Finds pulses designated as τ which will be scanned
scanInfo.address = findPulses(h,'notes','τ','contains');

%Info regarding the scan
for ii = 1:numel(scanInfo.address)
   scanInfo.bounds{ii} = [exportedTauStart,exportedTauEnd];
end
scanInfo.nSteps = p.tauNSteps;
scanInfo.parameter = 'duration';
scanInfo.identifier = 'Pulse Blaster';
scanInfo.notes = sprintf('Rabi (RF: %.3f GHz)',p.RFResonanceFrequency);
scanInfo.RFFrequency = p.RFResonanceFrequency;

%% Outputs
varargout{1} = h;%returns pulse blaster object
varargout{2} = scanInfo;%returns scan info

end
