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
defaultParameters.dataOnBuffer = 0;
defaultParameters.extraBuffer = 0;

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

if any(isempty({p.RF1ResonanceFrequency,p.RF2DurationStart,p.RF2DurationEnd,p.RF2Frequency})) || (isempty(p.RF2DurationNSteps) && isempty(p.RF2DurationStepSize))
   error('Parameter input must contain RF1ResonanceFrequency, RF2DurationStart, RF2DurationEnd, RF2Duration, and (RF2DurationNSteps or RF2DurationStepSize)')
end

% if p.nRF2Pulses == 1  
%    if  p.RF2DurationEnd > p.tauTime + p.piTime || p.RF2DurationStart > p.tauTime + p.piTime
%       error('RF2 duration cannot be longer than τ duration (%d) + π duration (%d)',p.tauTime,p.piTime)
%    end
%    if (p.RF2DurationStart < p.piTime && p.RF2DurationEnd > p.piTime) ||...
%          (p.RF2DurationStart > p.piTime && p.RF2DurationEnd < p.piTime)
%       error('RF2 duration cannot be scanned through pi time (%d). Please make scan either entirely less or entirely greater than pi time',p.piTime)
%    end   
% elseif p.nRF2Pulses == 2
   % if  p.RF2DurationStart > p.tauTime/2 - 30 - (3/4)*p.piTime || p.RF2DurationEnd > p.tauTime/2 - 30 - (3/4)*p.piTime
   %    error('RF2 duration cannot be longer than τ/2 duration (%d) - 30 - 3π/4 (%d)',p.tauTime/2,(3/4)*p.piTime)
   % end
% else
%    error('Number of RF2 pulses must be either 1 or 2')
% end

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

   h = condensedAddPulse(h,{addedSignal},30,'30 ns of τ');
   if p.nRF2Pulses == 1  
      h = condensedAddPulse(h,{addedSignal},49,'faux scanned rf2');
   else
       h = condensedAddPulse(h,{'RF2',addedSignal},49,'scanned rf2');
   end
      h = condensedAddPulse(h,{addedSignal},99,'inverse scanned remainder of τ');
      h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
      h = condensedAddPulse(h,{addedSignal},30,'30 ns of τ');
      h = condensedAddPulse(h,{'RF2',addedSignal},49,'scanned rf2');
      h = condensedAddPulse(h,{addedSignal},99,'inverse scanned remainder of τ');
   
   % if p.nRF2Pulses == 1   
   % 
   %    if p.piTime > p.RF2DurationStart %All RF2 durations less than RF1 pi time
   %       h = condensedAddPulse(h,{addedSignal},p.tauTime,'τ');
   %       h = condensedAddPulse(h,{'RF','I',addedSignal},49,'inverse scanned remainder π');
   %       h = condensedAddPulse(h,{'RF','I','RF2',addedSignal},99,'scanned rf2 + π y');
   %       h = condensedAddPulse(h,{'RF','I',addedSignal},49,'inverse scanned remainder π');         
   %       h = condensedAddPulse(h,{addedSignal},p.tauTime,'τ');
   %    else
   %       h = condensedAddPulse(h,{addedSignal},99,'inverse scanned remainder τ');
   %       h = condensedAddPulse(h,{'RF2',addedSignal},49,'scanned rf2');
   %       h = condensedAddPulse(h,{'RF','I','RF2',addedSignal},totalPiTime,'π y + rf2');
   %       h = condensedAddPulse(h,{'RF2',addedSignal},49,'scanned rf2');
   %       h = condensedAddPulse(h,{addedSignal},99,'inverse scanned remainder τ');
   %    end
   % 
   % else
   % 
   %    h = condensedAddPulse(h,{addedSignal},30,'30 ns of τ');
   %    h = condensedAddPulse(h,{'RF2',addedSignal},49,'scanned rf2');
   %    h = condensedAddPulse(h,{addedSignal},99,'inverse scanned remainder of τ');
   %    h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
   %    h = condensedAddPulse(h,{addedSignal},30,'30 ns of τ');
   %    h = condensedAddPulse(h,{'RF2',addedSignal},49,'scanned rf2');
   %    h = condensedAddPulse(h,{addedSignal},99,'inverse scanned remainder of τ');
   % end

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
h = standardTemplateModifications(h,p.intermissionBufferDuration,p.repolarizationDuration,...
    p.collectionBufferDuration,p.AOM_DAQCompensation,IQBuffers,p.dataOnBuffer,p.extraBuffer);

%Changes number of loops to match desired time
h.nTotalLoops = floor(p.timePerDataPoint/h.sequenceDurations.user.totalSeconds);

%Sends the completed sequence to the pulse blaster
h = sendToInstrument(h);

%% Scan Calculations
scannedBounds = [p.RF2DurationStart,p.RF2DurationEnd];

%Bounds for compensation pulses to keep total length constant
% if p.nRF2Pulses == 1
   % if p.piTime > p.RF2DurationStart %short rf2
   %    %Keep π constant  
   %    remainderBounds = [floor((totalPiTime - p.RF2DurationStart)/2),floor((totalPiTime - p.RF2DurationEnd)/2)];
   % 
   % else %long rf2
   %    %Keep τ constant  
   %    remainderBounds = [(p.tauTime - p.RF2DurationStart),(p.tauTime - p.RF2DurationEnd)];
   % 
   % end
% else
   %Keep τ constant  
   remainderModifiers = 30+sum(IQBuffers)+(3/4)*p.piTime;
   remainderBounds = [(p.tauTime - (p.RF2DurationStart+remainderModifiers)),(p.tauTime - (p.RF2DurationEnd+remainderModifiers))];   
   
% end

%Gets addresses and sets bounds corresponding to those addresses
scannedAddresses = findPulses(h,'notes','scanned rf2','contains');
remainderAddresses = findPulses(h,'notes','remainder','contains');
scanInfo.address = [scannedAddresses,remainderAddresses];
scanInfo.bounds = {};
[scanInfo.bounds{1:numel(scannedAddresses)}] = deal(scannedBounds);
[scanInfo.bounds{1+numel(scannedAddresses):numel(scanInfo.address)}] = deal(remainderBounds);

%Remaining scan info
if ~isempty(p.RF2DurationStepSize)
    scanInfo.nSteps = round(abs(p.RF2DurationEnd-p.RF2DurationStart) ./ p.RF2DurationStepSize);
    scanInfo.nSteps = scanInfo.nSteps+1;%Matlab starts at 1
else
scanInfo.nSteps = p.RF2DurationNSteps;
end
scanInfo.parameter = 'duration';
scanInfo.identifier = 'Pulse Blaster';
scanInfo.notes = sprintf('DEER (π: %d ns, τ = %d ns, RF: %g GHz, RF2: %g GHz)',round(p.piTime),round(p.tauTime),p.RF1ResonanceFrequency,p.RF2Frequency);
scanInfo.RF1Frequency = p.RF1ResonanceFrequency;
scanInfo.RF2Frequency = p.RF2Frequency;

%% Outputs
varargout{1} = h;%returns pulse blaster object
varargout{2} = scanInfo;%returns scan info

end
