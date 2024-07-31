function [h,scanInfo,paramRequest] = SpinEcho(h,p)
%Creates Spin Echo sequence based on given parameters
%h is pulse blaster object, p is parameters cell array

%Paramaters needed for this template, along with their defaults
paramRequest = {
   'RF Resonance Frequency',[];%1
   'π',[];%2
   'τ Start',[];%3
   'τ End',[];%4
   'τ Steps',[];%5
   'τ Step Size',[];%6
   'Collection Duration',1000;%7
   'Pre-Collection Buffer Duration',1000;%8
   'Repolarization Duration',7000;%9
   'Buffer Between Signal and Reference',2500;%10
   'Total Sequence Duration (s)',1;%11
   'RF Duration Reduction',0;%12
   'AOM/DAQ Delay Compensation',0;%13
   'I/Q Pre-Buffer',0;%14
   'I/Q Post-Buffer',0%15
   };

%Creates empty variable for scanInfo in case of parameter request
scanInfo = [];

%If the first input is empty, only the second output matters, so the function ends here
if isempty(h);   return;  end

%Shorthand for code readability
RFfreq = p{1,2};
piDuration = p{2,2};
tauStart = p{3,2};
tauEnd = p{4,2};
tauNSteps = p{5,2};
tauStepSize = p{6,2};
collectionDuration = p{7,2};
preCollectionBufferDuration = p{8,2};
repolarizationDuration = p{9,2};
blankBufferDuration = p{10,2};
totalSequenceDuration = p{11,2};
RFReduction = p{12,2};
AOMDAQCompensation = p{13,2};
IQBuffer = [p{14,2} p{15,2}];

%Deletes prior sequence
h.userSequence = [];

%Ensures that required parameters are given
for ii = 1:4
   if isempty(p{ii,2})
      error('Parameter cell array must contain information for %s (input row %d)',p{ii,1},ii)
   end
end


%Checks if either step size or number of steps is given. If it is step size, checks if pulse is given then calculates
%number of steps based on that
if isempty(tauNSteps)
   if isempty(tauStepSize)
      error('Parameter input must contain τ Steps (input row 5) or τ Step Size (input row 6)')
   end
   tauNSteps = ceil(abs((tauEnd-tauStart)/tauStepSize));%Absolute value allows for reverse scans
end

%Sets tau durations to start and end of scan. Subtracts pulses to make tau given by parameters match the difference between
%the middle of each π pulse. Gives error if either of these numbers are negative
tauDuration = [tauStart tauEnd];
tauDuration = tauDuration - (3/4)*piDuration + RFReduction - sum(IQBuffer);
if any(tauDuration < 0)
   error('Input tau would result in negative duration for sent tau pulse')
end

%% Creation of Pulse Sequence

for ii = 1:2 %Signal/Reference

   %π/2 to create superposition
   currentPulse.activeChannels = {'RF'};
   if ii == 2; currentPulse.activeChannels{end+1} = 'Signal';      end%Adds signal channel only for second loop
   currentPulse.duration = piDuration/2+RFReduction;
   currentPulse.notes = 'Starting π/2 x';
   h = addPulse(h,currentPulse);

   %Scanned τ time
   currentPulse.activeChannels = {};
   if ii == 2; currentPulse.activeChannels{end+1} = 'Signal';      end
   currentPulse.duration = 99;
   currentPulse.notes = 'τ';
   h = addPulse(h,currentPulse);

   %π to flip and create echo
   currentPulse.activeChannels = {'RF','I'};
   if ii == 2; currentPulse.activeChannels{end+1} = 'Signal';      end
   currentPulse.duration = piDuration+RFReduction;
   currentPulse.notes = 'Middle π y';
   h = addPulse(h,currentPulse);

   %Scanned τ time
   currentPulse.activeChannels = {};
   if ii == 2; currentPulse.activeChannels{end+1} = 'Signal';      end
   currentPulse.duration = 99;
   currentPulse.notes = 'τ';
   h = addPulse(h,currentPulse);

   %π/2 -x to transfer to |0> OR π/2 x to transfer to |-1> for reference and signal respectively
   if ii == 1
      currentPulse.notes = 'Ending π/2 -x to |0>';
      currentPulse.activeChannels = {'RF','I','Q'};
   else
      currentPulse.notes = 'Ending π/2 x to |-1>';
      currentPulse.activeChannels = {'RF'};
   end
   if ii == 2; currentPulse.activeChannels{end+1} = 'Signal';      end
   currentPulse.duration = piDuration/2+ RFReduction;
   h = addPulse(h,currentPulse);

   %Data collection
   currentPulse.activeChannels = {'AOM','Data'};
   if ii == 2; currentPulse.activeChannels{end+1} = 'Signal';      end
   currentPulse.duration = collectionDuration;
   if ii == 1
      currentPulse.notes = 'Reference data collection';
   else
      currentPulse.notes = 'Signal data collection';
   end
   h = addPulse(h,currentPulse);

end

%% Sequence Additions/Corrections
%The following addBuffer functions are done for more or less every template. They add (in order): I/Q buffer for
%ensuring total coverage of RF pulse, a blank buffer between signal and referenece to separate the two fully, a
%repolarization pulse after data collection, a data collection buffer after the last RF pulse but before the laser or
%DAQ is turned on to ensure all RF pulses have resolved before data is collected, and an AOM/DAQ compensation pulse
%which accounts for the discrepancy between time delay between when each instrument turns on after pulse blaster sends a
%pulse (caused by differences in cable length and other minor electrical discrepancies). They are added in an order such
%that the final result is in the desired configuration

h = addBuffer(h,findPulses(h,'activeChannels',{'RF'},'contains'),IQBuffer,{'I','Q','Signal'},'I/Q buffer');

h = addBuffer(h,findPulses(h,'activeChannels',{'Data'},'contains'),blankBufferDuration,{'Signal'},'Blank buffer','after');

h = addBuffer(h,findPulses(h,'activeChannels',{'Data'},'contains'),repolarizationDuration,{'AOM','Signal'},'Repolarization','after');

h = addBuffer(h,findPulses(h,'activeChannels',{'Data'},'contains'),preCollectionBufferDuration,{'Signal'},'Data collection buffer','before');

%Negative number indicates DAQ pulse must be sent first
if AOMDAQCompensation > 0
   %Adds pulse with AOM on to account for lag between AOM and DAQ
   h = addBuffer(h,findPulses(h,'activeChannels',{'Data'},'contains'),AOMDAQCompensation,{'AOM','Signal'},'DAQ delay compensation','before');
   
   %Shortens the repolarization time in accordance with the added time above
   newRepolarization = repolarizationDuration - AOMDAQCompensation;
   repolarizationAddresses = findPulses(h,'notes','Repolarization','contains');
   h = modifyPulse(h,repolarizationAddresses,'duration',newRepolarization);
else
   %Adds pulse with DAQ on to account for lag between DAQ and AOM
   h = addBuffer(h,findPulses(h,'activeChannels',{'Data'},'contains'),abs(AOMDAQCompensation),{'Signal'},'AOM/DAQ delay compensation','before');
   
   %Shortens the data collection time in accordance with the added time above
   newDataDuration = collectionDuration - abs(AOMDAQCompensation);
   dataAddresses = findPulses(h,'notes','data collection','contains');
   h = modifyPulse(h,dataAddresses,'duration',newDataDuration);
end

%% Final Calculations

%Get the duration of the pulse sequence
sequenceDuration = calculateDuration(h,'user');

%Calculate the number of loops needed to get the target sequence duration
h.nTotalLoops = ceil((totalSequenceDuration*1e9)/sequenceDuration);
h.useTotalLoop = true;

%Sends the completed sequence to the pulse blaster
h = sendToInstrument(h);

%Finds pulses designated as τ which will be scanned
scanInfo.address = findPulses(h,'notes','τ','contains');

%Info regarding the scan
for ii = 1:numel(scanInfo.address)
   scanInfo.bounds{ii} = tauDuration;
end
scanInfo.nSteps = tauNSteps;
scanInfo.parameter = 'duration';
scanInfo.instrument = 'pulse_blaster';
scanInfo.notes = sprintf('Spin Echo (RF: %.3f GHz, π: %d ns)',RFfreq,piDuration);
scanInfo.RFfrequency = RFfreq;
scanInfo.trueTauDurations = [tauStart tauEnd];

end