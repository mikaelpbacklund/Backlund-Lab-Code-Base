%Runs a simple Rabi sequence with no τ compensation or stage optimization

%% User Inputs
scanBounds = [450 600];%ns
scanStepSize = 10;
scanNotes = 'Rabi'; %Notes describing scan (will appear in titles for plots)
nIterations = 1;
RFFrequency = 2.0625;
sequenceTimePerDataPoint = 1.5;%Before factoring in forced delay and other pauses
timeoutDuration = 10;
forcedDelayTime = .15;
%Offset for AOM pulses relative to the DAQ in particular
%Positive for AOM pulse needs to be on first, negative for DAQ on first
aomCompensation = 400;
RFReduction = 0;

%Lesser used settings
RFAmplitude = 10;
dataType = 'analog';
scanNSteps = [];%Will override step size if set
nDataPointDeviationTolerance = .001;

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

%Add the current scan
ex = addScans(ex,scanInfo);

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
      ex = plotData(ex,nPoints,'n points');
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

