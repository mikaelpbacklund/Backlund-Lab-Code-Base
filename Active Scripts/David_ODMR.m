%% User Inputs
RFamplitude = 10;
scanBounds = [2.76 3.0];
scanStepSize = .005; %Step size for RF frequency
scanNotes = 'ODMR'; %Notes describing scan (will appear in titles for plots)
sequenceTimePerDataPoint = 1;%Before factoring in forced delay and other pauses
nIterations = 10;
timeoutDuration = 5;
forcedDelayTime = .125;
nDataPointDeviationTolerance = .00015;
useStageOptimization = false;%Not usable yet
dataType = 'analog';
baselineSubtraction = .13;

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
   fprintf('Connecting to pulse blaster...\n')
   ex.pulseBlaster = pulse_blaster('pulse_blaster_DEER');
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

%If there is no DAQ_controller object, create a new one with the config file "NI_DAQ_config"
if isempty(ex.DAQ)
   fprintf('Connecting to DAQ...\n')
   ex.DAQ = DAQ_controller('daq_6361');
   ex.DAQ = connect(ex.DAQ);
   fprintf('DAQ connected\n')
end

if isempty(ex.PIstage) && useStageOptimization
   ex.PIstage = stage('PI_stage');
   ex.PIstage = connect(ex.PIstage);
end

%Turns RF on, disables modulation, and sets amplitude to 10 dBm
ex.SRS_RF.enabled = 'on';
ex.SRS_RF.modulationEnabled = 'off';
ex.SRS_RF.amplitude = RFamplitude;

%Temporarily disables taking data, differentiates signal and reference (to get contrast), and sets data channel to
%counter
ex.DAQ.takeData = false;
ex.DAQ.differentiateSignal = 'on';
ex.DAQ.activeDataChannel = dataType;

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
scan.identifier = 'SRS RF'; %Instrument has identifier 'SRS RF' (not needed if only one RF generator is connected)
scan.notes = scanNotes; %Notes describing scan (will appear in titles for plots)

%Add the current scan
ex = addScans(ex,scan);

%Adds time (in seconds) after pulse blaster has stopped running before continuing to execute code
ex.forcedCollectionPauseTime = forcedDelayTime;

ex.maxFailedCollections = 10;

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
try
%Resets current data. [0,0] is for reference and contrast counts
ex = resetAllData(ex,[0,0]);

avgData = zeros([ex.scan.nSteps 1]);

recordedTime = cell(1,nIterations+1);
recordedTime{1} = datetime;

for ii = 1:nIterations
   
   %Reset current scan each iteration
   ex = resetScan(ex);

   iterationData = zeros([ex.scan.nSteps 1]);
   
   while ~all(cell2mat(ex.odometer) == [ex.scan.nSteps]) %While odometer does not match max number of steps

      %Takes the next data point. This includes incrementing the odometer and setting the instrument to the next value
      ex = takeNextDataPoint(ex,'pulse sequence');      

      odoCell = num2cell(ex.odometer);
      ex.data.values{odoCell{:},ex.data.iteration(odoCell{:})} = ex.data.values{odoCell{:},ex.data.iteration(odoCell{:})} - baselineSubtraction;

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
      

      %Creates plots
%       plotTypes = {'average','new'};%'old' also viable
%       for plotName = plotTypes
%          c = findContrast(ex,[],plotName{1});
%          ex = plotData(ex,c,plotName{1});
%       end
%       currentData = cellfun(@(x)x{1},ex.data.current,'UniformOutput',false);
%       prevData = cellfun(@(x)x{1},ex.data.previous,'UniformOutput',false);
%       refData = cell2mat(cellfun(@(x)x(1),currentData,'UniformOutput',false));
% %       ex = plotData(ex,refData,'new reference');
%       nPoints = ex.data.nPoints(:,ii)/expectedDataPoints;
%       nPoints(nPoints == 0) = 1;
%       ex = plotData(ex,nPoints,'n points');
%       ex = plotData(ex,ex.data.failedPoints,'n failed points');
% %       refData = cell2mat(cellfun(@(x)x(1),prevData,'UniformOutput',false));
% %       ex = plotData(ex,refData,'previous reference');
   end

   recordedTime{ii+1} = datetime;

   %Between each iteration, check for user input whether to continue scan
   %5 second timeout
   if ii ~= nIterations
       fprintf('Finished iteration %d\n',ii)
       fprintf('Number of failed points: %d\n',sum(ex.data.failedPoints(:,ii)))
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


