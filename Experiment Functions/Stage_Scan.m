function ex = Stage_Scan(ex,p)
%p is parameter structure

requiredParams = {'scanBounds','scanStepSize','scanAxes','collectionType'};

mustContainField(p,requiredParams)

paramsWithDefaults = {'plotAverageContrast',true;...
   'plotAverageReference',true;...
   'plotCurrentContrast',true;...
   'plotCurrentReference',true;...
   'plotCurrentPercentageDataPoints',false;...
   'plotAveragetPercentageDataPoints',false;...
   'plotAverageSNR',false;...
   'plotCurrentSNR',false;...
   'contrastVSReference','ref';...
   'RFAmplitude',10;...
   'RFFrequency',2.87;...
   'scanNotes','ODMR';...
   'sequenceTimePerDataPoint',.2;...
   'nIterations',1;...
   'timeoutDuration',10;...
   'forcedDelayTime',.125;...
   'nDataPointDeviationTolerance',.0001;...
   'baselineSubtraction',0;...
   'maxFailedCollections',3;...
   'optimizationEnabled',false;...
   'optimizationAxes',{'z'};...
   'optimizationSteps',{-2:.25:2};...
   'optimizationRFStatus','off';...
   'timePerOpimizationPoint',.1;...
   'timeBetweenOptimizations',180;...
   'percentageForcedOptimization',.75;...
   'pulseBlasterConfig','pulse_blaster_default';...
   'SRSRFConfig','SRS_RF';...
   'DAQConfig','daq_6361';...
   'stageConfig','PI_stage'};

p = mustContainField(p,paramsWithDefaults(:,1),paramsWithDefaults(:,2));

%This warning *should* be suppressed in the DAQ code but isn't for an unknown reason. This is not related to my code but
%rather the data acquisition toolbox code which I obviously can't change
warning('off','MATLAB:subscripting:noSubscriptsSpecified');

%This warning is for unreachable code. This will usually happen in this file dependant on user settings at the start
%#ok<*UNRCH>

%Creates experiment object if none exists
if ~exist('ex','var') || isempty(ex),   ex = experiment;   end

%Loads pulse blaster, srs rf, and daq with given configs
instrumentNames = ["pulse blaster","daq","stage"];
instrumentConfigs = [c2s(p.pulseBlasterConfig),c2s(p.DAQConfig),c2s(p.stageConfig)];
ex = loadInstruments(ex,instrumentNames,instrumentConfigs,false);

%Temporarily disables taking data and sets data channel to collectionType
ex.DAQ.takeData = false;
ex.DAQ.activeDataChannel = p.collectionType;

%Sets loops for entire sequence to "on". Deletes previous sequence if any existed
ex.pulseBlaster.nTotalLoops = 1;%will be overwritten later, used to find time for 1 loop
ex.pulseBlaster.useTotalLoop = true;
ex.pulseBlaster = deleteSequence(ex.pulseBlaster);

%Differences between contrast and signal
%Loading RF+settings
%DAQ continuous collection and signal differentiation
%Pulse sequence
%Whether some plotting is enabled
if strcmpi(p.contrastVSReference,'con')
   ex = loadInstruments(ex,"srs rf",c2s(p.SRSRFConfig),false);
   ex.SRS_RF.enabled = 'on';
   ex.SRS_RF.modulationEnabled = 'off';
   ex.SRS_RF.amplitude = p.RFAmplitude;
   ex.SRS_RF.frequency = p.RFFrequency;

   ex.DAQ.differentiateSignal = 'on';
   ex.DAQ.continuousCollection = 'on';

   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{},p.intermissionBufferDuration/2,'Initial buffer');
   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','DAQ'},1e6,'Reference');
   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','DAQ'},1e6,'Reference');
   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{},p.intermissionBufferDuration/2,'Middle buffer signal off');
   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'Signal'},p.intermissionBufferDuration/2,'Middle buffer signal on');
   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','DAQ','RF','Signal'},1e6,'Signal');
   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'Signal'},p.intermissionBufferDuration/2,'Final buffer');

elseif strcmpi(p.contrastVSReference,'ref')
   ex.DAQ.differentiateSignal = 'off';
   ex.DAQ.continuousCollection = 'off';

   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM'},p.intermissionBufferDuration,'Initial buffer');
   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','DAQ'},2e6,'Taking data');

   p.plotAverageContrast = false;
   p.plotCurrentContrast = false;
   p.plotAverageSNR = false;
   p.plotCurrentSNR = false;

else
   error('contrastVSReference must be "con" or "ref"')
end

%Gets duration of user sequence in order to change number of loops to match desired time for each data point
ex.pulseBlaster = calculateDuration(ex.pulseBlaster,'user');
ex.pulseBlaster.nTotalLoops = floor(p.sequenceTimePerDataPoint/ex.pulseBlaster.sequenceDurations.user.totalSeconds);

%Sends the currently saved pulse sequence to the pulse blaster instrument itself
ex.pulseBlaster = sendToInstrument(ex.pulseBlaster);

%Deletes any pre-existing scan
ex.scan = [];

scan.bounds = p.scanBounds; %RF frequency bounds
scan.stepSize = p.scanStepSize; %Step size for RF frequency
scan.parameter = 'frequency'; %Scan frequency parameter
scan.identifier = ex.SRS_RF.identifier; %Instrument has identifier 'SRS RF' (not needed if only one RF generator is connected)
scan.notes = p.scanNotes; %Notes describing scan (will appear in titles for plots)

%Adds each scan
for ii = 1:numel(p.scanBounds)
   scan.bounds = p.scanBounds{ii};
   scan.stepSize = p.scanStepSize{ii};
   scan.parameter = p.scanAxes{ii};
   scan.identifier = 'stage';
   scan.notes = scanNotes;

   ex = addScans(ex,scan);
end

%Adds time (in seconds) after pulse blaster has stopped running before continuing to execute code
ex.forcedCollectionPauseTime = p.forcedDelayTime;

%Number of failed collections before giving error
ex.maxFailedCollections = 5;

%Changes tolerance from .01 default to user setting
ex.nPointsTolerance = p.nDataPointDeviationTolerance;

%Checks if the current configuration is valid. This will give an error if not
ex = validateExperimentalConfiguration(ex,'pulse sequence');

ex.maxFailedCollections = p.maxFailedCollections;

%Sends information to command window
scanStartInfo(ex.scan.nSteps,ex.pulseBlaster.sequenceDurations.sent.totalSeconds + ex.forcedCollectionPauseTime*1.5,p.nIterations,.28)

%Asks for user input on whether to continue
cont = checkContinue(p.timeoutDuration*2);
if ~cont
    return
end

%Runs scan
ex = runScan(ex,p);
