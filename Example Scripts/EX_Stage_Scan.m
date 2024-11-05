%% User Inputs
scanBounds = {[0 100],[200 300],[7500 7600]};
scanAxes = {'x','y','z'};
scanStepSize = {10,5,2};
sequenceTimePerDataPoint = .5;%Before factoring in forced delay and other pauses
nIterations = 1;
contrastVSReference = 'ref';%'ref' or 'con'. If con, applies ODMR sequence but shows ref and con; if ref, uses fast sequence and only shows ref
RFfrequency = 2.87;

%Uncommonly changed parameters
dataType = 'counter';%'counter' or 'analog'
RFamplitude = 10;
timeoutDuration = 5;
forcedDelayTime = .125;
nDataPointDeviationTolerance = .00015;
scanNotes = 'Stage scan';

%% Backend

if ~exist('ex','var')
   ex = experiment;
end

if isempty(ex.pulseBlaster)
   ex.pulseBlaster = pulse_blaster('pulse_blaster_DEER');
   ex.pulseBlaster = connect(ex.pulseBlaster);
end

if isempty(ex.DAQ)
   ex.DAQ = DAQ_controller('3rd_setup_daq');
   ex.DAQ = connect(ex.DAQ);
end

if isempty(ex.PIstage) || ~ex.PIstage.connected
    ex.PIstage = stage('PI_stage');
    ex.PIstage = connect(ex.PIstage);
end

ex.DAQ.takeData = false;
ex.DAQ.activeDataChannel = dataType;

ex.pulseBlaster.nTotalLoops = 1;%will be overwritten later, used to find time for 1 loop
ex.pulseBlaster.useTotalLoop = true;
ex.pulseBlaster = deleteSequence(ex.pulseBlaster);

if strcmpi(contrastVSReference,'con')
   if isempty(ex.SRS_RF) %#ok<*UNRCH>
      ex.SRS_RF = RF_generator('SRS_RF');
      ex.SRS_RF = connect(ex.SRS_RF);
   end

   ex.SRS_RF.enabled = 'on';
   ex.SRS_RF.modulationEnabled = 'off';
   ex.SRS_RF.amplitude = RFamplitude;
   ex.SRS_RF.frequency = RFfrequency;

   ex.DAQ.differentiateSignal = true;
   ex.DAQ.continuousCollection = true;

   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{},2500,'Initial buffer');
   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','DAQ'},1e6,'Reference');
   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','DAQ'},1e6,'Reference');
   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{},2500,'Middle buffer signal off');
   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'Signal'},2500,'Middle buffer signal on');
   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','DAQ','RF','Signal'},1e6,'Signal');
   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'Signal'},2500,'Final buffer');
else
   ex.DAQ.differentiateSignal = false;
   ex.DAQ.continuousCollection = false;

   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM'},500,'Initial buffer');
   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','DAQ'},1e6,'Taking data');
end

ex.pulseBlaster = calculateDuration(ex.pulseBlaster,'user');

%Changes number of loops to match desired time for each data point
ex.pulseBlaster.nTotalLoops = floor(sequenceTimePerDataPoint/ex.pulseBlaster.sequenceDurations.user.totalSeconds);

ex.pulseBlaster = sendToInstrument(ex.pulseBlaster);

ex.scan = [];

scan.bounds = scanBounds;
scan.stepSize = scanStepSize;
scan.parameter = scanAxes;
scan.identifier = cell(1,numel(scanBounds));
scan.identifier = deal('stage');%sets all identifiers as stage instrument
scan.notes = scanNotes;

ex = addScans(ex,scan);

%Adds time (in seconds) after pulse blaster has stopped running before continuing to execute code
ex.forcedCollectionPauseTime = forcedDelayTime;

ex.maxFailedCollections = 3;

ex.nPointsTolerance = nDataPointDeviationTolerance;

%Sends information to command window
scanStartInfo(ex.scan.nSteps,ex.pulseBlaster.sequenceDurations.sent.totalSeconds + ex.forcedCollectionPauseTime*1.5,nIterations,.28)

cont = checkContinue(timeoutDuration*2);
if ~cont
    return
end

%% Running Scan
try
ex = resetAllData(ex,[0,0]);

for ii = 1:nIterations
   
   ex = resetScan(ex);
   
   while ~all(ex.odometer == [ex.scan.nSteps]) %While odometer does not match max number of steps

      ex = takeNextDataPoint(ex,'pulse sequence');               

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

   if ii ~= nIterations
       fprintf('Finished iteration %d\n',ii)

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