%Lowest tau duration must be greater than the sum of before and after IQ
%buffer and (3/4) * pi duration
%e.g. if IQ buffers are [20 40] and pi duration is 80
%20+40+(3/4)*80 = 120 minimum

%% Begin User Edit
%Settings
RFFrequency = 2.87;
piDuration = 170;
scanStartDuration = 250;
scanEndDuration = 10000;
scanNSteps = 0;%Overrides step size. Set to 0 to use step size
scanStepSize = 250;
nIterations = 10;
scanTitle = 'Spin Echo';

%System settings
IQBuffer = [50 0];%Before and after IQ buffer
dataCollectionDuration = 1000;
blankBufferDuration = 2500;
dataCollectionBufferDuration = 1000;
repolarizationDuration = 7000;
aomCompensation = -10;

%% Stop User Edits
%% Load instruments (see ODMR script for explanation)
if ~exist('instr','var')
    instr{1} = RF_generator;
    instr{1} = connect(instr{1},'RF_generator_config');
    instr{1} = toggle(instr{1},'on');
    instr{1} = modulationToggle(instr{1},'on');
    instr{1} = setAmplitude(instr{1},10);
    instr{1} = setFrequency(instr{1},RFFrequency);
    instr{2} = DAQ_controller;
    instr{2} = connect(instr{2},'NI_DAQ_config');
    instr{2} = setSignalDifferentiation(instr{2},'on');
    instr{2} = setDataChannel(instr{2},'counter');
    instr{3} = pulse_blaster;
    instr{3} = connect(instr{3},'pulse_blaster_config');
end
if ~exist('ex','var')
   ex = experiment;
end
ex = validExperimentalConfiguration(ex,instr,'pulse sequence');

%% Create pulse sequence
%instr{3} is the pulse blaster

%% Begin User Edit

instr{3}.nTotalLoops = 2e5;%Number of times entire sequence is repeated
instr{3}.userSequence = [];%Deletes whatever the current sequence is

clear pulseInfo 
for ii = 1:2
pulseInfo.activeChannels = {'RF'};
pulseInfo.duration = piDuration/2;
pulseInfo.notes = 'π/2 x';
instr{3} = finalizePulse(instr{3},pulseInfo,ii);

pulseInfo.activeChannels = {};
pulseInfo.duration = 99;
pulseInfo.notes = 'τ';
instr{3} = finalizePulse(instr{3},pulseInfo,ii);

pulseInfo.activeChannels = {'RF','I'};
pulseInfo.duration = piDuration;
pulseInfo.notes = 'π y';
instr{3} = finalizePulse(instr{3},pulseInfo,ii);

pulseInfo.activeChannels = {};
pulseInfo.duration = 99;
pulseInfo.notes = 'τ';
instr{3} = finalizePulse(instr{3},pulseInfo,ii);

if ii == 1
    pulseInfo.notes = 'π/2 -x';
    pulseInfo.activeChannels = {'RF','I','Q'};
else
    pulseInfo.notes = 'π/2 x';
    pulseInfo.activeChannels = {'RF'};
end
pulseInfo.duration = piDuration/2;
instr{3} = finalizePulse(instr{3},pulseInfo,ii);

if ii == 1
    pulseInfo.notes = 'Reference data collection';
else
    pulseInfo.notes = 'Signal data collection';
end
pulseInfo.activeChannels = {'AOM','Data'};
pulseInfo.duration = dataCollectionDuration;
instr{3} = finalizePulse(instr{3},pulseInfo,ii);
end


%% Stop User Edit

%The following addBuffer functions should more or less be done for every
%script. They add (in order): I/Q buffer for ensuring total coverage of RF
%signal, a blank buffer between signal and reference to ensure complete
%separation, a repolarization pulse after data collection, a data
%collection buffer after the last RF pulse but before the laser is turned
%on to ensure all RF pulses have gone off before data is collected, and a
%AOM/DAQ compensation pulse which accounts for the discrepancy between when
%each instrument turns on when given a pulse by the pulse blaster
instr{3} = addBuffer(instr{3},findPulses(instr{3},'activeChannels',{'RF'},'contains'),IQBuffer,{'I','Q','Signal'},'I/Q buffer');

instr{3} = addBuffer(instr{3},findPulses(instr{3},'activeChannels',{'Data'},'contains'),...
        blankBufferDuration,{'Signal'},'Blank buffer','after');

instr{3} = addBuffer(instr{3},findPulses(instr{3},'activeChannels',{'Data'},'contains'),...
        repolarizationDuration,{'AOM','Signal'},'Repolarization','after');

instr{3} = addBuffer(instr{3},findPulses(instr{3},'activeChannels',{'Data'},'contains'),...
        dataCollectionBufferDuration,{'Signal'},'Data collection buffer','before');

if aomCompensation > 0
    channelsOn = {'AOM','Signal'};
else
    channelsOn = {'Data','Signal'};    
end
instr{3} = addBuffer(instr{3},findPulses(instr{3},'activeChannels',{'Data'},'contains'),...
    abs(aomCompensation),channelsOn,'AOM/DAQ delay compensation','before');

%Sends the current pulse sequence to the pulse blaster. Largely irrelevant
%as this happens at every data point in the scan, but for good practice it
%is here
instr{3} = sendToInstrument(instr{3});
fprintf('Pulse sequence %g s\n',instr{3}.sentSequenceDuration/1e9)

%% Create scan
%% Begin specific to this script
scan = [];
ex.scan = [];

%Set scan address to any pulses containing tau
scan.address = findPulses(instr{3},'notes','τ','contains');

%Adjusts scan start and end duration based on I/Q buffer additions
IQPulses = findPulses(instr{3},'notes','I/Q buffer','matches');
durationBeforeAdjustment = zeros(1,numel(scan.address));

durationBeforeAdjustment(:) = scanStartDuration;
startDurations = calculatePulseModifications(instr{3},scan.address,IQPulses,[],[],durationBeforeAdjustment);
startDurations = startDurations - (3/4)*piDuration;%Tau must subtract 3pi/4

durationBeforeAdjustment(:) = scanEndDuration;
endDurations = calculatePulseModifications(instr{3},scan.address,IQPulses,[],[],durationBeforeAdjustment);

%Set the bounds for all pulse addresses' durations to adjusted tau start and end
for ii = 1:numel(scan.address)
    scan.bounds{ii} = [startDurations(ii) endDurations(ii)];
end

%% End specific to this script

%Sets number of steps and corresponding step size
if scanNSteps ~= 0 %Priority to number of steps
   scan.nSteps = scanNSteps;
elseif scanStepSize ~= 0
   scan.stepSize = scanStepSize;
else
   error('τ n steps or step size required')
end

ex.forcedCollectionPauseTime = .05;

%Give remaining information about the scan
scan.parameter = 'duration';
scan.instrument = 'pulse_blaster';
scan.notes = scanTitle;

ex = addScans(ex,scan);

ex = validExperimentalConfiguration(ex,instr,'pulse sequence');

fprintf('Number of steps in scan: %d\n',ex.scan.nSteps(1))

%% Run scan, and collect and display data

%Prepares experiment to run from scratch
%[0,0] is the value that all initial values for the data will take
%Two values are used because we are storing ref and sig
ex = resetAllData(ex,[0 0]);

for ii = 1:nIterations
   
   %Prepares scan for a fresh start while keeping data from previous
   %iterations
   [ex,instr] = resetScan(ex,instr);
   
   %While the odometer is not at its max value
   while ~all(ex.odometer == [ex.scan.nSteps])

      [ex,instr] = takeNextDataPoint(ex,instr,'pulse sequence');      

      %Plot the average contrast for each data point
      c = findContrast(ex,'average');
      ex = make1DPlot(ex,c,'average');      
   end

   if ii ~= nIterations
       continueIterations = input('Continue? true or false\n');
       if ~continueIterations
           break
       end
   end
   
end

%Stops continuous collection from DAQ
stop(instr{2}.handshake)

fprintf('Scan complete\n')

function h = finalizePulse(h,pulseInfo,ii)
%Quick function to save lines when adding pulses
if ii == 2
    pulseInfo.activeChannels{end+1} = 'Signal';
end
h = addPulse(h,pulseInfo);
end







