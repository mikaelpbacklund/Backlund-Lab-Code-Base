function [varargout] = Rabi_template(h,p)
%Creates Spin Echo sequence based on given parameters
%h is pulse blaster object, p is parameters structure

%Creates default parameter structure
defaultParameters.RFResonanceFrequency = [];
defaultParameters.scanBounds = [];
defaultParameters.scanNSteps = [];
defaultParameters.scanStepSize = [];
defaultParameters.sequenceTimePerDataPoint = 1;
defaultParameters.collectionDuration = 800;%Matches sample rate
defaultParameters.collectionBufferDuration = 100;
defaultParameters.repolarizationDuration = 7000;
defaultParameters.dataOnBuffer = 0;
defaultParameters.extraBuffer = 0;%Only relevant if repolarization buffer isn't 0
defaultParameters.intermissionBufferDuration = 1000;
defaultParameters.AOMCompensation = 0;
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
   p.scanNSteps = ceil(abs((p.scanBounds(2)-p.scanBounds(1))/p.scanStepSize))+1;
end

%% Sequence Creation

%Deletes prior sequence
h = deleteSequence(h);
h.nTotalLoops = 1;%Will be overwritten later, used to find time for 1 loop
h.useTotalLoop = true;

%First pulse is variable RF duration, second is data collection
%Second input is active channels, third is duration, fourth is notes
h = condensedAddPulse(h,{},mean(p.scanBounds),'τ without-RF time');%Scanned
h = condensedAddPulse(h,{'AOM','Data'},p.collectionDuration,'Reference Data collection');

h = condensedAddPulse(h,{'RF','Signal'},mean(p.scanBounds),'τ with-RF time');%Scanned
h = condensedAddPulse(h,{'AOM','Data','Signal'},p.collectionDuration,'Signal Data collection');

%IQ buffers irrelevant for Rabi
p.IQBuffers = [0 0];

%Completes sequence with standard changes for template
h = completeSequence(h,p);

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
scanInfo.notes = sprintf('Rabi (RF: %.3f GHz)',p.RFResonanceFrequency);
scanInfo.RFFrequency = p.RFResonanceFrequency;

%% Outputs
varargout{1} = h;%returns pulse blaster object
varargout{2} = scanInfo;%returns scan info

end