function [varargout] = Correlation_template(h,p)
%Creates Spin Echo sequence based on given parameters
%h is pulse blaster object, p is parameters structure
%τ is defined as time between the center of one π pulse and the next
%τ/2 cannot be shorter than (sum(IQ buffers) + (3/4)*π + RF reduction)

%Creates default parameter structure
parameterStructure.RFResonanceFrequency = [];
parameterStructure.piTime = [];
parameterStructure.tauDuration = [];%
parameterStructure.tBounds = [];%
parameterStructure.tNSteps = [];%
parameterStructure.tStepSize = [];%
% parameterStructure.tauStart = [];
% parameterStructure.tauEnd = [];
% parameterStructure.tauNSteps = [];
% parameterStructure.tauStepSize = [];
parameterStructure.setsXYN = [];
parameterStructure.nXY = 8;%default number of XY pulses per set
parameterStructure.sequenceTimePerDataPoint = 5;
parameterStructure.collectionDuration = 800;
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

if isempty(p.RFResonanceFrequency) || isempty(p.tBounds) || (isempty(p.tNSteps) && isempty(p.tStepSize))
   error('Parameter input must contain RFResonanceFrequency, tauStart, tauEnd and (tauNSteps or tauStepSize)')
end

%Calculates number of steps if only step size is given
if isempty(p.tNSteps)
   p.tNSteps = ceil(abs((p.tBounds(2)-p.tBounds(1))/p.tStepSize)+1);
end

%Calculates the duration of the τ pulse that will be sent to pulse blaster
reducedTauDuration = p.tauDuration - (p.piTime+p.RFReduction);
reducedTauByTwoDuration =  (p.tauDuration/2) - ((3/4)*p.piTime+p.RFReduction);

%Error check for τ/2 duration (τ/2 always shorter than τ)
if reducedTauByTwoDuration < 0
   error('τ/2 cannot be shorter than (sum(IQ buffers) + (3/4)*π + RF reduction)')
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
   for corrSet = 1:2

   %π/2 to create superposition
   h = condensedAddPulse(h,{'RF',addedSignal},halfTotalPiTime,'π/2 x');

   %Scanned (τ/2) between π/2 and π pulses
   h = condensedAddPulse(h,{addedSignal},reducedTauByTwoDuration,'τ/2');

   for m = 1:p.setsXYN
      for n = 1:p.nXY/2
         if mod(n,4) == 1 || mod(n,4) == 2 %odd set
            h = condensedAddPulse(h,{'RF',addedSignal},totalPiTime,'π x');
            h = condensedAddPulse(h,{addedSignal},reducedTauDuration,'τ');
            h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
            h = condensedAddPulse(h,{addedSignal},reducedTauDuration,'τ');
         else %even set
            h = condensedAddPulse(h,{'RF','I',addedSignal},totalPiTime,'π y');
            h = condensedAddPulse(h,{addedSignal},reducedTauDuration,'τ');
            h = condensedAddPulse(h,{'RF',addedSignal},totalPiTime,'π x');
            h = condensedAddPulse(h,{addedSignal},reducedTauDuration,'τ');
         end
      end
   end

   %modify final tau to tau/2
   h = modifyPulse(h,numel(h.userSequence),'duration',reducedTauByTwoDuration,false);
   h = modifyPulse(h,numel(h.userSequence),'notes','τ/2',false);
   
   if corrSet == 1
      h = condensedAddPulse(h,{'RF','I',addedSignal},halfTotalPiTime,'π/2 y');
      h = condensedAddPulse(h,{addedSignal},99,'Scanned t corr');
   elseif rs == 1 %corrSet 2
      h = condensedAddPulse(h,{'RF','I',addedSignal},halfTotalPiTime,'π/2 y');
      h = condensedAddPulse(h,{'Data','AOM',addedSignal},p.collectionDuration,'Reference data collection');
   else %rs 2, corrSet 2
      h = condensedAddPulse(h,{'RF','Q',addedSignal},halfTotalPiTime,'π/2 -y');
      h = condensedAddPulse(h,{'Data','AOM',addedSignal},p.collectionDuration,'Reference data collection');
   end

   end
end

%See function for more detail. Modifies base sequence with necessary things to function properly
h = standardTemplateModifications(h,p.intermissionBufferDuration,p.repolarizationDuration,...
    p.collectionBufferDuration,p.AOMCompensation,p.IQBuffers,p.dataOnBuffer,p.extraBuffer);

%Changes number of loops to match desired time
h.nTotalLoops = 1;
h = calculateDuration(h,'user');
scanInfo.meanSequenceDuration = h.sequenceDurations.user.totalNanoseconds - 198;%198 is standin tcorr*2
scanInfo.meanSequenceDuration = scanInfo.meanSequenceDuration + (2*mean(p.tBounds));
h.nTotalLoops = round(p.sequenceTimePerDataPoint/(scanInfo.meanSequenceDuration*1e-9));
scanInfo.meanSequenceDuration = scanInfo.meanSequenceDuration * h.nTotalLoops;

%Sends the completed sequence to the pulse blaster
h = sendToInstrument(h);

%% Scan Calculations

%Finds pulses designated as τ which will be scanned
scanInfo.address = findPulses(h,'notes','t corr','contains');
nAddresses = numel(scanInfo.address);
%Info regarding the scan
for ii = 1:numel(scanInfo.address)
   scanInfo.bounds{ii} = p.tBounds;
end

compensatingPulses = findPulses(h,'notes','intermission','contains');
scanInfo.address(end+1:end+numel(compensatingPulses)) = compensatingPulses;
intermissionBounds = p.intermissionBufferDuration + [p.tBounds(2) p.tBounds(1)];
for ii = nAddresses+1:numel(scanInfo.address)
   scanInfo.bounds{ii} = intermissionBounds;
end

scanInfo.nSteps = p.tNSteps;
scanInfo.parameter = 'duration';
scanInfo.identifier = 'Pulse Blaster';
scanInfo.notes = sprintf('XY%d-%d Correlation (tau: %d ns)',p.nXY,p.setsXYN,p.tauDuration);
scanInfo.RFFrequency = p.RFResonanceFrequency;

%% Outputs
varargout{1} = h;%returns pulse blaster object
varargout{2} = scanInfo;%returns scan info

end
