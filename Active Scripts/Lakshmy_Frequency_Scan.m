%Default ODMR script example

%% User Inputs
instrumentToScan = 'srs';%'srs' or 'wf'
scanBounds = [2.35 2.9];
scanStepSize = .005; %Step size for RF frequency
scanNotes = 'ODMR'; %Notes describing scan (will appear in titles for plots)
sequenceTimePerDataPoint = .2;%Before factoring in forced delay and other pauses
nIterations = 5;
timeoutDuration = 5;
forcedDelayTime = .125;
nDataPointDeviationTolerance = .0001;
%SRS parameters
srsAmplitude = 10;
srsFrequency = 2.425;%can be overwritten by scan
%Windfreak parameters
wfAmplitude = 29;
wfFrequency = 2.3;%can be overwritten by scan

optimizationAxes = {'z'};
optimizationSteps = {-2:0.25:2};
optimizationRFStatus = 'off';
timePerOptimizationPoint = .1;
timeBetweenOptimizations = 180; %s (Inf to disable)
%How much the current data would be less than the previous optimized value to force a new optimization
percentageDifferenceToForceOptimization = .5; %Inf to disable


%% Backend

%This warning *should* be suppressed in the DAQ code but isn't for an unknown reason. This is not related to my code but
%rather the data acquisition toolbox code which I obviously can't change
warning('off','MATLAB:subscripting:noSubscriptsSpecified');

%Creates experiment object if none exist
if ~exist('ex','var')
   ex = experiment;
end
ex.notifications = true;

%If there is no pulseBlaster object, create a new one with the config file "pulse_blaster_config"
if isempty(ex.pulseBlaster)
   ex.pulseBlaster = pulse_blaster('pulse_blaster_DEER');
   ex.pulseBlaster = connect(ex.pulseBlaster);
end

%If there is no RF_generator object, create a new one with the config file "SRS_RF"
%This is the "normal" RF generator that our lab uses, other specialty RF generators have their own configs
if isempty(ex.SRS_RF)
   ex.SRS_RF = RF_generator('SRS_RF');
   ex.SRS_RF = connect(ex.SRS_RF);
end

%Windfreak connection
if isempty(ex.windfreak_RF)
   ex.windfreak_RF = RF_generator('windfreak_RF');
   ex.windfreak_RF = connect(ex.windfreak_RF);
end

%If there is no DAQ_controller object, create a new one with the config file "NI_DAQ_config"
if isempty(ex.DAQ)
   ex.DAQ = DAQ_controller('3rd_setup_daq');
   ex.DAQ = connect(ex.DAQ);
end

%Stage connection
if isempty(ex.PIstage) || ~ex.PIstage.connected
    ex.PIstage = stage('PI_stage');
    ex.PIstage = connect(ex.PIstage);
end

%Turns RF on, disables modulation, and sets amplitude to 10 dBm
ex.SRS_RF.enabled = 'on';
ex.SRS_RF.modulationEnabled = 'off';
ex.SRS_RF.amplitude = srsAmplitude;

ex.windfreak_RF.enabled = 'on';
ex.windfreak_RF.amplitude = wfAmplitude;

%For instrument not scanned, set frequency
% switch lower(instrumentToScan)
%     case 'srs'
%         ex.windfreak_RF.frequency = wfFrequency; 
%     case 'wf'
%         ex.SRS_RF.frequency = srsFrequency; 
%     otherwise
%         error('Instrument to scan must be "wf" or "srs"')
% end

%Temporarily disables taking data, differentiates signal and reference (to get contrast), and sets data channel to
%counter
ex.DAQ.takeData = false;
ex.DAQ.differentiateSignal = 'on';
ex.DAQ.activeDataChannel = 'counter';

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

if strcmpi(instrumentToScan,'wf')
    ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','DAQ','RF2','Signal'},1e6,'Signal'); %#ok<UNRCH>
    if sequenceTimePerDataPoint < 4
        sequenceTimePerDataPoint = 4;
        warning('Sequence time per data point for a windfreak scan must be at least 4 seconds and has been changed accordingly')
    end
else
    ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','DAQ','RF','Signal'},1e6,'Signal');
end


ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'Signal'},2500,'Final buffer');

ex.pulseBlaster = calculateDuration(ex.pulseBlaster,'user');

%Changes number of loops to match desired time for each data point
ex.pulseBlaster.nTotalLoops = floor(sequenceTimePerDataPoint/ex.pulseBlaster.sequenceDurations.user.totalSeconds);

%Sends the currently saved pulse sequence to the pulse blaster instrument itself
ex.pulseBlaster = sendToInstrument(ex.pulseBlaster);

%Deletes any pre-existing scan
ex.scan = [];

scan.bounds = scanBounds; %RF frequency bounds
scan.stepSize = scanStepSize; %Step size for RF frequency
scan.parameter = 'frequency'; %Scan frequency parameter
switch lower(instrumentToScan)
    case 'wf'
        scan.identifier = ex.windfreak_RF.identifier;
    case 'srs'
        scan.identifier = ex.SRS_RF.identifier;
end
scan.notes = scanNotes; %Notes describing scan (will appear in titles for plots)

%Add the current scan
ex = addScans(ex,scan);

%Adds time (in seconds) after pulse blaster has stopped running before continuing to execute code
ex.forcedCollectionPauseTime = forcedDelayTime;

ex.maxFailedCollections = 3;

%Changes tolerance from .01 default to user setting
ex.nPointsTolerance = nDataPointDeviationTolerance;

%Checks if the current configuration is valid. This will give an error if not
ex = validateExperimentalConfiguration(ex,'pulse sequence');

algorithmType = 'max value';
acquisitionType = 'pulse blaster';
optimizationSequence.axes = optimizationAxes;
optimizationSequence.steps = optimizationSteps;

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

lastOptimizationTime = datetime;
lastOptimizationValue = 9999999999999999;

for ii = 1:nIterations
   
   %Reset current scan each iteration
   ex = resetScan(ex);

   iterationData = zeros([ex.scan.nSteps 1]);
   
   while ~all(cell2mat(ex.odometer) == [ex.scan.nSteps]) %While odometer does not match max number of steps

        timeSinceLastOptimizaiton = seconds(datetime - lastOptimizationTime);

      %If first data point, or time since last optimization is greater than set time, or difference between current
      %value and last optimized value is greater than set parameter
      if  timeSinceLastOptimizaiton > timeBetweenOptimizations || ...
            (ex.odometer ~= 0 && lastOptimizationValue*(1-percentageDifferenceToForceOptimization) > ex.data.values{ex.odometer,end}(1))
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

      if didOptimization
         lastOptimizationValue = ex.data.values{ex.odometer,end}(1);
      end

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
          % title('Average')
          averageAxes = axes(averageFig); %#ok<LAXES>
          iterationFig = figure(2);
          % title('Current Iteration')
          iterationAxes = axes(iterationFig); %#ok<LAXES>
          xax = ex.scan.bounds(1):ex.scan.stepSize:ex.scan.bounds(2);
          avgPlot = plot(averageAxes,xax,avgData);
          iterationPlot = plot(iterationAxes,xax,iterationData);
      else
          avgPlot.YData = avgData;
          iterationPlot.YData = iterationData;
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


