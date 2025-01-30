function [varargout] = XYn_m_template(h,p)
%Creates Spin Echo sequence based on given parameters
%h is pulse blaster object, p is parameters structure
%τ is defined as time between the center of one π pulse and the next
%τ/2 cannot be shorter than (sum(IQ buffers) + (3/4)*π + RF reduction)

%Creates default parameter structure
parameterStructure.RFResonanceFrequency = [];
parameterStructure.piTime = [];
parameterStructure.tauStart = [];
parameterStructure.tauEnd = [];
parameterStructure.tauNSteps = [];
parameterStructure.tauStepSize = [];
parameterStructure.setsXYN = [];
parameterStructure.nXY = 8;%default number of XY pulses per set
parameterStructure.sequenceTimePerDataPoint = 1;
parameterStructure.collectionDuration = 1000;
parameterStructure.collectionBufferDuration = 1000;
parameterStructure.repolarizationDuration = 7000;
parameterStructure.intermissionBufferDuration = 2500;
parameterStructure.RFReduction = 0;
parameterStructure.AOMCompensation = 0;
parameterStructure.IQBuffers = [0 0];
parameterStructure.dataOnBuffer = 0;
parameterStructure.extraBuffer = 0;

parameterFieldNames = string(fieldnames(parameterStructure));

%If no pulse blaster object is given, returns default parameter structure and list of field names
if isempty(h)
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
   p.tauNSteps = ceil(abs((p.tauEnd-p.tauStart)/p.tauStepSize))+1;
end

%Calculates the duration of the τ pulse that will be sent to pulse blaster
scanInfo.reducedTauTime = sum(p.IQBuffers)+p.piTime+p.RFReduction;
scanInfo.reducedTauByTwoTime = sum(p.IQBuffers)+(3/4)*p.piTime+p.RFReduction;
exportedTauStart = p.tauStart - scanInfo.reducedTauTime;
exportedTauEnd = p.tauEnd - scanInfo.reducedTauTime;
exportedTauByTwoStart = (p.tauStart/2) - scanInfo.reducedTauByTwoTime;
exportedTauByTwoEnd = (p.tauEnd/2) - scanInfo.reducedTauByTwoTime;

%Error check for τ/2 duration (τ/2 always shorter than τ)
if min([exportedTauByTwoStart,exportedTauByTwoEnd]) <= 0
   error('τ cannot be shorter than (sum(IQ buffers) + (3/4)*π + RF reduction)')
end

%% Sequence Creation

%Deletes prior sequence
h = deleteSequence(h);
h.nTotalLoops = 1;%Will be overwritten later, used to find time for 1 loop
h.useTotalLoop = true;

halfTotalPiTime = round(p.piTime/2 + p.RFReduction);
totalPiTime = p.piTime + p.RFReduction;

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
   h = condensedAddPulse(h,{addedSignal},49,'Scanned τ/2');

   for m = 1:p.setsXYN
      for n = 1:p.nXY/2
         if mod(n,4) == 1 || mod(n,4) == 2 %odd set
            h = condensedAddPulse(h,{'RF',addedSignal},totalPiTime,'π x');
            h = condensedAddPulse(h,{addedSignal},99,'Scanned τ');
            h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
            h = condensedAddPulse(h,{addedSignal},99,'Scanned τ');
         else %even set
            h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
            h = condensedAddPulse(h,{addedSignal},99,'Scanned τ');
            h = condensedAddPulse(h,{'RF',addedSignal},totalPiTime,'π x');
            h = condensedAddPulse(h,{addedSignal},99,'Scanned τ');
         end
      end
   end

   %modify final tau to tau/2
   h = modifyPulse(h,numel(h.userSequence),'duration',49,false);
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


%See function for more detail. Modifies base sequence with necessary things to function properly
h = standardTemplateModifications(h,p.intermissionBufferDuration,p.repolarizationDuration,...
    p.collectionBufferDuration,p.AOMCompensation,p.IQBuffers,p.dataOnBuffer,p.extraBuffer);

%Changes number of loops to match desired time
nTau = ((p.setsXYN*p.nXY)+1);
scanInfo.meanSequenceDuration = h.sequenceDurations.user.totalNanoseconds - (nTau*99);
scanInfo.meanSequenceDuration = scanInfo.meanSequenceDuration + (nTau*mean([p.tauStart,p.tauEnd]));
h.nTotalLoops = floor(p.sequenceTimePerDataPoint/(scanInfo.meanSequenceDuration*1e-9));
scanInfo.meanSequenceDuration = scanInfo.meanSequenceDuration * h.nTotalLoops;

%Sends the completed sequence to the pulse blaster
h = sendToInstrument(h);

%% Scan Calculations

%Finds pulses designated as τ which will be scanned
scanInfo.address = findPulses(h,'notes','τ','contains');

%Info regarding the scan
for ii = 1:numel(scanInfo.address)
   scanInfo.bounds{ii} = [exportedTauStart exportedTauEnd];
end
scanInfo.bounds{1,end} = [exportedTauByTwoStart exportedTauByTwoEnd];
scanInfo.nSteps = p.tauNSteps;
scanInfo.parameter = 'duration';
scanInfo.identifier = 'Pulse Blaster';
scanInfo.notes = sprintf('XY%d-%d (π: %d ns, RF: %.3f GHz)',p.nXY,p.setsXYN,round(p.piTime),p.RFResonanceFrequency);
scanInfo.RFFrequency = p.RFResonanceFrequency;

%% Outputs
varargout{1} = h;%returns pulse blaster object
varargout{2} = scanInfo;%returns scan info

end
