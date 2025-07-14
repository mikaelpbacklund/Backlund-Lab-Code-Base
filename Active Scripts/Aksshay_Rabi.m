%Runs a simple Rabi sequence with no τ compensation or stage optimization

%Highly recommended to use a "time per data point" of at least 3 seconds
%Lower than this is sensitive to jitters in number of points collected,
%resulting in failed and/or erroneous points

%% User Inputs
p.scanBounds = [10 210];%ns
p.scanStepSize = 2;
p.scanNotes = 'Rabi'; %Notes describing scan (will appear in titles for plots)
p.nIterations = 1;
p.RFResonanceFrequency = 2.1775;
p.sequenceTimePerDataPoint = 5;%Before factoring in forced delay and other pauses
p.timeoutDuration = 10;
p.forcedDelayTime = .2;
%Offset for AOM pulses relative to the DAQ in particular
%Positive for AOM pulse needs to be on first, negative for DAQ on first
p.aomCompensation = 600;
p.RFReduction = 0;

%Lesser used settings
p.RFAmplitude = 10;
p.dataType = 'analog';
p.scanNSteps = [];%Will override step size if set
p.nDataPointDeviationTolerance = .01;
p.collectionDuration = (1/1.25)*1000;
p.collectionBufferDuration = 1000;

%% Loading Instruments
%See ODMR example script for instrument loading information
warning('off','MATLAB:subscripting:noSubscriptsSpecified');

if ~exist('ex','var'),  ex = experiment; end

if isempty(ex.pulseBlaster)
   ex.pulseBlaster = pulse_blaster('pulse_blaster_DEER');
   ex.pulseBlaster = connect(ex.pulseBlaster);
end
if isempty(ex.SRS_RF)
   ex.SRS_RF = RF_generator('SRS_RF');
   ex.SRS_RF = connect(ex.SRS_RF);
end
if isempty(ex.DAQ)
   ex.DAQ = DAQ_controller('daq_6361');
   ex.DAQ = connect(ex.DAQ);
end

%Sends RF settings
ex.SRS_RF.enabled = 'on';
ex.SRS_RF.modulationEnabled = 'off';
ex.SRS_RF.amplitude = p.RFAmplitude;
ex.SRS_RF.frequency = p.RFResonanceFrequency;

%Sends DAQ settings
ex.DAQ.takeData = false;
ex.DAQ.differentiateSignal = 'on';
ex.DAQ.activeDataChannel = p.dataType;

%% Use template to create sequence and scan

%Load empty parameter structure from template
[parameters,~] = Rabi_template([],[]);

%Set parameters
%Leaves intermissionBufferDuration, collectionDuration, repolarizationDuration, and collectionBufferDuration as default
parameters.RFResonanceFrequency = p.RFResonanceFrequency;
parameters.tauStart = p.scanBounds(1);
parameters.tauEnd = p.scanBounds(2);
parameters.scanBounds=p.scanBounds;
parameters.timePerDataPoint = p.sequenceTimePerDataPoint;
parameters.AOM_DAQCompensation = p.aomCompensation;
parameters.collectionBufferDuration = p.collectionBufferDuration;
parameters.collectionDuration = p.collectionDuration;
if ~isempty(p.scanNSteps) %Use number of steps if set otherwise use step size
   parameters.tauNSteps = p.scanNSteps;
else
   parameters.scanStepSize = p.scanStepSize;
end
parameters.RFReduction = p.RFReduction;

%Sends parameters to template
%Creates and sends pulse sequence to pulse blaster
%Gets scan information
[ex.pulseBlaster,scanInfo] = Rabi_template(ex.pulseBlaster,parameters);

%Deletes any pre-existing scan
ex.scan = [];

%Adds scan to experiment based on template output
ex = addScans(ex,scanInfo);

%Adds time (in seconds) after pulse blaster has stopped running before continuing to execute code
ex.forcedCollectionPauseTime = p.forcedDelayTime;

%Changes tolerance from .01 default to user setting
ex.nPointsTolerance = p.nDataPointDeviationTolerance;

ex.maxFailedCollections = 3;

%Checks if the current configuration is valid. This will give an error if
%not #ANR: I commented it out since this is a deprecated function
%ex = validateExperimentalConfiguration(ex,'pulsesequence');

%Sends information to command window
scanStartInfo(ex.scan.nSteps,ex.pulseBlaster.sequenceDurations.sent.totalSeconds + ex.forcedCollectionPauseTime*1.5,p.nIterations,.28)

cont = checkContinue(p.timeoutDuration*4);
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

for ii = 1:p.nIterations

   %Prepares scan for a fresh start while keeping data from previous
   %iterations
   ex = resetScan(ex);

   iterationData = zeros([ex.scan.nSteps 1]);

   %While the odometer is not at its max value
   while ~all(cell2mat(ex.odometer) == [ex.scan.nSteps]) %While odometer does not match max number of steps

      ex = takeNextDataPoint(ex,'pulse sequence');

      %The problem is that the odometer is 1 but the data point is 2?

      currentData = mean(createDataMatrixWithIterations(ex,ex.odometer{:}),2);
      currentData = (currentData(1)-currentData(2))/currentData(1);
      avgData(ex.odometer{:}) = currentData;
      currentData = ex.data.values{ex.odometer{:},end};
      currentData = (currentData(1)-currentData(2))/currentData(1);
      iterationData(ex.odometer{:}) = currentData;

      if ~exist("averageFig",'var') || ~ishandle(averageAxes) || (ex.odometer{:} == 1 && ii == 1)
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

   if ii ~= p.nIterations
       cont = checkContinue(p.timeoutDuration);
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
