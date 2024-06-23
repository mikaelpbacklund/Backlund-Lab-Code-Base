%Spin Echo

piTime = 60;
aomCompensation = -100;
startTauDuration = 100;
endTauDuration = 1100;
tauNSteps = 11;

%% Load instruments

%Creates objects for necessary instrument and connects to them using
%previously generated config files
srs = RF_generator;
srs = connect(srs,'RF_generator_config');
srsRF = toggle(srsRF,'on');
srsRF = modulationToggle(srsRF,'on');
srsRF = setAmplitude(srsRF,10);

nidaq = DAQ_controller;
nidaq = connect(nidaq,'NI_DAQ_config'); 
nidaq = setSignalDifferentiation(nidaq,'on');
nidaq = setDataChannel(nidaq,'counter');

pb = pulse_blaster;
pb = connect(pb,'pulse_blaster_config');

pistage = stage;
pistage = connect(pistage,'PI_stage_config');

ex = experiment;

%Groups instruments and saves the names of each
instrumentCells = {srs,nidaq,pb,pistage};
ex = getInstrumentNames(ex,instrumentCells);

%% Create pulse sequence

%pb shorthand used for simplicity and brevity. It will be re-synced with
%instrumentCells later
pb.nTotalLoops = 1000;

n = 1;
pulseSequence{n}.activeChannels = {};
pulseSequence{n}.duration = 2000;
pulseSequence{n}.notes = 'Initial buffer';

n = n+1;%2
pulseSequence{n}.activeChannels = {'RF'};
pulseSequence{n}.duration = piTime/2;
pulseSequence{n}.notes = 'Starting π/2 x';

n = n+1;%3
pulseSequence{n}.activeChannels = {};
pulseSequence{n}.duration = 99;%Scanned
pulseSequence{n}.notes = 'τ';

n = n+1;%4
pulseSequence{n}.activeChannels = {'RF','I'};
pulseSequence{n}.duration = piTime;
pulseSequence{n}.notes = 'Middle π y';

n = n+1;%5
pulseSequence{n}.activeChannels = {};
pulseSequence{n}.duration = 99;%Scanned
pulseSequence{n}.notes = 'τ';

n = n+1;%6
pulseSequence{n}.activeChannels = {'RF','I','Q'};
pulseSequence{n}.duration = piTime/2;
pulseSequence{n}.notes = 'Ending π/2 -x';

n = n+1;%7
pulseSequence{n}.activeChannels = {};
pulseSequence{n}.duration = 2000;
pulseSequence{n}.notes = 'Data collection buffer';

n = n+1;%8
if aomCompensation > 0
   pulseSequence{n}.activeChannels = {'AOM'};
else
   pulseSequence{n}.activeChannels = {'DAQ'};
end
pulseSequence{n}.duration = abs(aomCompensation);
pulseSequence{n}.notes = 'AOM/DAQ delay compensation';


n = n+1;%9
pulseSequence{n}.activeChannels = {'AOM','Data'};
pulseSequence{n}.duration = 1000;
pulseSequence{n}.notes = 'Reference data collection';

n = n+1;%10
pulseSequence{n}.activeChannels = {'AOM'};
pulseSequence{n}.duration = 7000;
pulseSequence{n}.notes = 'Repolarization';

n = n+1;%11
pulseSequence{n}.activeChannels = {'Signal'};
pulseSequence{n}.duration = 2000;
pulseSequence{n}.notes = 'Buffer between signal and reference';

n = n+1;%12
pulseSequence{n}.activeChannels = {'RF','Signal'};
pulseSequence{n}.duration = piTime/2;
pulseSequence{n}.notes = 'Starting π/2 x';

n = n+1;%13
pulseSequence{n}.activeChannels = {'Signal'};
pulseSequence{n}.duration = 99;%Scanned
pulseSequence{n}.notes = 'τ';

n = n+1;%14
pulseSequence{n}.activeChannels = {'RF','I','Signal'};
pulseSequence{n}.duration = piTime;
pulseSequence{n}.notes = 'Middle π y';

n = n+1;%15
pulseSequence{n}.activeChannels = {'Signal'};
pulseSequence{n}.duration = 99;%Scanned
pulseSequence{n}.notes = 'τ';

n = n+1;%16
pulseSequence{n}.activeChannels = {'RF'};
pulseSequence{n}.duration = piTime/2;
pulseSequence{n}.notes = 'Ending π/2 x';

n = n+1;%17
pulseSequence{n}.activeChannels = {'Signal'};
pulseSequence{n}.duration = 2000;
pulseSequence{n}.notes = 'Data collection buffer';

n = n+1;%18
if aomCompensation > 0
   pulseSequence{n}.activeChannels = {'AOM','Signal'};
else
   pulseSequence{n}.activeChannels = {'DAQ','Signal'};
end
pulseSequence{n}.duration = abs(aomCompensation);
pulseSequence{n}.notes = 'AOM/DAQ delay compensation';


n = n+1;%19
pulseSequence{n}.activeChannels = {'AOM','Data','Signal'};
pulseSequence{n}.duration = 1000;
pulseSequence{n}.notes = 'Signal data collection';

n = n+1;%20
pulseSequence{n}.activeChannels = {'AOM','Signal'};
pulseSequence{n}.duration = 7000;
pulseSequence{n}.notes = 'Repolarization';

for ii = 1:numel(pulseSequence)
   pb = addPulse(pb,pulseSequence{ii});
end

pb = sendToInstrument(pb);

%Re-sync instrumentCells with shorthand
instrumentCells{strcmpi('pulse_blaster',h.instrumentNames)} = pb;

%% Stage optimization parameters

%Type of optimization*
optSequence.consecutive = true;

%Assignment of optimization sequence
optSequence.axes = {'x','y','z'};
optSequence.steps = {-1:.1:1,-1:.1:1,-2:.2:2};

%Alternate way to do axes/steps
n = 1;
optSequence.axes{n} = 'x';
optSequence.steps{n} = -1 : 0.1 : 1;
n = 2;
optSequence.axes{n} = 'y';
optSequence.steps{n} = -1 : 0.1 : 1;
n = 3;
optSequence.axes{n} = 'z';
optSequence.steps{n} = -2 : 0.2 : 2;

%% Create scan

%Finds the pulses with τ in the notes
scan.address = findPulses(pb,'notes','τ','contains');

%Set the bounds for all pulse addresses' durations to tau start and end
for ii = 1:numel(scan.address)
   scan.bounds{ii} = [startTauDuration endTauDuration];
end

%Give remaining information about the scan
scan.nSteps = tauNSteps;
scan.parameter = 'duration';
scan.instrument = 'pulse_blaster';
scan.notes = 'Spin Echo';

ex = addScans(ex,scan);

%% Run scan, and collect and display data

nIterations = 4;

%Prepares experiment to run from scratch
ex = resetAllData(ex);

for ii = 1:nIterations
   
   %Prepares scan for a fresh start while keeping data from previous
   %iterations
   [ex,instrumentCells] = resetScan(ex,instrumentCells);
   
   %Runs initial optimization. Optimization goes to highest value based on
   %output of pulse sequence; the stage movements are determined by
   %optSequence and RF is turned off
   [ex,instrumentCells] = stageOptimization(ex,instrumentCells,'max value','pulse sequence',optSequence,'off');
   lastOptTime = datetime;
   
   %While the odometer is not at its max value
   while all(ex.odometer == [ex.scan.nSteps])
      
      if datetime-lastOptTime > duration(0,5,0)%Check if last optimization was over 5 mins ago
         %Runs stage optimization
         [ex,instrumentCells] = stageOptimization(ex,instrumentCells,'max value','pulse sequence',optSequence,'off');
         
         %Sets new time for last optimization
         lastOptTime = datetime;
      end
      
      [ex,instrumentCells] = takeNextDataPoint(ex,instrumentCells,'pulse sequence');
      
      %Display the data for the current iteration, the previous iterations,
      %and the average of all
      ex = displayData(ex,'current');
      ex = displayData(ex,'previous');
      ex = displayData(ex,'average');
   end
   
end










