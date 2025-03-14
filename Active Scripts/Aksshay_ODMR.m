%Default ODMR script example

%% User Inputs
%General
RFamplitude = 10;
scanBounds = [2.02 2.06];
scanStepSize = .001; %Step size for RF frequency
scanNotes = 'hyperfine ODMR'; %Notes describing scan (will appear in titles for plots)
sequenceTimePerDataPoint = 0.100;%Before factoring in forced delay and other pauses
nIterations = 1; %Number of iterations of scan to perform
timeoutDuration = 10; %How long before auto-continue occurs
forcedDelayTime = .125; %Time to force pause before (1/2) and after (full) collecting data
nDataPointDeviationTolerance = .0001;%How precies measurement is. Lower number means more exacting values, could lead to repeated failures
baselineSubtraction = .095;%Amount to subtract from both reference and signal collected

%Plotting
plotAverageContrast = true;
plotCurrentContrast = true;
plotAverageReference = true;
plotCurrentReference = true;

%Stage optimization
optimizationEnabled = false; %Set to false to disable stage optimization
optimizationAxes = {'z'}; %The axes which will be optimized over
optimizationSteps = {-2:0.25:2}; %Locations the stage will move relative to current location
optimizationRFStatus = 'off'; %'off', 'on', or 'con' 
timePerOpimizationPoint = .1; %Duration of each data point during optimization
timeBetweenOptimizations = 180; %Seconds between optimizations (0 or Inf to disable)
percentageForcedOptimization = .75; %see below (0 to disable)

%percentageForcedOptimization is a more complex way of deciding when to do an optimization.
%After every optimization, the reference value of the next data point is recorded. After every data point, if the
%reference value is lower than X percent of that post-optimization value, a new optimization will be performed. This
%means setting the value to 1 corresponds to running an optimization if the value obtained is lower at all than the
%post-optimization value, .75 means running optimization if less than 3/4 post-optimization value etc.

%% Backend

%This warning *should* be suppressed in the DAQ code but isn't for an unknown reason. This is not related to my code but
%rather the data acquisition toolbox code which I obviously can't change
warning('off','MATLAB:subscripting:noSubscriptsSpecified');

%Creates experiment object if none exist
if ~exist('ex','var')
   ex = experiment;
end

%If there is no pulseBlaster object, create a new one with the config file "pulse_blaster_default"
if isempty(ex.pulseBlaster)
   fprintf('Connecting to pulse blaster...\n')
   ex.pulseBlaster = pulse_blaster('pulse_blaster_default');
   ex.pulseBlaster = connect(ex.pulseBlaster);
   fprintf('Pulse blaster connected\n')
end

%If there is no RF_generator object, create a new one with the config file "SRS_RF"
%This is the "normal" RF generator that our lab uses, other specialty RF generators have their own configs
if isempty(ex.SRS_RF)
   fprintf('Connecting to SRS...\n')
   ex.SRS_RF = RF_generator('SRS_RF');
   ex.SRS_RF = connect(ex.SRS_RF);
   fprintf('SRS connected\n')
end

%If there is no DAQ_controller object, create a new one with the config file "daq_6361"
if isempty(ex.DAQ)
   fprintf('Connecting to DAQ...\n')
   ex.DAQ = DAQ_controller('daq_6361');
   ex.DAQ = connect(ex.DAQ);
   fprintf('DAQ connected\n')
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

%Gets duration of user sequence in order to change number of loops to match desired time for each data point
ex.pulseBlaster = calculateDuration(ex.pulseBlaster,'user');
ex.pulseBlaster.nTotalLoops = floor(sequenceTimePerDataPoint/ex.pulseBlaster.sequenceDurations.user.totalSeconds);

%Sends the currently saved pulse sequence to the pulse blaster instrument itself
ex.pulseBlaster = sendToInstrument(ex.pulseBlaster);

%Deletes any pre-existing scan
ex.scan = [];

scan.bounds = scanBounds; %RF frequency bounds
scan.stepSize = scanStepSize; %Step size for RF frequency
scan.parameter = 'frequency'; %Scan frequency parameter
scan.identifier = ex.SRS_RF.identifier; %Instrument has identifier 'SRS RF' (not needed if only one RF generator is connected)
scan.notes = scanNotes; %Notes describing scan (will appear in titles for plots)

%Add the current scan
ex = addScans(ex,scan);

%Adds time (in seconds) after pulse blaster has stopped running before continuing to execute code
ex.forcedCollectionPauseTime = forcedDelayTime;

%Number of failed collections before giving error
ex.maxFailedCollections = 5;

%Changes tolerance from .01 default to user setting
ex.nPointsTolerance = nDataPointDeviationTolerance;

%Information for stage optimization
ex.optimizationInfo.algorithmType = 'max value';
ex.optimizationInfo.acquisitionType = 'pulse blaster';
ex.optimizationInfo.stageAxes = optimizationAxes;
ex.optimizationInfo.steps = optimizationSteps;
ex.optimizationInfo.timePerPoint = timePerOpimizationPoint;
ex.optimizationInfo.timeBetweenOptimizations = timeBetweenOptimizations;
if isempty(timeBetweenOptimizations) || timeBetweenOptimizations == 0 || timeBetweenOptimizations == Inf
   ex.optimizationInfo.useTimer = false;
else
   ex.optimizationInfo.useTimer = true;
end
ex.optimizationInfo.percentageToForceOptimization = percentageForcedOptimization;
if isempty(percentageForcedOptimization) || percentageForcedOptimization == 0
   ex.optimizationInfo.usePercentageDifference = false;
else
   ex.optimizationInfo.usePercentageDifference = true;
end
ex.optimizationInfo.needNewValue = true;
ex.optimizationInfo.lastOptimizationTime = [];
ex.optimizationInfo.postOptimizationValue = 0;
ex.optimizationInfo.rfStatus = optimizationRFStatus;

%Checks if the current configuration is valid. This will give an error if not
%ex = validateExperimentalConfiguration(ex,'pulse sequence');

%Sends information to command window
scanStartInfo(ex.scan.nSteps,ex.pulseBlaster.sequenceDurations.sent.totalSeconds + ex.forcedCollectionPauseTime*1.5,nIterations,.28)

%Asks for user input on whether to continue
cont = checkContinue(timeoutDuration*2);
if ~cont
    return
end

%% Running Scan
try
%Resets current data. [0,0] is for reference and signal counts
ex = resetAllData(ex,[0,0]);

averageData = zeros([ex.scan.nSteps 1]);

for ii = 1:nIterations
   
   %Reset current scan each iteration
   ex = resetScan(ex);

   iterationData = zeros([ex.scan.nSteps 1]);
   
   while ~all(cell2mat(ex.odometer) == [ex.scan.nSteps]) %While odometer does not match max number of steps

      %Checks if stage optimization should be done, then does it if so
      if optimizationEnabled && checkOptimization(ex),  ex = stageOptimization(ex);   end

      %Takes the next data point. This includes incrementing the odometer and setting the instrument to the next value
      ex = takeNextDataPoint(ex,'pulse sequence');

      %Subtract baseline from ref and sig
      ex = subtractBaseline(ex,baselineSubtraction);

      %Create matrix where first row is ref, second is sig, and columns indicate iteration
      data = createDataMatrixWithIterations(ex);
      %Find average data across iterations by taking mean across all columns
      averageData = mean(data,2);
      %Current data is last column
      currentData = data(:,end);

      %Find and plot reference or contrast
      if plotAverageContrast
         averageContrast = (averageData(1) - averageData(2)) / averageData(1);
         ex = plotData(ex,averageContrast,'Average Contrast');
      end
      if plotCurrentContrast
         currentContrast = (currentData(1) - currentData(2)) / currentData(1);
         ex = plotData(ex,currentContrast,'Current Contrast');
      end
      if plotAverageReference
         ex = plotData(ex,averageData(1),'Average Reference'); %#ok<*UNRCH>
      end
      if plotCurrentReference
         ex = plotData(ex,currentData(1),'Current Reference');
      end

      %If a new post-optimization value is needed, record current data
      if ex.optimizationInfo.needNewValue
         ex.optimizationInfo.postOptimizationValue = currentData;
         ex.optimizationInfo.needNewValue = false;
      end
      
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
fprintf('Scan complete\n')
catch ME   
    stop(ex.DAQ.handshake)
    rethrow(ME)
end
stop(ex.DAQ.handshake)


