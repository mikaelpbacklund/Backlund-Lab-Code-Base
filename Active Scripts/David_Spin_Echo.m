%Example Spin Echo using template

%% User Settings
params.RFResonanceFrequency = 2.43925;
params.piTime = 88;
params.tauStart = 200;
params.tauEnd = 2000;
params.tauStepSize = 200;
%All parameters below this are optional in that they will revert to defaults if not specified
params.tauNSteps = [];%will override step size
params.timePerDataPoint = 10;%seconds
params.collectionDuration = 800;
params.collectionBufferDuration = 1000;
params.intermissionBufferDuration = 2500;
params.repolarizationDuration = 7000;
params.extraRF =  0;
params.AOM_DAQCompensation = 400;
params.IQPreBufferDuration = 22;
params.IQPostBufferDuration = 0;
nIterations = 20;
RFAmplitude = 10;
dataType = 'counter';
timeoutDuration = 10;
forcedDelayTime = .25;
nDataPointDeviationTolerance = .01;

%% Setup

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

%Sends RF settings
ex.SRS_RF.enabled = 'on';
ex.SRS_RF.modulationEnabled = 'on';
ex.SRS_RF.modulationType = 'iq';
ex.SRS_RF.amplitude = RFAmplitude;
ex.SRS_RF.frequency = params.RFResonanceFrequency;

%Sends DAQ settings
ex.DAQ.takeData = false;
ex.DAQ.differentiateSignal = 'on';
ex.DAQ.activeDataChannel = dataType;

%Load empty parameter structure from template
[sentParams,~] = SpinEcho_template([],[]);

%Replaces values in sentParams with values in params if they aren't empty
for paramName = fieldnames(sentParams)'
   if ~isempty(params.(paramName{1}))
      sentParams.(paramName{1}) = params.(paramName{1});
   end
end

%Executes spin echo template, giving back edited pulse blaster object and information for the scan
[ex.pulseBlaster,scanInfo] = SpinEcho_template(ex.pulseBlaster,sentParams);

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

for ii = 1:nIterations

   %Prepares scan for a fresh start while keeping data from previous
   %iterations
   ex = resetScan(ex);

   iterationData = zeros([ex.scan.nSteps 1]);

   %While the odometer is not at its max value
   while ~all(ex.odometer == [ex.scan.nSteps])

      ex = takeNextDataPoint(ex,'pulse sequence');

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
          %FIX X AXIS FOR p.tauStart - (sum(IQBuffers)+(3/4)*p.piTime+p.extraRF)
          xax = ex.scan.bounds{1}(1):ex.scan.stepSize:ex.scan.bounds{1}(2);
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

