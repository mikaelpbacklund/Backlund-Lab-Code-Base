%Runs a simple Rabi sequence with no τ compensation or stage optimization

%% User Inputs
scanBounds = [10 250];%ns
scanStepSize = 4; 
scanNotes = 'Rabi'; %Notes describing scan (will appear in titles for plots)
nIterations = 5;
RFFrequency = 2.26;
%Offset for AOM pulses relative to the DAQ in particular
%Positive for AOM pulse needs to be on first, negative for DAQ on first
aomCompensation = 400; 

sequenceTimePerDataPoint = 3;%Before factoring in forced delay and other pauses
timeoutDuration = 10;
forcedDelayTime = .125;

%Lesser used settings
RFAmplitude = 10;
dataType = 'analog';
scanNSteps = [];%Will override step size if set

%% Loading Instruments
%See ODMR example script for instrument loading information
warning('off','MATLAB:subscripting:noSubscriptsSpecified');

if ~exist('ex','var'),  ex = experiment; end

if isempty(ex.pulseBlaster)
   ex.pulseBlaster = pulse_blaster('PB');
   ex.pulseBlaster = connect(ex.pulseBlaster);
end
if isempty(ex.SRS_RF)
   ex.SRS_RF = RF_generator('SRS_RF');
   ex.SRS_RF = connect(ex.SRS_RF);
end
if isempty(ex.DAQ)
   ex.DAQ = DAQ_controller('NI_DAQ');
   ex.DAQ = connect(ex.DAQ);
end

ex.SRS_RF.enabled = 'on';
ex.SRS_RF.modulationEnabled = 'off';
ex.SRS_RF.amplitude = RFAmplitude;

ex.DAQ.takeData = false;
ex.DAQ.differentiateSignal = 'on';
ex.DAQ.activeDataChannel = dataType;

%% Create pulse sequence

ex.pulseBlaster.nTotalLoops = 1;%will be overwritten later, used to find time for 1 loop
ex.pulseBlaster.useTotalLoop = true;
ex.pulseBlaster = deleteSequence(ex.pulseBlaster);

%Adds pulse to sequence with given parameters (active channels, duration, and notes)
ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{},2500,'Initial buffer');

ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{},99,'τ no-RF time');

ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{},2000,'Data collection buffer');

if aomCompensation > 0
   activeChannels = {'AOM'};
else
   activeChannels = {'DAQ'};
end
ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,activeChannels,abs(aomCompensation),'AOM/DAQ delay compensation');

ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','Data'},1000,'Reference data collection');

ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM'},7000,'Repolarization');

ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'Signal'},2500,'Middle buffer');

ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'Signal','RF'},99,'τ RF time');

ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'Signal'},2000,'Data collection buffer');

if aomCompensation > 0
   activeChannels = {'AOM','Signal'};
else
   activeChannels = {'DAQ','Signal'};
end
ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,activeChannels,abs(aomCompensation),'AOM/DAQ delay compensation');

ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','Data','Signal'},1000,'Signal data collection');

ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','Signal'},7000,'Repolarization');

%Changes number of loops to match desired time for each data point
ex.pulseBlaster.nTotalLoops = sequenceTimePerDataPoint/ex.pulseBlaster.sequenceDurations.user.totalSeconds;

ex.pulseBlaster = sendToInstrument(ex.pulseBlaster);

fprintf('Pulse sequence %g s\n',ex.pulseBlaster.sentSequenceDuration/1e9)

%% Create scan
scan = [];
ex.scan = [];

ex.forcedCollectionPauseTime = .05;

%Finds the pulses with τ in the notes
scan.address = findPulses(ex.pulseBlaster,'notes','τ','contains');

%Set the bounds for all pulse addresses' durations to tau start and end
for ii = 1:numel(scan.address)
   scan.bounds{ii} = scanBounds;
end

%Sets number of steps and corresponding step size
if ~isempty(scanNSteps) %Priority to number of steps
   scan.nSteps = tauNSteps;
else
   scan.stepSize = tauStepSize;
end

%Give remaining information about the scan
scan.parameter = 'duration'; %Scan frequency parameter
scan.identifier = 'pb'; %Instrument has identifier 'SRS RF' (not needed if only one RF generator is connected)
scan.notes = scanNotes; %Notes describing scan (will appear in titles for plots)

ex = addScans(ex,scan);

%Adds time (in seconds) after pulse blaster has stopped running before continuing to execute code
ex.forcedCollectionPauseTime = forcedDelayTime;

%Checks if the current configuration is valid. This will give an error if not
ex = validateExperimentalConfiguration(ex,'pulse sequence');

%Sends information to command window
scanStartInfo(ex.scan.nSteps,ex.pulseBlaster.sequenceDurations.sent.totalSeconds + ex.forcedCollectionPauseTime*1.5,nIterations,.28)

cont = checkContinue(timeoutDuration*2);
if ~cont
    return
end

expectedDataPoints = ex.pulseBlaster.sequenceDurations.sent.dataNanoseconds;
expectedDataPoints = (expectedDataPoints/1e9) * ex.DAQ.sampleRate;

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

      %Plot the average and new contrast for each data point
      plotTypes = {'average','new'};%'old' also viable
      for plotName = plotTypes
         c = findContrast(ex,[],plotName{1});
         ex = plotData(ex,c,plotName{1});
      end      
   end

   if ii ~= nIterations
      cont = checkContinue(timeoutDuration);
      if ~cont
          break
      end
  end
   
end

%Stops continuous collection from DAQ
stop(instr{2}.handshake)

fprintf('Scan complete\n')








