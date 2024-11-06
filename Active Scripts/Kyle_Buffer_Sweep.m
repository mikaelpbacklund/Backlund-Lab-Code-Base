%Runs a simple Rabi sequence with no τ compensation or stage optimization

%Highly recommended to use a "time per data point" of at least 3 seconds
%Lower than this is sensitive to jitters in number of points collected,
%resulting in failed and/or erroneous points

%% User Inputs
myDurationSetting = 120;
scanBounds = [10 1000];%ns
scanNotes = 'Rabi'; %Notes describing scan (will appear in titles for plots)
scanNSteps = 100;%Will override step size if set
nIterations = 1;
RFFrequency = 2.87;
sequenceTimePerDataPoint = 4;%seconds before factoring in forced delay and other pauses
timeoutDuration = 10;
forcedDelayTime = .2;
%Offset for AOM pulses relative to the DAQ in particular
%Positive for AOM pulse needs to be on first, negative for DAQ on first
aomCompensation = 1;
RFReduction = 0;

%Lesser used settings
RFAmplitude = 10;
dataType = 'counter';
nDataPointDeviationTolerance = .015;
collectionDuration = (1/1.25)*1000;
collectionBufferDuration = 1000;

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
[ex.pulseBlaster,~] = Rabi_template(ex.pulseBlaster,parameters);

tauPulses = findPulses(ex.pulseBlaster,'notes','τ','contains');

for ii = 1:numel(tauPulses)
   ex.pulseBlaster = modifyPulse(ex.pulseBlaster,tauPulses(ii),'duration',myDurationSetting);
end

%Deletes any pre-existing scan
ex.scan = [];

scanInfo.address = findPulses(ex.pulseBlaster,'notes','AOM/DAQ delay compensation','matches');
% scanInfo.address(end+1:end+2) = findPulses(ex.pulseBlaster,'duration',799); %
scanInfo.bounds{1} = scanBounds;
scanInfo.bounds{2} = scanBounds;
% scanInfo.bounds{3} = 800-scanBounds; %
% scanInfo.bounds{4} = 800-scanBounds; %
scanInfo.nSteps = scanNSteps;
scanInfo.parameter = 'duration';
scanInfo.identifier = 'Pulse Blaster';
scanInfo.notes = 'Kyles sweep';

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

cont = checkContinue(timeoutDuration*2);
if ~cont
   return
end

%% Run scan, and collect and display data

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
   refData = zeros([ex.scan.nSteps 1]);
   
   while ~all(ex.odometer == [ex.scan.nSteps]) %While odometer does not match max number of steps

      %Takes the next data point. This includes incrementing the odometer and setting the instrument to the next value
      ex = takeNextDataPoint(ex,'pulse sequence');          

      con = zeros(1,ex.scan.nSteps);

      %The problem is that the odometer is 1 but the data point is 2?

      currentData = mean(createDataMatrixWithIterations(ex,ex.odometer),2);
      refData(ex.odometer) = currentData(1);
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
          if exist("refFig",'var') && ishandle(refFig)
            close(refFig)
          end
          xax = ex.scan.bounds{1}(1):ex.scan.stepSize:ex.scan.bounds{1}(2);
          averageFig = figure(1);          
          averageAxes = axes(averageFig); %#ok<LAXES>          
          iterationFig = figure(2);          
          iterationAxes = axes(iterationFig); %#ok<LAXES>          
          avgPlot = plot(averageAxes,xax,avgData);
          iterationPlot = plot(iterationAxes,xax,iterationData);
          refFig = figure(3);          
          refAxes = axes(refFig); %#ok<LAXES>          
          refPlot = plot(refAxes,xax,refData);
          title(averageAxes,'Average')
          ylabel(averageAxes,'contrast')
          title(iterationAxes,'Current')
          ylabel(iterationAxes,'contrast')
          title(refAxes,'Reference')
          ylabel(refAxes,'counts')
      else
          avgPlot.YData = avgData;
          iterationPlot.YData = iterationData;
          refPlot.YData = refData;
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