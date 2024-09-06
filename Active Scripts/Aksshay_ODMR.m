%Default ODMR script example

%% User Inputs
RFamplitude = -25;
scanBounds = [2.86 2.9];
scanStepSize = .0005; %Step size for RF frequency
scanNotes = 'ODMR'; %Notes describing scan (will appear in titles for plots)
sequenceTimePerDataPoint = 2;%Before factoring in forced delay and other pauses
nIterations = 25;
timeoutDuration = 10;
forcedDelayTime = .125;
nDataPointDeviationTolerance = .0001;

%% Backend

%This warning *should* be suppressed in the DAQ code but isn't for an unknown reason. This is not related to my code but
%rather the data acquisition toolbox code which I obviously can't change
warning('off','MATLAB:subscripting:noSubscriptsSpecified');

%Creates experiment object if none exist
if ~exist('ex','var')
   ex = experiment;
end

%If there is no pulseBlaster object, create a new one with the config file "pulse_blaster_config"
if isempty(ex.pulseBlaster)
   ex.pulseBlaster = pulse_blaster('PB');
   ex.pulseBlaster = connect(ex.pulseBlaster);
end

%If there is no RF_generator object, create a new one with the config file "SRS_RF"
%This is the "normal" RF generator that our lab uses, other specialty RF generators have their own configs
if isempty(ex.SRS_RF)
   ex.SRS_RF = RF_generator('SRS_RF');
   ex.SRS_RF = connect(ex.SRS_RF);
end

%If there is no DAQ_controller object, create a new one with the config file "NI_DAQ_config"
if isempty(ex.DAQ)
   ex.DAQ = DAQ_controller('NI_DAQ');
   ex.DAQ = connect(ex.DAQ);
end

%Turns RF on, disables modulation, and sets amplitude to 10 dBm
ex.SRS_RF.enabled = 'on';
ex.SRS_RF.modulationEnabled = 'off';
ex.SRS_RF.amplitude = RFamplitude;

%Temporarily disables taking data, differentiates signal and reference (to get contrast), and sets data channel to
%counter
ex.DAQ.takeData = false;
ex.DAQ.differentiateSignal = 'on';
ex.DAQ.activeDataChannel = 'analog';

%Sets loops for entire sequence to "on". Deletes previous sequence if any existed
ex.pulseBlaster.nTotalLoops = 1;%will be overwritten later, used to find time for 1 loop
ex.pulseBlaster.useTotalLoop = true;
ex.pulseBlaster = deleteSequence(ex.pulseBlaster);

%For each of the following sections:
%Clear previous information
%Set which channels should be active in the pulse blaster
%Set how long this pulse should run for
%List any notes to describe the pulse
%Add the pulse to the current sequence
clear pulseInfo 
pulseInfo.activeChannels = {};
pulseInfo.duration = 2500;
pulseInfo.notes = 'Initial buffer';
ex.pulseBlaster = addPulse(ex.pulseBlaster,pulseInfo);

%Condensed version below puts this on one line
ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','DAQ'},1e6,'Reference');

ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{},2500,'Middle buffer signal off');

ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'Signal'},2500,'Middle buffer signal on');

ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','DAQ','RF','Signal'},1e6,'Signal');

ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'Signal'},2500,'Final buffer');

%Changes number of loops to match desired time for each data point
ex.pulseBlaster.nTotalLoops = floor(sequenceTimePerDataPoint/ex.pulseBlaster.sequenceDurations.user.totalSeconds);

%Sends the currently saved pulse sequence to the pulse blaster instrument itself
ex.pulseBlaster = sendToInstrument(ex.pulseBlaster);

%Deletes any pre-existing scan
ex.scan = [];

scan.bounds = scanBounds; %RF frequency bounds
scan.stepSize = scanStepSize; %Step size for RF frequency
scan.parameter = 'frequency'; %Scan frequency parameter
scan.identifier = 'SRS RF'; %Instrument has identifier 'SRS RF' (not needed if only one RF generator is connected)
scan.notes = scanNotes; %Notes describing scan (will appear in titles for plots)

%Add the current scan
ex = addScans(ex,scan);

%Adds time (in seconds) after pulse blaster has stopped running before continuing to execute code
ex.forcedCollectionPauseTime = forcedDelayTime;

%Changes tolerance from .01 default to user setting
ex.nPointsTolerance = nDataPointDeviationTolerance;

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

%% Running Scan

%Resets current data. [0,0] is for reference and contrast counts
ex = resetAllData(ex,[0,0]);

for ii = 1:nIterations
   
   %Reset current scan each iteration
   ex = resetScan(ex);
   
   while ~all(ex.odometer == [ex.scan.nSteps]) %While odometer does not match max number of steps

      %Takes the next data point. This includes incrementing the odometer and setting the instrument to the next value
      ex = takeNextDataPoint(ex,'pulse sequence');      

      %Creates plots
      
      currentData = cellfun(@(x)x{1},ex.data.current,'UniformOutput',false);
      prevData = cellfun(@(x)x{1},ex.data.previous,'UniformOutput',false);
      newRefData = cell2mat(cellfun(@(x)x(1),currentData,'UniformOutput',false));
      prevRefData = cell2mat(cellfun(@(x)x(1),prevData,'UniformOutput',false));
      nPoints = ex.data.nPoints(:,ii)/expectedDataPoints;
      nPoints(nPoints == 0) = 1;
      plotTypes = {'average','new'};%'old' also viable
      for plotName = plotTypes
         c = findContrast(ex,[],plotName{1});
         ex = plotData(ex,c,plotName{1});
      end
%       ex = plotData(ex,nPoints,'n points');
%       ex = plotData(ex,ex.data.failedPoints,'n failed points');
      ex = plotData(ex,newRefData,'new reference');
%       ex = plotData(ex,prevRefData,'previous reference');
   end

   %Between each iteration, check for user input whether to continue scan
   %5 second timeout
   if ii ~= nIterations
       cont = checkContinue(timeoutDuration);
       if ~cont
           break
       end
   end
end
stop(ex.DAQ.handshake)
fprintf('Scan complete\n')

