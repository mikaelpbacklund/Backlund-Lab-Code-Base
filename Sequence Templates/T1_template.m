function [varargout] = T1_template(h,p)
%Creates Spin Echo sequence based on given parameters
%h is pulse blaster object, p is parameters structure

%Creates default parameter structure
defaultParameters.scanBounds = [];
defaultParameters.scanNSteps = [];
defaultParameters.scanStepSize = [];
defaultParameters.sequenceTimePerDataPoint = 1;
defaultParameters.collectionDuration = 1000;%Matches sample rate
defaultParameters.collectionBufferDuration = 100;
defaultParameters.repolarizationDuration = 7000;
defaultParameters.dataOnBuffer = 0;
defaultParameters.extraBuffer = 0;%Only relevant if repolarization buffer isn't 0
defaultParameters.AOMCompensation = 0;

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

if isempty(p.scanBounds) || (isempty(p.scanNSteps) && isempty(p.scanStepSize))
   error('Parameter input must contain scanBounds, and (scanNSteps or scanStepSize)')
end

%Calculates number of steps if only step size is given
if isempty(p.scanNSteps)
   p.scanNSteps = ceil(abs(p.scanBounds(2)-p.scanBounds(1))/p.scanStepSize)+1;
end

%% Sequence Creation

%Deletes prior sequence
h = deleteSequence(h);
h.nTotalLoops = 1;%Will be overwritten later, used to find time for 1 loop
h.useTotalLoop = true;

%First pulse is variable RF duration, second is data collection
%Second input is active channels, third is duration, fourth is notes

h = condensedAddPulse(h,{},mean(p.scanBounds),'scanned τ');%Scanned
h = condensedAddPulse(h,{'aom'},p.repolarizationDuration,'aom on');
h = condensedAddPulse(h,{'signal'},mean(p.scanBounds),'scanned τ');
h = condensedAddPulse(h,{'aom'},p.AOMCompensation,'aom compensation');
h = condensedAddPulse(h,{'aom','data','signal'},p.collectionDuration,'signal data collection');
h = condensedAddPulse(h,{'aom','signal'},((p.repolarizationDuration-2000)/2),'repolarization');
h = condensedAddPulse(h,{'aom'},((p.repolarizationDuration-2000)/2),'repolarization');
h = condensedAddPulse(h,{'aom','data'},p.collectionDuration,'reference data collection');

h = calculateDuration(h,'user');

%Changes number of loops to match desired time
h.nTotalLoops = floor(p.sequenceTimePerDataPoint/h.sequenceDurations.user.totalSeconds);

%Sends the completed sequence to the pulse blaster
h = sendToInstrument(h);

%% Scan Calculations

%Finds pulses designated as τ which will be scanned  
scanInfo.address = findPulses(h,'notes','τ','contains');

%Info regarding the scan
for ii = 1:numel(scanInfo.address)
   scanInfo.bounds{ii} = p.scanBounds;
end
scanInfo.nSteps = p.scanNSteps;
scanInfo.parameter = 'duration';
scanInfo.identifier = 'Pulse Blaster';
scanInfo.notes = sprintf('T1');

%% Outputs
varargout{1} = h;%returns pulse blaster object
varargout{2} = scanInfo;%returns scan info

end