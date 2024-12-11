%stageLocations = ex.PIstage.axisSum;
%ex.PIstage = absoluteMove(ex.PIstage,'z',7500);
%ex.PIstage = relativeMove(ex.PIstage,'z',-50);
%% User Inputs
scanBounds = {[6700 6900]};
scanAxes = {'z'};
scanStepSize = {2.5};
sequenceTimePerDataPoint = .25;%Before factoring in forced delay and other pauses
p.nIterations = 1;
contrastVSReference = 'con';%'ref' or 'con'. If con, applies ODMR sequence but shows ref and con; if ref, uses fast sequence and only shows ref
RFfrequency = 2.41;

%Uncommonly changed parameters
dataType = 'counter';%'counter' or 'analog'
RFamplitude = 10;
timeoutDuration = 5;
forcedDelayTime = .125;

p.baselineSubtraction = 0;
p.plotAverageContrast = false;
p.plotAverageReference = false;
p.plotAverageSNR = false;
p.plotCurrentContrast = true;
p.plotCurrentReference = true;
p.plotCurrentSNR = true;
p.collectionType = 'counter';
p.boundsToUse = 1;
p.perSecond = true;

nDataPointDeviationTolerance = .00015;
scanNotes = 'Stage scan';

%% Backend

if ~exist('ex','var')
   ex = experiment;
end

if isempty(ex.pulseBlaster)
    fprintf('Connecting to pulse blaster...\n')
   ex.pulseBlaster = pulse_blaster('pulse_blaster_DEER');
   ex.pulseBlaster = connect(ex.pulseBlaster);
   fprintf('Pulse blaster connected\n')
end
if isempty(ex.SRS_RF) && strcmp(contrastVSReference,'con')
    fprintf('Connecting to SRS...\n')
   ex.SRS_RF = RF_generator('SRS_RF');
   ex.SRS_RF = connect(ex.SRS_RF);
   fprintf('SRS connected\n')
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

%Condensed version below puts this on one line
ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{},2500,'Initial buffer signal off');
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

%Adds each scan
for ii = 1:numel(scanBounds)
   scan.bounds = scanBounds{ii};
   scan.stepSize = scanStepSize{ii};
   scan.parameter = scanAxes{ii};
   scan.identifier = 'stage';
   scan.notes = scanNotes;

   ex = addScans(ex,scan);
end

%Adds time (in seconds) after pulse blaster has stopped running before continuing to execute code
ex.forcedCollectionPauseTime = forcedDelayTime;

ex.maxFailedCollections = 3;

ex.nPointsTolerance = nDataPointDeviationTolerance;

%Sends information to command window
% scanStartInfo(ex.scan.nSteps,ex.pulseBlaster.sequenceDurations.sent.totalSeconds + ex.forcedCollectionPauseTime*1.5,nIterations,.28)

cont = checkContinue(timeoutDuration*2);
if ~cont
    return
end


ex.optimizationInfo.enableOptimization = false;

ex = runScan(ex,p);