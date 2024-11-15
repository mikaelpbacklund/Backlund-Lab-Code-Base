%Default ODMR script example

%% User Inputs
RFamplitude = 10;
scanBounds = [2.7 3];
scanStepSize = .005; %Step size for RF frequency
scanNotes = 'ODMR'; %Notes describing scan (will appear in titles for plots)
sequenceTimePerDataPoint = .5;%Before factoring in forced delay and other pauses
nIterations = 1; %Number of iterations of scan to perform
timeoutDuration = 10; %How long before auto-continue occurs
forcedDelayTime = .125; %Time to force pause before (1/2) and after (full) collecting data
nDataPointDeviationTolerance = .0001;%How precies measurement is. Lower number means more exacting values, could lead to repeated failures
baselineSubtraction = 0;%Amount to subtract from both reference and signal collected

%Stage optimization
optimizationEnabled = true; %Set to false to disable stage optimization
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
ex.optimizationInfo.useTimer = true;
ex.optimizationInfo.percentageToForceOptimization = percentageForcedOptimization;
ex.optimizationInfo.usePercentageDifference = true;
ex.optimizationInfo.needNewValue = true;
ex.optimizationInfo.lastOptimizationTime = [];
ex.optimizationInfo.lastOptimizationValue = [];

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
try
%Resets current data. [0,0] is for reference and signal counts
ex = resetAllData(ex,[0,0]);

avgData = zeros([ex.scan.nSteps 1]);

for ii = 1:nIterations
   
   %Reset current scan each iteration
   ex = resetScan(ex);

   iterationData = zeros([ex.scan.nSteps 1]);
   
   while ~all(cell2mat(ex.odometer) == [ex.scan.nSteps]) %While odometer does not match max number of steps

      %Checks if stage optimization should be done, then does it if so
      if checkOptimization(ex),  ex = stageOptimization(ex);   end

      odometerCell = num2cell(ex.odometer);

      timeSinceLastOptimizaiton = seconds(datetime - lastOptimizationTime);

      %If first data point, or time since last optimization is greater than set time, or difference between current
      %value and last optimized value is greater than set parameter
      if  ii == 1 || timeSinceLastOptimizaiton > timeBetweenOptimizations || ...
            (ex.odometer ~= 0 && lastOptimizationValue*percentageForcedOptimization > ex.data.values{ex.odometer,end}(1))
         lastOptimizationTime = datetime;
         fprintf('Beginning stage optimization (%.1f seconds since last optimization)\n',timeSinceLastOptimizaiton)
         [ex,optVal,optLoc] = stageOptimization(ex,algorithmType,acquisitionType,optimizationSequence,optimizationRFStatus,[],timePerOptimizationPoint);
         fprintf('Stage optimization finished, max value %g at location %.1f\n',optVal,optLoc)
         didOptimization = true;
         pause(numel(optimizationSequence.steps{1})*timePerOptimizationPoint)
      else
         didOptimization = false;
      end

      %Takes the next data point. This includes incrementing the odometer and setting the instrument to the next value
      ex = takeNextDataPoint(ex,'pulse sequence');

      con = zeros(1,ex.scan.nSteps);

      %The problem is that the odometer is 1 but the data point is 2?

      currentData = mean(createDataMatrixWithIterations(ex,ex.odometer),2);
      currentData = (currentData(1)-currentData(2))/currentData(1);
      avgData(ex.odometer) = currentData;
      currentData = ex.data.values{ex.odometer,end};
      currentData = (currentData(1)-currentData(2))/currentData(1);
      iterationData(ex.odometer) = currentData;

      if ~exist("averageFig",'var') || ~ishandle(averageAxes) || (ex.odometer == 1 && ii == 1)
          %Bad usage of this just to get it going. Should be replacing individual data points
          %Only works for 1D
          if exist("averageFig",'var') && ishandle(averageFig)
            close(averageFig)
          end
          if exist("iterationFig",'var') && ishandle(iterationFig)
            close(iterationFig)
          end
          averageFig = figure(1);
          averageAxes = axes(averageFig); %#ok<LAXES>
          iterationFig = figure(2);
          iterationAxes = axes(iterationFig); %#ok<LAXES>
          xax = ex.scan.bounds(1):ex.scan.stepSize:ex.scan.bounds(2);
          avgPlot = plot(averageAxes,xax,avgData);
          iterationPlot = plot(iterationAxes,xax,iterationData);
      else
          avgPlot.YData = avgData;
          iterationPlot.YData = iterationData;
      end

      %Stores reference value of the data point if the optimization was just done
      %Used to reference later to determine if optimization should be performed
      if didOptimization
         lastOptimizationValue = ex.data.values{ex.odometer,end}(1);
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


