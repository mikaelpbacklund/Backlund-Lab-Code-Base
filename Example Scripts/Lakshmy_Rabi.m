%Runs a simple Rabi sequence with no τ compensation or stage optimization

piDuration = 50;
aomCompensation = -10;
startTauDuration = 10;
endTauDuration = 1010;
tauNSteps = 0;%Overrides step size. Set to 0 to use step size
tauStepSize = 25;
scanTitle = 'Spin Echo';
nIterations = 10;

%% Load instruments (see ODMR script for explanation)
if ~exist('instr','var')
    % instr{1} = RF_generator;
    % instr{1} = connect(instr{1},'RF_generator_config');
    % instr{1} = toggle(instr{1},'on');
    % instr{1} = modulationToggle(instr{1},'off');
    % instr{1} = setAmplitude(instr{1},10);
    % instr{2} = DAQ_controller;
    % instr{2} = connect(instr{2},'NI_DAQ_config');
    % instr{2} = setSignalDifferentiation(instr{2},'on');
    % instr{2} = setDataChannel(instr{2},'counter');
    instr{3} = pulse_blaster;
    instr{3} = connect(instr{3},'pulse_blaster_config');
    h.pb = pulse_blaster;
    h.pb = connect(h.pb,'pulse_blaster_config');
end
if ~exist('ex','var')
   ex = experiment;
end
% ex = validExperimentalConfiguration(ex,instr,'pulse sequence');

%% Create pulse sequence
%instr{3} is the pulse blaster

instr{3}.nTotalLoops = 2e5;%Number of times entire sequence is repeated
instr{3}.userSequence = [];%Deletes whatever the current sequence is

clear pulseInfo 
pulseInfo.activeChannels = {};
pulseInfo.duration = 2500;
pulseInfo.notes = 'Initial buffer';
instr{3} = addPulse(instr{3},pulseInfo);

pulseInfo.activeChannels = {'RF'};
pulseInfo.duration = piDuration/2;
pulseInfo.notes = 'RF time';
instr{3} = addPulse(instr{3},pulseInfo);

pulseInfo.activeChannels = {};
pulseInfo.duration = 100;
pulseInfo.notes = 'τ RF time';
instr{3} = addPulse(instr{3},pulseInfo);

pulseInfo.activeChannels = {'RF','I'};
pulseInfo.duration = piDuration;
pulseInfo.notes = 'RF time';
instr{3} = addPulse(instr{3},pulseInfo);

pulseInfo.activeChannels = {};
pulseInfo.duration = 100;
pulseInfo.notes = 'τ RF time';
instr{3} = addPulse(instr{3},pulseInfo);

pulseInfo.activeChannels = {'RF'};
pulseInfo.duration = piDuration/2;
pulseInfo.notes = 'RF time';
instr{3} = addPulse(instr{3},pulseInfo);

pulseInfo.activeChannels = {};
pulseInfo.duration = 1000;
pulseInfo.notes = 'Data collection buffer';
instr{3} = addPulse(instr{3},pulseInfo);

if aomCompensation > 0
   pulseInfo.activeChannels = {'AOM'};
else
   pulseInfo.activeChannels = {'DAQ'};
end
pulseInfo.duration = abs(aomCompensation);
pulseInfo.notes = 'AOM/DAQ delay compensation';
instr{3} = addPulse(instr{3},pulseInfo);

pulseInfo.activeChannels = {'AOM','Data'};
pulseInfo.duration = 1000;
pulseInfo.notes = 'Reference data collection';
instr{3} = addPulse(instr{3},pulseInfo);

pulseInfo.activeChannels = {'AOM'};
pulseInfo.duration = 7000;
pulseInfo.notes = 'Repolarization';
instr{3} = addPulse(instr{3},pulseInfo);

pulseInfo.activeChannels = {'Signal'};
pulseInfo.duration = 2500;
pulseInfo.notes = 'Middle buffer';
instr{3} = addPulse(instr{3},pulseInfo);

pulseInfo.activeChannels = {'RF', 'Signal'};
pulseInfo.duration = piDuration/2;
pulseInfo.notes = 'RF time';
instr{3} = addPulse(instr{3},pulseInfo);

pulseInfo.activeChannels = {'Signal'};
pulseInfo.duration = 100;
pulseInfo.notes = 'τ RF time';
instr{3} = addPulse(instr{3},pulseInfo);

pulseInfo.activeChannels = {'RF','Signal','I'};
pulseInfo.duration = piDuration;
pulseInfo.notes = 'RF time';
instr{3} = addPulse(instr{3},pulseInfo);

pulseInfo.activeChannels = {'Signal'};
pulseInfo.duration = 100;
pulseInfo.notes = 'τ RF time';
instr{3} = addPulse(instr{3},pulseInfo);

pulseInfo.activeChannels = {'RF','Signal','I','Q'};
pulseInfo.duration = piDuration/2;
pulseInfo.notes = 'RF time';
instr{3} = addPulse(instr{3},pulseInfo);

pulseInfo.activeChannels = {'Signal'};
pulseInfo.duration = 1000;
pulseInfo.notes = 'Data collection buffer';
instr{3} = addPulse(instr{3},pulseInfo);

if aomCompensation > 0
   pulseInfo.activeChannels = {'AOM','Signal'};
else
   pulseInfo.activeChannels = {'DAQ','Signal'};
end
pulseInfo.duration = abs(aomCompensation);
pulseInfo.notes = 'AOM/DAQ delay compensation';
instr{3} = addPulse(instr{3},pulseInfo);

pulseInfo.activeChannels = {'AOM','Data','Signal'};
pulseInfo.duration = 1000;
pulseInfo.notes = 'Signal data collection';
instr{3} = addPulse(instr{3},pulseInfo);

pulseInfo.activeChannels = {'AOM','Signal'};
pulseInfo.duration = 7000;
pulseInfo.notes = 'Repolarization';
instr{3} = addPulse(instr{3},pulseInfo);

% instr{3} = sendToInstrument(instr{3});

%% Create scan
scan = [];
ex.scan = [];

%Finds the pulses with τ in the notes
scan.address = findPulses(instr{3},'notes','τ','contains');

%Set the bounds for all pulse addresses' durations to tau start and end
for ii = 1:numel(scan.address)
   scan.bounds{ii} = [startTauDuration endTauDuration];
end

%Sets number of steps and corresponding step size
if tauNSteps ~= 0 %Priority to number of steps
   scan.nSteps = tauNSteps;
elseif tauStepSize ~= 0
   scan.stepSize = tauStepSize;
else
   error('τ n steps or step size required')
end

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










