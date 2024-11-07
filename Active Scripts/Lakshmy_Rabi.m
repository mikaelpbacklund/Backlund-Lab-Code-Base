%Runs a simple Rabi sequence with no τ compensation or stage optimization

%Highly recommended to use a "time per data point" of at least 3 seconds
%Lower than this is sensitive to jitters in number of points collected,
%resulting in failed and/or erroneous points

%% User Inputs
scanBounds = [10 310];%ns
scanStepSize = 10;
scanNotes = 'Rabi'; %Notes describing scan (will appear in titles for plots)
nIterations = 3;
RFFrequency = 2.425;
sequenceTimePerDataPoint = 5;%Before factoring in forced delay and other pauses
timeoutDuration = 5;
forcedDelayTime = .2;
%Offset for AOM pulses relative to the DAQ in particular
%Positive for AOM pulse needs to be on first, negative for DAQ on first
aomCompensation = 300;
RFReduction = 0;

%Lesser used settings
RFAmplitude = 10;
dataType = 'counter';
scanNSteps = [];%Will override step size if set
nDataPointDeviationTolerance = .01;
collectionDuration = (1/1.25)*1000;
collectionBufferDuration = 1000;
ex.maxFailedCollections = 5;

optimizationAxes = {'z'};
optimizationSteps = {-2:0.25:2};
optimizationRFStatus = 'off';
timePerOptimizationPoint = .1;
timeBetweenOptimizations = 180; %s (Inf to disable)
%How much the current data would be less than the previous optimized value to force a new optimization
percentageDifferenceToForceOptimization = .5; %Inf to disable

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
if isempty(ex.PIstage)
    fprintf('Connecting to PI stage...\n')
   ex.PIstage = stage('PI_stage');
   ex.PIstage = connect(ex.PIstage);
   fprintf('PI stage connected\n')
end

%Sends RF settings
ex.SRS_RF.enabled = 'on';
ex.SRS_RF.modulationEnabled = 'off';
ex.SRS_RF.amplitude = RFAmplitude;
ex.SRS_RF.frequency = RFFrequency;

%Sends DAQ settings
ex.DAQ.takeData = false;
ex.DAQ.differentiateSignal = 'on';
ex.DAQ.activeDataChannel = dataType;

%% Use template to create sequence and scan

%Load empty parameter structure from template
[parameters,~] = Rabi_template([],[]);

%Set parameters
%Leaves intermissionBufferDuration, collectionDuration, repolarizationDuration, and collectionBufferDuration as default
parameters.RFResonanceFrequency = RFFrequency;
parameters.tauStart = scanBounds(1);
parameters.tauEnd = scanBounds(2);
parameters.timePerDataPoint = sequenceTimePerDataPoint;
parameters.AOM_DAQCompensation = aomCompensation;
parameters.collectionBufferDuration = collectionBufferDuration;
parameters.collectionDuration = collectionDuration;
if ~isempty(scanNSteps) %Use number of steps if set otherwise use step size
   parameters.tauNSteps = scanNSteps;
else
   parameters.tauStepSize = scanStepSize;
end
parameters.RFReduction = RFReduction;

%Sends parameters to template
%Creates and sends pulse sequence to pulse blaster
%Gets scan information
[ex.pulseBlaster,scanInfo] = Rabi_template(ex.pulseBlaster,parameters);

%Deletes any pre-existing scan
ex.scan = [];

%Adds scan to experiment based on template output
ex = addScans(ex,scanInfo);

%Adds time (in seconds) after pulse blaster has stopped running before continuing to execute code
ex.forcedCollectionPauseTime = forcedDelayTime;

%Changes tolerance from .01 default to user setting
ex.nPointsTolerance = nDataPointDeviationTolerance;

ex.maxFailedCollections = 10;

%Checks if the current configuration is valid. This will give an error if not
ex = validateExperimentalConfiguration(ex,'pulse sequence');

%Sends information to command window
scanStartInfo(ex.scan.nSteps,ex.pulseBlaster.sequenceDurations.sent.totalSeconds + ex.forcedCollectionPauseTime*1.5,nIterations,.28)

algorithmType = 'max value';
acquisitionType = 'pulse blaster';
optimizationSequence.axes = optimizationAxes;
optimizationSequence.steps = optimizationSteps;

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

      if didOptimization
         lastOptimizationValue = ex.data.values{ex.odometer,end}(1);
      end

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
%           if exist("nPointsFig",'var') && ishandle(nPointsFig)
%             close(nPointsFig)
%           end
          averageFig = figure(1);
          averageAxes = axes(averageFig); %#ok<*LAXES> 
          iterationFig = figure(2);
          iterationAxes = axes(iterationFig); 
%           nPointsFig = figure(3);
%           nPointsAxes = axes(nPointsFig); 
          xax = ex.scan.bounds{1}(1):ex.scan.stepSize:ex.scan.bounds{1}(2);
          avgPlot = plot(averageAxes,xax,avgData);
          iterationPlot = plot(iterationAxes,xax,iterationData);
%           nPointsPlot = plot(nPointsAxes,xax,ex.data.nPoints);
      else
          avgPlot.YData = avgData;
          iterationPlot.YData = iterationData;
%           nPointsPlot.YData = ex.data.nPoints(:,ii);
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
