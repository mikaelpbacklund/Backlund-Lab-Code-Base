%Example Spin Echo using template

%% User Settings
scanType = 'duration';%Either frequency or duration
params.RF2Frequency = .43088;%GHz. Overwritten by scan if frequency selected
params.RF2Duration = 100;%ns. Overwritten by scan if duration selected
params.nRF2Pulses = 2;%1 for centered on pi pulse, 2 for during tau
params.RF1ResonanceFrequency = 2.43925;
params.piTime = 88;
params.tauTime = 450;
% scanStart = .4;%ns or GHz
% scanEnd = .45;%ns or GHz
% scanStepSize = .0025;%ns or GHz
scanStart = 10;%ns or GHz
scanEnd = 310;%ns or GHz
scanStepSize = 10;%ns or GHz

%All parameters below this are optional in that they will revert to defaults if not specified
optimizationAxes = {'z'};
optimizationSteps = {-2:0.25:2};
optimizationRFStatus = 'off';
timePerOptimizationPoint = .1;
timeBetweenOptimizations = 180; %s (Inf to disable)
%How much the current data would be less than the previous optimized value to force a new optimization
percentageDifferenceToForceOptimization = .5; %Inf to disable
scanNSteps = [];%will override step size
params.timePerDataPoint = 10;%seconds
params.collectionDuration = 800;
params.collectionBufferDuration = 1000;
params.intermissionBufferDuration = 2500;
params.repolarizationDuration = 7000;
params.extraRF =  0;
params.AOM_DAQCompensation = -100;
params.IQPreBufferDuration = 22;
params.IQPostBufferDuration = 0;
nIterations = 200;
SRSAmplitude = 10;
windfreakAmplitude = 29;
dataType = 'counter';
timeoutDuration = 10;
forcedDelayTime = .25;
nDataPointDeviationTolerance = .2;

%% Setup

warning('off','MATLAB:subscripting:noSubscriptsSpecified');

if ~strcmpi(scanType,'frequency') && ~strcmpi(scanType,'duration')
    error('scanType must be "frequency" or "duration"') %#ok<*UNRCH>
end

if ~exist('ex','var'),  ex = experiment; end
ex.notifications = true;

if isempty(ex.pulseBlaster)
    fprintf('Connecting to pulse blaster...\n')
   ex.pulseBlaster = pulse_blaster('pulse_blaster_DEER');
   ex.pulseBlaster = connect(ex.pulseBlaster);
   fprintf('Pulse blaster connected\n')
end
if isempty(ex.SRS_RF)
    fprintf('Connecting to SRS...\n')
   ex.SRS_RF = RF_generator('SRS_RF');
   ex.SRS_RF = connect(ex.SRS_RF);
   fprintf('SRS connected\n')
end
if isempty(ex.windfreak_RF)
    fprintf('Connecting to windfreak...\n')
   ex.windfreak_RF = RF_generator('windfreak_RF');
   ex.windfreak_RF = connect(ex.windfreak_RF);
fprintf('windfreak connected\n')
end
if isempty(ex.DAQ)
    fprintf('Connecting to DAQ...\n')
   ex.DAQ = DAQ_controller('daq_6361');
   ex.DAQ = connect(ex.DAQ);
   fprintf('DAQ connected\n')
end
if isempty(ex.PIstage)
    fprintf('Connecting to PI stage...\n')
   ex.PIstage = stage('PI_stage');
   ex.PIstage = connect(ex.PIstage);
   fprintf('PI stage connected\n')
end

%Sends SRS settings
ex.SRS_RF.enabled = 'on';
ex.SRS_RF.modulationEnabled = 'on';
ex.SRS_RF.modulationType = 'iq';
ex.SRS_RF.amplitude = SRSAmplitude;
ex.SRS_RF.frequency = params.RF1ResonanceFrequency;

%Sends windfreak settings
ex.windfreak_RF.enabled = 'on';
ex.windfreak_RF.amplitude = windfreakAmplitude;

%Sends DAQ settings
ex.DAQ.takeData = false;
ex.DAQ.differentiateSignal = 'on';
ex.DAQ.activeDataChannel = dataType;

%Changes scan info names based on frequency or duration
%Load empty parameter structure from template
if strcmpi(scanType,'frequency')
    params.frequencyStart = scanStart;
    params.frequencyEnd = scanEnd;
    params.frequencyStepSize = scanStepSize;
    params.frequencyNSteps = scanNSteps;
    [sentParams,~] = DEER_frequency_template([],[]);
else 
    params.RF2DurationStart = scanStart;
    params.RF2DurationEnd = scanEnd;
    params.RF2DurationStepSize = scanStepSize;
    params.RF2DurationNSteps = scanNSteps;
    [sentParams,~] = DEER_duration_template([],[]);
end

%Replaces values in sentParams with values in params if they aren't empty
for paramName = fieldnames(sentParams)'
   if ~isempty(params.(paramName{1}))
      sentParams.(paramName{1}) = params.(paramName{1});
   end
end

%Executes template, giving back edited pulse blaster object and information for the scan

%Changes rf2 frequency if running duration scan (constant frequency)
if strcmpi(scanType,'duration')
    [ex.pulseBlaster,scanInfo] = DEER_duration_template(ex.pulseBlaster,sentParams);
    ex.windfreak_RF.frequency = scanInfo.RF2Frequency;
else
    [ex.pulseBlaster,scanInfo] = DEER_frequency_template(ex.pulseBlaster,sentParams);
end

%Deletes any pre-existing scan
ex.scan = [];

%Adds scan to experiment based on template output
ex = addScans(ex,scanInfo);

%Adds time (in seconds) after pulse blaster has stopped running before continuing to execute code
ex.forcedCollectionPauseTime = forcedDelayTime;

%Changes tolerance from .01 default to user setting
ex.nPointsTolerance = nDataPointDeviationTolerance;

ex.maxFailedCollections = 10;

%Information for stage optimization
algorithmType = 'max value';
acquisitionType = 'pulse blaster';
optimizationSequence.axes = optimizationAxes;
optimizationSequence.steps = optimizationSteps;

%Checks if the current configuration is valid. This will give an error if not
ex = validateExperimentalConfiguration(ex,'pulse sequence');

%Sends information to command window
%First is the number of steps, second is the full time per data point, third is the number of iterations,
%fourth is a fudge factor for any additional time from various sources (heuristically found)
trueTimePerDataPoint = ex.pulseBlaster.sequenceDurations.sent.totalSeconds + ex.forcedCollectionPauseTime*1.5;
scanStartInfo(ex.scan.nSteps,trueTimePerDataPoint,nIterations,.28)

cont = checkContinue(timeoutDuration*2);
if ~cont
   return
end

%% Run scan, and collect and display data

try
%Prepares experiment to run from scratch
%[0,0] is the value that all initial values for the data will take
%Two values are used because we are storing ref and sig
ex = resetAllData(ex,[0 0]);

avgData = zeros([ex.scan.nSteps 1]);

lastOptimizationTime = datetime;
lastOptimizationValue = 9999999999999999;

for ii = 1:nIterations

   %Prepares scan for a fresh start while keeping data from previous
   %iterations
   ex = resetScan(ex);

   iterationData = zeros([ex.scan.nSteps 1]);   

   %While the odometer is not at its max value
   while ~all(ex.odometer == [ex.scan.nSteps])

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

      ex = takeNextDataPoint(ex,'pulse sequence');

      pause(params.timePerDataPoint)

      %Stores reference value of the data point if the optimization was just done
      %Used to reference later to determine if optimization should be performed
      if didOptimization
         lastOptimizationValue = ex.data.values{ex.odometer,end}(1);
      end

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
          averageAxes = axes(averageFig); %#ok<*LAXES>           
          iterationFig = figure(2);
          iterationAxes = axes(iterationFig); 
          xax = scanStart:scanStepSize:scanEnd;
          avgPlot = plot(averageAxes,xax,avgData);          
          iterationPlot = plot(iterationAxes,xax,iterationData);
          title(averageAxes,'Average')
          title(iterationAxes,'Current')
      else
          avgPlot.YData = avgData;
          iterationPlot.YData = iterationData;
      end

   end

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

